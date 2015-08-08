//
//  Concurrent.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/7/15.
//
//

import Foundation


/// This is a nonblocking once. THis means that the once block
/// may fire after the callers that don't get it succeed
/// This is unlike the behavior of dispatch_once
struct Once {
    var count: Int32 = 0
    
    /// If this is the first one to call this, will invoke the block
    ///
    /// :param: bit This structure can be used for more than one bit. We allow the first 16 bits to be used
    ///
    /// :return: true if the block is ecuted
    mutating func doMaybe(bit: Int = 0, block: () -> ()) -> Bool {
        precondition(bit < 16)
        
        guard !count.atomicTestAndSet(bit) else {
            return false
        }
        
        block()
        return true
    }
}

extension Int32 {
    mutating func atomicTestAndSet(bit: Int) -> Bool {
        return withUnsafeMutablePointer(&self) { ptr in
            return OSAtomicTestAndSet(UInt32(bit), ptr)
        }
    }
}

class PGroup<T> {
    /// TODO: remove locking somehow
    typealias LockType = OSSpinLock
    
    typealias Handler = (ErrorOptional<T>) -> ()
    
    let queue: Queue

    // These should only be mutated inside a lock
    private var result: PromiseOrValue<T>? = nil
    
    // these are blocks enqueued while we don't have a result. Should be called when we actually fulfill
    private var pendingHandlers = [Handler]()
    
    func cancel() {
        reject(Error.Canceled)
    }
    
    func reject(error: ErrorType) {
        fulfill(.Value(.Error(error)))
    }
    
    func resolve(value: T) {
        fulfill(.Value(ErrorOptional(value)))
    }
    
    private func flushHandlers() {
        precondition(queue.isCurrentQueue())
        
        guard let result = self.result else {
            return
        }
        
        switch result {
        case let .Promised(resultPromise):
            let pendingHandlersCopy = self.pendingHandlers
            
            resultPromise.then { v in
                self.queue.dispatchAsync {
                    for h in pendingHandlersCopy {
                        h(v)
                    }
                }
            }
        case let .Value(resultValue):
            for h in self.pendingHandlers {
                h(resultValue)
            }
        }
        self.pendingHandlers.removeAll()
    }
    
    func fulfill(result: PromiseOrValue<T>) {
        queue.dispatchAsync {
            // Do nothing if it has already been fulfilled
            guard self.result == nil else {
                return
            }
            
            self.result = result
            self.flushHandlers()
        }
    }
    
    /// Adds a handler. Called immediately if result is set. Otherwise it will enqueue
    func then(h: Handler) -> Void {
        queue.dispatchAsync {
            self.pendingHandlers.append(h)
            self.flushHandlers()
        }
    }
    
    /// :param queue: Queue that the handlers will be invoked on in order
    init(queue: Queue) {
        self.queue = queue
    }
    
    private init(queue: Queue, result: ErrorOptional<T>) {
        self.queue = queue
        self.result = .Value(result)
    }
    
    static func resolve<T>(queue: Queue, value: T) -> PGroup<T> {
        return PGroup<T>(queue: queue, result: ErrorOptional<T>(value))
    }
    
    static func reject<T>(queue: Queue, error: ErrorType) -> PGroup<T> {
        return PGroup<T>(queue: queue, result: ErrorOptional<T>(error))
    }
}