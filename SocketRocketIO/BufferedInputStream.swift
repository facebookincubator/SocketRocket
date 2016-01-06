//
//  BufferedReading.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/11/15.
//
//

import Foundation
import RxSwift

private enum BufferedReadRequestType<C: CollectionType> {
    
    /// If splitfunc finds a match
    ///
    /// - parameter currentBuffer: current buffer to match against
    /// - parameter atEnd: if we're at the end of the file. If there's no guaranteed match, the function should throws
    typealias SplitFunc = (currentBuffer: C, atEnd: Bool) throws -> (sizeToProduce: C.Index.Distance, finished: Bool)
    
    case Size(sizeRequested: C.Index.Distance)
    case OnSplit(splitFunc: SplitFunc)
}

private struct PendingReadRequest<O: ObserverType where O.E: CollectionType> {
    typealias C = O.E
    typealias RequestType = BufferedReadRequestType<C>
    
    init(type: RequestType, observer: O) {
        self.type = type
        self.observer = observer
    }
    
    /// Contains the request type
    let type: RequestType
    
    let observer: O
    
    /// How much we have produced so far
    var countProduced: C.Index.Distance = 0
}

/// We will try to read this much when trying to buffer for split requests
private let defaultChunkSizeForSplit = 2048

public protocol SplittableInputStream : StreamBase {
    func read(splitFunc splitFunc: (currentBuffer: UnsafeBufferPointer<Element>, atEnd: Bool) throws -> (sizeToProduce: Int, finished: Bool)) -> Observable<UnsafeBufferPointer<Element>>
}

public class BufferedInputStream<Wrapped: InputStream> : InputStream, SplittableInputStream {
    private let stream: Wrapped
    
    public typealias Element = Wrapped.Element
    
    private var buffer = Array<Wrapped.Element>()
    
    private typealias PendingRequest = PendingReadRequest<AnyObserver<UnsafeBufferPointer<Wrapped.Element>>>

    private var lock = SpinLock()

    /// The following must only read or mutated within a lock
    private var pendingRequests = [PendingRequest]()
    private var readingInProgress = false
    
    /// These are to be called after we're unlocked
    private var deferredCalls = Array<() -> ()>()
    
    /// This is set if we get any error back from the stream. Subsequent requests will
    private var failError: ErrorType?
    
    /// TODO: make this work
    private var atEOF = false
    
    
    private var isOkToDeferCall = false
    
    /// Disposable for reading
    private var currentDisposable: Disposable? = nil
    
    private var outstandingBytes: Int = 0
    
    private var reachedEnd = false
    
    
    private func locked(@noescape body: ()  throws -> ()) rethrows {
        let deferredCalls: [() -> ()] = try self.lock.locked {
            isOkToDeferCall = true
            try body()

            defer {
                isOkToDeferCall = false
                self.deferredCalls.removeAll()
            }
            return self.deferredCalls
        }
        
        for c in deferredCalls {
            c()
        }
    }
    
    private func deferCall(call: () -> ()) {
        precondition(isOkToDeferCall)
        deferredCalls.append(call)
    }
    
    init(stream: Wrapped) {
        self.stream = stream
    }
    
    deinit {
        self.currentDisposable?.dispose()
    }
    
    private func pump() {
        locked {
            do {
                if readingInProgress {
                    return
                }
                
                if pendingRequests.isEmpty {
                    return
                }
                
                // If we have an error, fail all pending requests
                if let error = failError {
                    let requests = pendingRequests
                    pendingRequests.removeAll()
                    
                    deferCall {
                        for r in requests {
                            r.observer.onError(error)
                        }
                    }
                    return
                }

                /// Consume buffer until we can't anymore
                repeat {
                } while (try tryConsumeBuffer() > 0)
                
                
                
                // If we reached the end of the stream then we want to flush all the existing requests
                if reachedEnd {
                    let requests = pendingRequests
                    pendingRequests.removeAll()
                    
                    deferCall {
                        for r in requests {
                            r.observer.onCompleted()
                        }
                    }
                    return
                    
                }
                
                guard let nextRequest = pendingRequests.first else {
                    return
                }
                
                /// Now we take our next request and fetch data for it
                
                let readSize: Int

                switch nextRequest.type {
                case .OnSplit:
                    readSize = defaultChunkSizeForSplit
                case let .Size(sizeRequested: requested):
                    /// We should have already consumed this if it were the case
                    precondition(self.buffer.count < requested)
                    readSize = requested - self.buffer.count
                }

                precondition(!readingInProgress)
                precondition(currentDisposable == nil)
                readingInProgress = true
                precondition(outstandingBytes == 0)
                outstandingBytes = readSize

                deferCall { self.requestData(readSize) }
                
            } catch let e  {
                /// If we failed, we want to re-run pump
                failWhileLocked(e)
                
                deferCall { self.pump() }
            }
        }
    }
    
    public func read(count: Int) -> Observable<UnsafeBufferPointer<Element>> {
        return self.read(.Size(sizeRequested: count))
    }
    
    public typealias SplitFunc = (currentBuffer: UnsafeBufferPointer<Element>, atEnd: Bool) throws -> (sizeToProduce: Int, finished: Bool)

    public func read(splitFunc splitFunc: SplitFunc) -> Observable<UnsafeBufferPointer<Element>> {
        return self.read(.OnSplit(splitFunc: splitFunc))
    }
    
    private func requestData(count: Int) {
        precondition(currentDisposable == nil)
        precondition(readingInProgress)
        
        let compositeDisposable = CompositeDisposable()
        self.currentDisposable = compositeDisposable
        let disposable = self
            .stream
            .read(count)
            .subscribe(self.handle)
        
        compositeDisposable.addDisposable(disposable)
    }
    
    private func handle(event: Event<UnsafeBufferPointer<Wrapped.Element>>) {
        locked  {
            switch event {
            case .Completed:
                currentDisposable?.dispose()
                currentDisposable = nil
                readingInProgress = false
                
                // If we requested more bytes than we received, we have reached the end of input stream
                if outstandingBytes > 0 {
                    reachedEnd = true
                }
            case let .Next(value):
                
                outstandingBytes -= value.count
                precondition(outstandingBytes >= 0)
                
                do {
                    try consumeNewData(value)
                } catch let e  {
                    failWhileLocked(e)
                }
            case let .Error(e):
                failWhileLocked(e)
            }
        }
        pump()
    }
    
    private func failWhileLocked(e: ErrorType) {
        readingInProgress = false
        self.failError = e
        currentDisposable?.dispose()
        currentDisposable = nil
    }
    
    /// Produces data to the pending requests
    private func consumeNewData(newData: UnsafeBufferPointer<Wrapped.Element>) throws {
        repeat {
        } while (try tryConsumeBuffer() > 0)
        
        // if the buffer is empty we can try to consume the new data. Otherwise, append to buffer
        if buffer.isEmpty {
            let consumed = try tryConsumeData(newData)
            buffer.appendContentsOf(newData[consumed..<newData.endIndex])
        } else {
            // if the buffer isn't empty, just append the contents
            buffer.appendContentsOf(newData)
            // Try to consume the buffer again just in case
        }
        
        repeat {
        } while (try tryConsumeBuffer() > 0)
    }

    /// Attemps to consume buffered data. Must be called while locked
    private func tryConsumeBuffer() throws -> Int {
        if buffer.isEmpty {
            return 0
        }
        let consumed = try buffer.withUnsafeBufferPointer(tryConsumeData)
        if consumed > 0 {
            buffer.removeFirst(consumed)
        }
        return consumed
    }

    /// Attempts to consume the data passed in. Must be called while locked
    @warn_unused_result
    private func tryConsumeData(data: UnsafeBufferPointer<Wrapped.Element>) throws -> Int  {
        guard var request = self.pendingRequests.first else {
            /// if we don't have any pending requests, we didn't consume any
            return 0
        }
        
        let sizeToProduce: Int
        let finished: Bool
        
        switch request.type {
        case let .OnSplit(splitFunc: splitFunc):
            (sizeToProduce, finished) = try buffer.withUnsafeBufferPointer { try splitFunc(currentBuffer: $0, atEnd: atEOF) }
        case let .Size(sizeRequested: requestedSize):
            let sizeRemaining = requestedSize - request.countProduced
            sizeToProduce = min(data.count, sizeRemaining)
            finished = sizeRemaining - sizeToProduce == 0
        }
        
        if finished {
            self.pendingRequests.removeFirst()
        } else {
            request.countProduced += sizeToProduce
            pendingRequests[0] = request
        }
        
        
        if sizeToProduce > 0 {
            precondition(sizeToProduce <= data.count)
            let dataToProduce = sizeToProduce == data.count ? data : UnsafeBufferPointer(start: data.baseAddress, count: sizeToProduce)
            request.observer.onNext(dataToProduce)
        }
        
        if finished {
            deferCall {
                request.observer.onCompleted()
            }
        }
        
        return sizeToProduce
    }
    
    private func read(requestType: PendingRequest.RequestType) -> Observable<UnsafeBufferPointer<Element>> {
        return Observable.create { observer in
            let request = PendingRequest(type: requestType, observer: observer)
            
            self.lock.locked {
                self.pendingRequests.append(request)
            }
            
            self.pump()
            
            return NopDisposable.instance
        }
    }
}

private let crlf: [UInt8] = [UInt8]("\r\n".utf8)
private let crlfCrlf: [UInt8] = crlf + crlf

let crlfSplitFunc = makeSplitFunc(crlf)
let crlfCrlfSplitFunc = makeSplitFunc(crlfCrlf)

private func makeSplitFunc<E: Equatable
    >(separator: [E]) -> (currentBuffer: UnsafeBufferPointer<E>, atEnd: Bool) throws -> (sizeToProduce: Int, finished: Bool) {
    let separatorCount = separator.count
    return { currentBuffer, atEnd in       
        
        var lastPartialMatchCount = 0
        continueLabel:
        for startPos in currentBuffer.startIndex..<(currentBuffer.startIndex.advancedBy(currentBuffer.count)) {
            for checkOffset in 0..<separatorCount {
                if startPos.advancedBy(checkOffset) >= currentBuffer.endIndex {
                    lastPartialMatchCount = checkOffset
                    break continueLabel
                }
                if currentBuffer[startPos + checkOffset] != separator[checkOffset] {
                    continue continueLabel
                }
            }
            // if we got to here, we have a match!
            return (startPos + separatorCount, true)
        }
        
        
        /// If we got this far, we can produce all data up to the length
        
        // We need to keep any data that we had a partial match with
        return (currentBuffer.count - lastPartialMatchCount, false)
    }
}

extension SplittableInputStream where Element == UInt8 {
    /// Yields elements until line is read. It may produce multiple chunks
    public func readLine() -> Observable<UnsafeBufferPointer<Element>> {
        return read(splitFunc: crlfSplitFunc)
    }
    
    /// Reads until we get a '\r\n\r\n'. Useful for reading HTTP header
    public func readCrlfCrlf() -> Observable<UnsafeBufferPointer<Element>> {
        return read(splitFunc: crlfCrlfSplitFunc)
    }
}

