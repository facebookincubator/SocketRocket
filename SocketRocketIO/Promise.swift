//
//  Promise.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/3/15.
//
//

import Foundation


/// Calls block when counts down to zero
/// Cannot count down to more than 0
private struct CountdownLatch {
    private var count: Int32
    private var action: (() -> ())! = nil
    private var fired = false
    
    init(count: Int32) {
        self.count = count
    }
    
    mutating func decrement() {
        let newCount = withUnsafeMutablePointer(&count, OSAtomicDecrement32Barrier)
        precondition(newCount >= 0, "Cannot count down more than the initialized times")
        
        precondition(!fired)
        if newCount == 0 {
            action()
            fired = true
        }
    }
}

// Only part of a promise protocol. It defines that it can be terminated


// Represents a return type that can either be a promise or a value
enum RawPromiseOrValue<V> {
    case Promised(RawPromise<V>)
    case Value(V)
}

extension RawPromise {

}

// Represents a return type that can either be a promise or a value
public enum PromiseOrValue<V> {
    public typealias P = Promise<V>
    
    case Promised(P)
    case Value(P.ET)
    
    static func of<V>(val: V) -> PromiseOrValue<V> {
        return .Value(ErrorOptional<V>(val))
    }
}

/// Promise that has error handling. Our promises are built on this
class RawPromise<T> {
    // This is decremented when the value is set or the handler is set
    private var latch = CountdownLatch(count: 2)
    
    private var val: T! = nil
    
    typealias ResultType = T
    typealias PV = RawPromiseOrValue<T>
  
    init () {
        
    }
    
    init(value: T) {
        self.val = value
        precondition(self.val != nil)
        latch.count = 1
    }
    
    /// Fulfills the promise. Calls handler if its ready
    func fulfill(value: T) {
        precondition(val == nil, "Should only set value once")
        self.val = value
        latch.decrement()
    }
    
    /// Terminating
    func then(queue: Queue?, handler: T -> Void)  {
        precondition(latch.action == nil)
        latch.action = wrap(queue) {
            precondition(self.val != nil)
            handler(self.val)
        }
        latch.decrement()
    }
    
    func then<R>(queue: Queue?, handler: T -> RawPromise<R>.PV) -> RawPromise<R> {
        let p = RawPromise<R>()
        precondition(latch.action == nil)
        self.then(queue) { val in
            switch handler(val) {
            case let .Value(value):
                p.fulfill(value)
            case let .Promised(subPromise):
                subPromise.then(nil) { value in
                    p.fulfill(value)
                }
            }
        }
        return p
    }
}



func wrap(queue: Queue?, fn:() -> ()) -> () -> () {
    if let q = queue {
        return q.wrap(fn)
    }
    
    return fn
}

extension Queue {
    /// wraps a void function and returns a new one. When
    /// the new one is called it will be dispatched on the sender
    func wrap(fn:() -> ()) -> () -> () {
        return {
            self.dispatchAsync(fn)
        }
    }
}

public class Promise<T> {
    /// Error optional type
    public typealias ET = ErrorOptional<T>
    
    typealias UnderlyingPromiseType = RawPromise<ET>
    
    let underlyingPromise: UnderlyingPromiseType
    
    private init(underlyingPromise: UnderlyingPromiseType) {
        self.underlyingPromise = underlyingPromise
    }
    
    public init(value: T) {
        underlyingPromise = RawPromise(value: ET(value))
    }
    
    // Initializes a failed promise
    public init(error: ErrorType) {
        underlyingPromise = RawPromise(value: ET(error))
    }
    
    // An uninitialized one
    public required init() {
        underlyingPromise = UnderlyingPromiseType()
    }

    // splits the call based one rror or success
    public func thenSplit<R>(queue: Queue? = nil, error: ((ErrorType) -> ())? = nil, success: T -> PromiseOrValue<R>) -> Promise<R> {
        return self.then { (r:ET) -> PromiseOrValue<R> in
            switch r {
            case let .Error(e):
                error?(e)
                // TODO: improve this .Not very efficient
                return PromiseOrValue.Promised(Promise<R>(error: e))
            case let .Some(val):
                return success(val)
            }
        }
    }
    
    public func then<R>(queue: Queue? = nil, handler: ET -> PromiseOrValue<R>) -> Promise<R> {
        typealias RET = Promise<R>.ET
        
        // Not super efficient since it makes an extra promise, but oh well
        let newRaw: RawPromise<RET> = underlyingPromise.then(queue) { (val: ET) in
            switch handler(val) {
            case let .Promised(promise):
                return .Promised(promise.underlyingPromise)
            case let .Value(value):
                return .Value(value)
            }
        }
        
        return Promise<R>(underlyingPromise: newRaw)
    }
    
    /// Terminating
    func then(queue: Queue? = nil, handler: ET -> Void)  {
        self.underlyingPromise.then(queue, handler: handler)
    }

    public func then<R>(queue: Queue? = nil, handler: ET -> Promise<R>.ET) -> Promise<R> {
        typealias RET = Promise<R>.ET
        
        // Not super efficient since it makes an extra promise, but oh well
        let newRaw: RawPromise<RET> = underlyingPromise.then(queue) { (val: ET) in
           return .Value(handler(val))
        }
        
        return Promise<R>(underlyingPromise: newRaw)
    }
    
    /// Catches an error and propagates it in the optitional
    /// 
    /// Callers of this should use the .checkedGet on the input type to make it easy to propagate errors
    ///
    /// Example:
    ///
    /// p.thenChecked{ v throws in
    ///     return try v.checkedGet() + 3
    /// }
    public func thenChecked<R>(queue: Queue? = nil, handler: ET throws -> R) -> Promise<R> {
        typealias RP = Promise<R>
        typealias RET = RP.ET
        
        return self.then(queue) { val -> ErrorOptional<R> in
            do {
                return RET(try handler(val))
            } catch let e {
                return RET(e)
            }
        }
    }
    
    public func fulfill(value: T) {
        self.fulfill(ET(value))
    }
    
    public func fulfill(value: ET) {
        underlyingPromise.fulfill(value)
    }
    
    public func fulfill(error: ErrorType) {
        self.fulfill(ET(error))
    }
}
