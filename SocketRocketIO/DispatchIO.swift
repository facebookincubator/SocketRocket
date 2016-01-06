//
//  DispatchIO.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/6/16.
//
//

import Foundation

import RxSwift

/// Wraps an io since it is a protocol
public struct DispatchIO {
    public let io: dispatch_io_t
    /// queue that results are called on
    public let resultQueue: dispatch_queue_t
    
    // We're bound to using a result queue if we want to use dispatch_io underlying
    public init(io: dispatch_io_t, resultQueue: dispatch_queue_t) {
        self.io = io
        self.resultQueue = resultQueue
    }
}



extension DispatchIO : StreamBase {
    public typealias Element = UInt8
}

extension DispatchIO : InputStream {
    public func read(count: Int) -> Observable<UnsafeBufferPointer<UInt8>> {
        let io = self.io
        return Observable.create { observer in
            dispatch_io_read(io, 0, count, self.resultQueue) { done, data, error in
                if error != 0 {
                    observer.onError(POSIXError(rawValue: error)!)
                }
                
                let dataSize = dispatch_data_get_size(data)
                
                var buffer = [UInt8]()
                
                buffer.reserveCapacity(dataSize)
                
                data.apply { rawBuffer in
                    observer.onNext(rawBuffer)
                }
                
                
                if done {
                    observer.onCompleted()
                }
            }
            
            return NopDisposable.instance
        }
    }
}


extension DispatchIO : OutputStream {
    public func write(data: UnsafeBufferPointer<UInt8>) -> Observable<Void> {
        let doneSubject: ReplaySubject<Void> = ReplaySubject.create(bufferSize: 1)
        
        let dispatchData = dispatch_data_create(data.baseAddress, data.count, nil, nil)
        
        dispatch_io_write(io, 0, dispatchData, resultQueue) { done, _, error in
            guard error == 0 else {
                doneSubject.onError(POSIXError(rawValue: error)!)
                return
            }
            
            if done {
                doneSubject.onNext()
                doneSubject.onCompleted()
            }
        }
        
        return doneSubject
    }
}
