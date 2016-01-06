//
//  Stream.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/6/16.
//
//

import Foundation
import RxSwift

public protocol StreamBase {
    typealias Element
}

public protocol OutputStream : StreamBase {
    /// Writes data to the the stream. Data is not valid after call
    /// - returns: Hot observable yields one value when its done then immediately closes.
    func write(data: UnsafeBufferPointer<Element>) -> Observable<Void>
}

extension OutputStream {
    func write(data: Array<Element>) -> Observable<Void> {
        return data.withUnsafeBufferPointer { ptr in
            return self.write(ptr)
        }
    }
}


public struct AnyInputStream<T> : InputStream {
    public typealias Element = T
    
    private let readFunc: (count: Int) -> Observable<UnsafeBufferPointer<T>>
    
    private init<S: InputStream where S.Element == T>(stream: S) {
        self.readFunc = stream.read
    }
    
    public func read(count: Int) -> Observable<UnsafeBufferPointer<T>> {
        return self.readFunc(count: count)
    }
}

public func anyInputStream<S: InputStream>(stream: S) -> AnyInputStream<S.Element> {
    return .init(stream: stream)
}

public protocol InputStream : StreamBase {
    /// Reads data until it reaches the number of bytes or end of stream. EOF is not interpreted as an error. Passing in Int.max is valid
    /// - returns: Cold readable that enqueues read operation once subscribed. If subscribed to more than once, it will read data more than once
    @warn_unused_result
    func read(count: Int) -> Observable<UnsafeBufferPointer<Element>>
}

public enum StreamError : Int, ErrorType {
    case InvalidLength = 1
}

public extension InputStream {
    /// Same as read, but will error if we don't have enough bytes for expected length
    func readExactly(count: Int) -> Observable<UnsafeBufferPointer<Element>> {
        return Observable.create { observer in
            var seen = 0
            
            return self
                .read(count)
                .subscribe { event in
                    switch event {
                    case let .Next(val):
                        seen += val.count
                    case .Completed:
                        if seen != count {
                            observer.onError(StreamError.InvalidLength)
                            return
                        }
                    default: break
                    }
                    
                    observer.on(event)
            }
        }
    }
    
    
    /// Combines everything into one buffer and delivers it at the end.
    /// It has a short circuit case if the first received value is exactly the expected length. This avoids buffering and copying of data.
    /// If allowEmpty is true, it will yield an empty array if we dont' see anything. THis is Good for EOF stuff
    func readAndBufferExactly(count: Int, allowEmpty: Bool = false) -> Observable<UnsafeBufferPointer<Self.Element>> {
            return Observable.create { observer in
                /// Buffer if we need one
                var buffer = [Element]()
                var seen = 0
                
                return self
                    .read(count)
                    .subscribe { event in
                        switch event {
                        case let .Next(val):
                            /// Special case for reading the exact ammount to start. This avoids copying data
                            if seen == 0 && val.count == count {
                                seen += val.count
                                observer.onNext(val)
                            } else {
                                seen += val.count
                                buffer.appendContentsOf(val)
                            }
                        case .Completed:
                            guard seen == count || (allowEmpty && seen == 0) else {
                                observer.onError(StreamError.InvalidLength)
                                return
                            }
                            
                            if !buffer.isEmpty {
                                buffer.withUnsafeBufferPointer { ptr in
                                    observer.onNext(ptr)
                                }
                            }
                            
                            observer.onCompleted()
                        case let .Error(e):
                            observer.onError(e)
                        }
                }
            }
        }
}
