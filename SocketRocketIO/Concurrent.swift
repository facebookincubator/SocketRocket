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



/// Building block for a
enum PState<V> {
    case Pending
    case Fulfilled(V)
    case Rejected(ErrorType)
}

struct PGroup<T> {
    /// TODO: remove locking somehow
    typealias LockType = OSSpinLock
    
    typealias Handler = (ErrorOptional<T>) -> ()
    
    private var lock = LockType()
    
    // These should only be mutated inside a lock
    private var result: ErrorOptional<T>? = nil
    
    // these are blocks enqueued while we don't have a result. Should be called when we actually fulfill
    private var pendingHandlers = [Handler]()
    
    var state = PState<T>.Pending
    
    mutating func cancel() -> Bool {
        return reject(Error.Canceled)
    }
    
    mutating func reject(e: ErrorType) -> Bool {
        return fulfill(.Error(e))
    }
    
    mutating func fulfill(v: ErrorOptional<T>) -> Bool {
        guard result == nil else {
            return false
        }
        
        let blocksToRun: [Handler]? = lock.withLock() {
            guard self.result == nil else {
                return nil
            }
            
            self.result = v
            
            let ret = self.pendingHandlers
            self.pendingHandlers.removeAll()
            return ret
        }
        
        guard let b = blocksToRun else {
            return false
        }
        
        for bl in b {
            bl(v)
        }
        
        return true
    }
    
    /// Adds a handler. Called immediately if result is set. Otherwise it will enqueue
    mutating func then(h: Handler) -> Void {
        // If we have a result, return it
        if let v = self.result {
            h(v)
            return
        }
        
        let valueAgain: ErrorOptional<T>? = lock.withLock {
            if let r = result {
                return r
            }
            
            self.pendingHandlers.append(h)
            
            return nil
        }
        
        if let v = valueAgain {
            h(v)
        }
    }
    
    init () {
        
    }
    
    private init(result: ErrorOptional<T>) {
        self.result = result
    }
    
    static func resolve<T>(v: T) -> PGroup<T> {
        return PGroup<T>(result: ErrorOptional<T>(v))
    }
    
    static func reject<T>(error: ErrorType) -> PGroup<T> {
        return PGroup<T>(result: ErrorOptional<T>(error))
    }
}