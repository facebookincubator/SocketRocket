//
//  Concurrent.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/7/15.
//
//

import Foundation

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
        
        // Only run it if we have a result
        guard case let .Some(.Value(resultValue)) = self.result else {
            return
        }
        
        for h in self.pendingHandlers {
            h(resultValue)
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
            
            switch result {
            case let .Promised(promised):
                promised.then(self.queue) { v in
                    self.result = .Value(v)
                    self.flushHandlers()
                }
            case .Value:
                self.flushHandlers()
            }
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