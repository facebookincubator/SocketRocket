//
//  WebSocketProtocol.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/6/16.
//
//

import Foundation
import RxSwift
import SocketRocketIO

public protocol MessageOutputStream {
    
    /// This is the raw way to write messages. This probably shouldn't be used by general implementations (it is unsafe). By using unsafeBufferPointer we can avoid most copying of data
    func writeMessageRaw(buffers: Observable<UnsafeBufferPointer<UInt8>>)
}

public protocol MessageInputStream {
    @warn_unused_result
    func readMessagesRaw(scheduler: ImmediateSchedulerType) -> Observable<Observable<UnsafeBufferPointer<UInt8>>>
}

private let controlFrameRange = 0x8..<0xF

func == (lhs: WebSocketFrameHeader, rhs: WebSocketFrameHeader) -> Bool {
    return lhs.fin == rhs.fin
        && lhs.opcode == rhs.opcode
        && lhs.mask == rhs.mask
        && lhs.payloadLen == rhs.payloadLen
        && lhs.maskingKey == rhs.maskingKey
}

struct WebSocketFrameHeader : Equatable {
    let fin: Bool
    let opcode: Int // We're not using normal opcodes for this incase they're undefined
    let mask: Bool
    
    let payloadLen: Int
    
    let maskingKey: UInt32?
    
    static let initialBytesNeeded = 2
    
    /// Constructs a complete frame
    /// Mask is inferred based on maskingKey
    init(fin: Bool, opcode: WebSocketOpcode, payloadLen: Int, maskingKey: UInt32? = nil) {
        self.fin = fin
        self.mask = maskingKey != nil
        self.maskingKey = maskingKey
        self.payloadLen = payloadLen
        self.opcode = opcode.rawValue
    }
    
    /// Whether or not we're just the first part of a frame
    var isComplete: Bool {
        if mask && self.maskingKey == nil {
            return false
        }
        
        if payloadLen  == 126 || payloadLen == 127 {
            return false
        }
        
        return true
    }
    
    /// Initializes from 16 bits of data.
    init(data: UnsafeBufferPointer<UInt8>) {
        precondition(data.count == WebSocketFrameHeader.initialBytesNeeded, "Must only initialize with 16 bits of data")
        
        let firstByte = data[data.startIndex]
        let secondByte = data[data.startIndex.advancedBy(1)]
        
        fin = firstByte & 0b1000_0000 != 0
        opcode = Int(firstByte & 0b0000_1111)
        mask = secondByte & 0b1000_0000 != 0
        payloadLen = Int(secondByte & 0b0111_1111)
        maskingKey = nil
    }
    
    /// Constructor for creating a websocket with additional data
    init(original: WebSocketFrameHeader, additionalData: UnsafeBufferPointer<UInt8>) {
        precondition(original.additionalBytesNeeded == additionalData.count)
        
        self.fin = original.fin
        self.opcode = original.opcode
        self.mask = original.mask
        
        let maskOffset: Int
        // Now we have to read the payload length
        switch original.payloadLen {
        case 126:
            var networkOrderLen: UInt16 = 0
            let lenSize = sizeofValue(networkOrderLen)
            memcpy(&networkOrderLen, additionalData.baseAddress, lenSize)
            payloadLen = Int(networkOrderLen.bigEndian)
            maskOffset = lenSize
        case 127:
            var networkOrderLen: UInt64 = 0
            let lenSize = sizeofValue(networkOrderLen)
            memcpy(&networkOrderLen, additionalData.baseAddress, lenSize)
            payloadLen = Int(networkOrderLen.bigEndian)
            maskOffset = lenSize
        default:
            payloadLen = original.payloadLen
            maskOffset = 0
        }
        
        /// If there's a mask we need to read that
        if mask {
            let startPtr = additionalData.baseAddress.advancedBy(maskOffset)
            var key: UInt32 = 0
            memcpy(&key, startPtr, sizeofValue(key))
            maskingKey = key
        } else {
            maskingKey = nil
        }
    }
    
    /// These are additional bytes we need to complete the frame. This accounts of additional
    var additionalBytesNeeded: Int {
        let extendedPayloadNeeded: Int
        
        switch self.payloadLen {
        case 126:
            extendedPayloadNeeded = 2
        case 127:
            extendedPayloadNeeded = 8
        default:
            extendedPayloadNeeded = 0
        }
        
        let maskingLengthNeeded = mask ? sizeof(UInt32) : 0
        
        return extendedPayloadNeeded + maskingLengthNeeded
    }
    
    
    var isControlFrame : Bool {
        return controlFrameRange.contains(opcode)
    }
}

public struct WebSocketFrame {
    let header: WebSocketFrameHeader
    let payload: Observable<UnsafeBufferPointer<UInt8>>
}

public struct WebSocketFrameReader<I: InputStream where I.Element == UInt8>  {
    let stream: I
    
    public init(stream: I) {
        self.stream = stream
    }
    
    @warn_unused_result
    private func readFrameHeader() -> Observable<WebSocketFrameHeader> {
        return self.stream
            .readAndBufferExactly(WebSocketFrameHeader.initialBytesNeeded, allowEmpty: true)
            .map { WebSocketFrameHeader(data: $0) }
            .flatMap { header -> Observable<WebSocketFrameHeader> in
                /// Read more of the header if we need to
                switch header.additionalBytesNeeded {
                case 0:
                    return Observable.just(header)
                    
                case let needed:
                    return self
                        .stream
                        .readAndBufferExactly(needed)
                        .map { WebSocketFrameHeader(original: header, additionalData: $0) }
                }
        }
    }
    
    @warn_unused_result
    private func readFrame() -> Observable<WebSocketFrame> {
        return readFrameHeader()
            .map { header -> WebSocketFrame in
                let payload: Observable<UnsafeBufferPointer<UInt8>>
                
                precondition(header.isComplete)
                
                if header.payloadLen == 0 {
                    payload = Observable.empty()
                } else {
                    if let maskingKey = header.maskingKey {
                        payload = self.stream.readExactly(header.payloadLen).mask(maskingKey)
                    } else {
                        payload = self.stream.readExactly(header.payloadLen)
                    }
                }
                
                return WebSocketFrame(header: header, payload: payload)
        }
    }
    
    @warn_unused_result
    public func readFrames(scheduler: ImmediateSchedulerType) -> Observable<WebSocketFrame> {
        return Observable.create { observer in
            let disposable = SerialDisposable()
            
            func doNext() -> Disposable {
                var seenOne = false
                return self
                    .readFrame()
                    .subscribe { e in
                        switch e {
                        case let .Next(v):
                            seenOne = true
                            /// Rewrite the payload to have a side effect of pumping the next frame once it is completely read
                            let newPayload = v.payload.doOn { e in
                                switch e {
                                    /// We can start reading the next one once they've finished this one
                                case .Completed:
                                    disposable.disposable = doNext()
                                    /// If there's an error reading the data, then propagate that to our observer as well
                                case let .Error(e):
                                    observer.onError(e)
                                default:
                                    break
                                }
                            }
                            
                            let newFrame = WebSocketFrame(header: v.header, payload: newPayload)
                            
                            observer.onNext(newFrame)
                        case .Error:
                            observer.on(e)
                        case .Completed:
                            /// If we didn't see one, we're at the end of the stream
                            if !seenOne {
                                observer.onCompleted()
                            }
                        }
                }
            }
            
            disposable.disposable = doNext()
            
            return disposable
        }
    }
}

extension ObservableType where E == UnsafeBufferPointer<UInt8> {
    /// This will mask or unmask the data via xor
    /// TODO: make buffer size configurable
    /// Not thread safe
    func mask(mask: UInt32) -> Observable<UnsafeBufferPointer<UInt8>> {
        var mask = mask
        
        return Observable.create { observer in
            var writeBuffer = [UInt8]()
            var lastOffset = 0
            
            return self
                .subscribe { evt in
                    switch evt {
                    case let .Next(data):
                        withUnsafePointer(&mask) { ptr in
                            let keyBytesStart = unsafeBitCast(ptr, UnsafePointer<UInt8>.self)
                            let keyLen = sizeof(UInt32)
                            assert(writeBuffer.isEmpty)
                            writeBuffer.reserveCapacity(data.count)
                            
                            // TODO: determine if this slows us down too much
                            for (i, byte) in data.enumerate() {
                                writeBuffer.append(byte ^ keyBytesStart.advancedBy((i + lastOffset) % keyLen).memory)
                            }
                            
                            lastOffset += data.count
                        }
                        
                        writeBuffer.withUnsafeBufferPointer { ptr in
                            observer.onNext(ptr)
                        }
                        
                        writeBuffer.removeAll(keepCapacity: true)
                    case .Error, .Completed:
                        observer.on(evt)
                    }
            }
        }
    }
}

/// Handles the wire format of a websocket. This is pretty much everything past a handshake. It is server/client agnostic
public class WebSocketProtocol {
    
}

/// Default contains implementation is O(N) for range. This is much faster
extension Range {
    public func contains(element: Element) -> Bool {
        return startIndex.distanceTo(element) >= 0 &&  endIndex.distanceTo(element) < 0
    }
}
