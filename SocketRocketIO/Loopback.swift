//
//  Loopback.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/6/16.
//
//

import Foundation
import RxSwift


/// Converts an observable of arrays into an InputStream
public struct ObserverInputStream<E> : InputStream {
    public typealias Element = E

    private let loopback = LoopbackStream<E>()

    private let disposeBag = DisposeBag()
    
    private init<OE: CollectionType where OE.Generator.Element == E>(data: Observable<OE>) {
        data
            .subscribe { evt in
                switch evt {
                case .Completed:
                    self.loopback.onCompleted()
                case let .Error(e):
                    self.loopback.onError(e)
                case let .Next(buff):
                    Array(buff).withUnsafeBufferPointer { ptr in
                        self.loopback.onNext(ptr)
                    }
                }
            }
            .addDisposableTo(disposeBag)
    }
    
    public func read(count: Int) -> Observable<UnsafeBufferPointer<Element>> {
        return self.loopback.read(count)
    }
}

public extension ObservableType where E: CollectionType {
    /// Utility function for helping with tests and the likes
    public func asInputStream() -> ObserverInputStream<E.Generator.Element> {
        return ObserverInputStream(data: self.asObservable())
    }
}


public extension ObservableType where E == String {
    /// Utility function for helping with tests and the likes
    public func asUTF8InputStream() -> ObserverInputStream<UInt8> {
        return ObserverInputStream(data: self.map { Array($0.utf8) } .asObservable())
    }
}

extension LoopbackStream : ObserverType {
    typealias E = UnsafeBufferPointer<Element>
    
    func on(event: Event<E>) {
        switch event {
        case .Completed:
            self.close()
        case let .Next(val):
            self.write(val)
        case let .Error(e):
            self.fail(e)
        }
    }
}

class LoopbackStream<ElementType> : InputStream, OutputStream {
    
    typealias Element = ElementType
    
    private var dataLock = SpinLock()
    
    /// This is used in pump so we make sure to handle everything in order
    private var pumpLock = RecursiveLock()
    
    private var pendingRequests = [(AnyObserver<UnsafeBufferPointer<Element>>, Int, Int)]()
    private var buffer = [Element]()
    private var closed = false
    private var failError: ErrorType?
    
    private var pumpDeferredBlocks = Array<() -> ()>()
    private var isPumping = false

    func write(data: UnsafeBufferPointer<Element>) -> Observable<Void> {
        self.dataLock.locked {
            self.buffer.appendContentsOf(data)
        }
        pump()
        return Observable.just()
    }
    
    func read(count: Int) -> Observable<UnsafeBufferPointer<Element>> {
        return Observable.create { observer in
            self.dataLock.locked {
                self.pendingRequests.append((observer, count, count))
            }
            
            self.pump()
            
            return NopDisposable.instance
        }
    }
    
    /// To simulate or propagagte errors
    func fail(error: ErrorType) {
        self.dataLock.locked {
            self.closed = true
            self.failError = error
        }
        self.pump()
    }
    
    func close() {
        self.dataLock.locked {
            self.closed = true
        }
        self.pump()
    }
    
    private func pump() {
        self.pumpLock.locked {
            let isOuterPump = !isPumping
            
            if isOuterPump {
                isPumping = true
            }
            
            self.dataLock.locked {
                while (closed || !buffer.isEmpty) && !pendingRequests.isEmpty {
                    var request = pendingRequests[0]
                    let elementsToConsume = min(request.1, buffer.count)
                    request.1 -= elementsToConsume
                    
                    let observer = request.0

                    if elementsToConsume > 0 {
                        let elements = Array(buffer[0..<elementsToConsume])
                        self.buffer.removeFirst(elementsToConsume)

                        self.pumpDeferredBlocks.append {
                            elements.withUnsafeBufferPointer(observer.onNext)
                        }
                    }
                    
                    if request.1 == 0 || closed {
                        if let failError = self.failError {
                            self.pumpDeferredBlocks.append  {
                                observer.onError(failError)
                            }
                        } else {
                            self.pumpDeferredBlocks.append  {
                                observer.onCompleted()
                            }
                        }
                        pendingRequests.removeFirst(1)
                    } else {
                        pendingRequests[0] = request
                    }
                }
            }
        
            /// If we're the outer pump, handle the deferred blocks
            if isOuterPump {
                while !self.pumpDeferredBlocks.isEmpty {
                    let blocks = self.pumpDeferredBlocks
                    self.pumpDeferredBlocks.removeAll()
                    for b in blocks {
                        b()
                    }
                }
                isPumping = false
            }
        }
    }
}