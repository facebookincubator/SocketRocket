//
//  WebSocketProtocolTest.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/7/16.
//
//

import Foundation
import XCTest
import RxSwift

@testable import SocketRocket
@testable import SocketRocketIO

/// Example frames from the RFC
struct ExampleFrames {
    ///    A single-frame unmasked text message
    /// contains "Hello"
    static let singleFrameUnmasked: [UInt8] = [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
    
    // A single-frame masked text message
    static let singleFrameMasked: [UInt8] = [0x81,0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
    
    // A fragmented unmasked text message
    // Contains "Hel" then "lo"
    static let fragmentedUnmasked: [UInt8] =
        [0x01, 0x03, 0x48, 0x65, 0x6c] +
        [0x80, 0x02, 0x6c, 0x6f]
    
    /// Unmasked Ping request
    static let unmaskedPingRequest: [UInt8] = [0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
    
    /// Unmasked Ping response
    static let maskedPingResponse: [UInt8] = [0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
    
    static let shortBinaryMessageContents = (0..<256).map { UInt8($0 % 0xFF) }
    
    /// Binary message that is 256 long
    static let shortBinaryMessage: [UInt8] = [0x82, 0x7E, 0x01, 0x00] + shortBinaryMessageContents
    
    
    static let longBinaryMessageContents = (0..<65536).map { UInt8($0 % 0xFF) }


    /// Binary message that is 65536 long
    static let longBinaryMessage: [UInt8] = [0x82, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00] + longBinaryMessageContents
}

class WebSocketProtocolTests : XCTestCase {
    func testSingleFrameUnmasked() {
        let frame = readFrame(ExampleFrames.singleFrameUnmasked)
        
        XCTAssertEqual(frame.opCode, .Text)
        XCTAssertTrue(frame.header.fin)
        XCTAssertFalse(frame.header.mask)
        XCTAssertNil(frame.header.maskingKey)
        
        XCTAssertEqual(frame.payload.utf8String, "Hello")

    }
    
    func testSingleFrameMasked() {
        /// TODO: Unmask frame data
        let frame = readFrame(ExampleFrames.singleFrameMasked)
        
        XCTAssertEqual(frame.opCode, .Text)
        XCTAssertTrue(frame.header.fin)
        XCTAssertTrue(frame.header.mask)
        XCTAssertNotNil(frame.header.maskingKey)
        
        XCTAssertEqual(frame.payload.utf8String, "Hello")
    }
    
    func testFragmentedUnmasked() {
        /// TODO: Unmask frame data
        let frames = readFrames(ExampleFrames.fragmentedUnmasked)
        XCTAssertEqual(frames.count, 2)
        
        let frame1 = frames[0]
        
        let frame2 = frames[1]
        
        XCTAssertEqual(frame1.opCode, .Text)
        XCTAssertFalse(frame1.header.fin)
        XCTAssertFalse(frame1.header.mask)
        XCTAssertNil(frame1.header.maskingKey)
        XCTAssertEqual(frame1.payload.utf8String, "Hel")
        
        XCTAssertEqual(frame2.opCode, .Continuation)
        XCTAssertTrue(frame2.header.fin)
        XCTAssertFalse(frame2.header.mask)
        XCTAssertNil(frame2.header.maskingKey)
        XCTAssertEqual(frame2.payload.utf8String, "lo")
    }
    
    
    func testPingUnmasked() {
        /// TODO: Unmask frame data
        let frame = readFrame(ExampleFrames.unmaskedPingRequest)
        
        XCTAssertEqual(frame.opCode, .Ping)
        XCTAssertEqual(frame.payload.utf8String, "Hello")
        XCTAssertTrue(frame.header.fin)
        XCTAssertFalse(frame.header.mask)
        XCTAssertNil(frame.header.maskingKey)
    }
    
    
    func testPongUnmasked() {

        let frame = readFrame(ExampleFrames.maskedPingResponse)
        
        XCTAssertEqual(frame.opCode, .Pong)
        XCTAssertEqual(frame.payload.utf8String, "Hello")
        XCTAssertTrue(frame.header.fin)
        XCTAssertTrue(frame.header.mask)
        XCTAssertNotNil(frame.header.maskingKey)
    }


    func testShortMessageUnmasked() {
        /// TODO: Unmask frame data
        let frame = readFrame(ExampleFrames.shortBinaryMessage)
        
        XCTAssertEqual(frame.payload, ExampleFrames.shortBinaryMessageContents)
        
        XCTAssertEqual(frame.opCode, .Binary)
        XCTAssertTrue(frame.header.fin)
        XCTAssertFalse(frame.header.mask)
        XCTAssertNil(frame.header.maskingKey)
    }
    
    func testLongMessageUnmasked() {
        /// TODO: Unmask frame data
        let frame = readFrame(ExampleFrames.longBinaryMessage)
        
        XCTAssertEqual(frame.payload, ExampleFrames.longBinaryMessageContents)
        
        XCTAssertEqual(frame.opCode, .Binary)
        XCTAssertTrue(frame.header.fin)
        XCTAssertFalse(frame.header.mask)
        XCTAssertNil(frame.header.maskingKey)
    }
    
    private func readFrame(data: [UInt8], file: String = __FILE__, line: UInt = __LINE__) -> MaterializedWebsocketFrame {
        let vals = self.readFrames(data, file: file, line: line)
        XCTAssertEqual(vals.count, 1)
        return vals.first!
    }
    
    
    private func readFramesFromStream<I: InputStream where I.Element == UInt8>(stream: I) -> [MaterializedWebsocketFrame] {
        let frameReader = WebSocketFrameReader(stream: stream)
        
        let frames = frameReader
            .readFrames(MainScheduler.instance)
            .flatMap { $0.materialized() }
            .subscribeFuture(self)
            .get(timeout: 600)
        
        for f in frames {
            XCTAssertTrue(f.header.isComplete)
        }
        
        return frames
    }
    
    private func readFrames(data: [UInt8], file: String = __FILE__, line: UInt = __LINE__) -> [MaterializedWebsocketFrame] {

        let eagerStream1Chunk = Observable
            .just(data)
            .asInputStream()
        
        let eagerStreamSeveralChunk = data
            .toObservable()
            .toArray()
            .asInputStream()
        
        let queue = dispatch_queue_create("testQueue", DISPATCH_QUEUE_SERIAL)
        
        let lazySingleObservable: Observable<[UInt8]> = Observable.create { observer in
            dispatch_async(queue) {
                observer.onNext(data)
                observer.onCompleted()
            }
            
            return NopDisposable.instance
        }
        
        let lazyIndividualObservable: Observable<[UInt8]> = Observable.create { observer in
            for byte in data {
                dispatch_async(queue) {
                    observer.onNext([byte])
                }
            }
            
            dispatch_async(queue) {
                observer.onCompleted()
            }
            return NopDisposable.instance
        }
        
        
        /// We're going to try multiple different ways to produce this data
        let streams: [AnyInputStream<UInt8>] = [
            anyInputStream(eagerStream1Chunk),
            anyInputStream(eagerStreamSeveralChunk),
            anyInputStream(lazySingleObservable.asInputStream()),
            anyInputStream(lazyIndividualObservable.asInputStream()),
        ]
        
        
        let frames = streams
            .map(readFramesFromStream)

        for f in frames.flatten() {
            XCTAssertEqual(f.payload.count, f.header.payloadLen)
        }
        
        var lastFrames: [MaterializedWebsocketFrame]?
        for (i, f) in frames.enumerate() {
            if let last = lastFrames {
                /// Fail twice so we know which test is bad too
                XCTAssertEqual(last, f, "\(i) stream failed", file:file, line:line)
                XCTAssertEqual(last, f, "\(i) stream failed")
            }
            lastFrames = f
        }
        
        return frames.first!
    }
}

extension WebSocketFrame {
    func materialized() -> Observable<MaterializedWebsocketFrame> {
        return Observable.create { observer in
            var buffer = [UInt8]()
            let header = self.header
            
            return self
                .payload
                .subscribe { event in
                    switch event {
                    case .Completed:
                        let materialized = MaterializedWebsocketFrame(header: header, payload: buffer)
                        observer.onNext(materialized)
                        observer.onCompleted()
                    case let .Error(e):
                        observer.onError(e)
                    case let .Next(val):
                        buffer.appendContentsOf(val)
                    }
            }
        }
    }
}

/// A websocket frame that is comparable that has the data consumed already.
struct MaterializedWebsocketFrame : Equatable {
    let header: WebSocketFrameHeader
    let payload: [UInt8]
    
    var opCode: WebSocketOpcode? {
        return WebSocketOpcode(rawValue: self.header.opcode)
    }
}

func == (lhs: MaterializedWebsocketFrame, rhs: MaterializedWebsocketFrame) -> Bool {
    return lhs.header == rhs.header && lhs.payload == rhs.payload
}