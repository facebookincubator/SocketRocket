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
    case Promised(P: RawPromise<V>)
    case Value(V)
}



// Represents a return type that can either be a promise or a value
public enum PromiseOrValue<V> {
    case Promised(Promise<V>)
    case Value(V)
}

/// Promise that has error handling. Our promises are built on this
class RawPromise<T> {
    // This is decremented when the value is set or the handler is set
    private var latch = CountdownLatch(count: 2)
    
    private var val: T! = nil
    
    typealias ResultType = T
    typealias PV = RawPromiseOrValue<T>
    
    required init () {
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
    func then(handler: T -> Void)  {
        precondition(latch.action == nil)
        latch.action = {
            precondition(self.val != nil)
            handler(self.val)
        }
        latch.decrement()
    }
    
    func then<R>(handler: ResultType -> RawPromise<R>.PV) -> RawPromise<R> {
        let p = RawPromise<R>()
        precondition(latch.action == nil)
        latch.action = {
            precondition(self.val != nil)
            switch handler(self.val) {
            case let .Value(value):
                p.fulfill(value)
            case let .Promised(subPromise):
                subPromise.then { value in
                    p.fulfill(value)
                }
            }
        }
        latch.decrement()
        return p
    }
}

public class Promise<T> : RawPromise<ErrorOptional<T>> {
    /// Error optional type
    public typealias ET = ErrorOptional<T>


    public init(value: T) {
        super.init(value: ET(value))
    }
    
    // Initializes a failed promise
    public init(error: ErrorType) {
        super.init(value: ET(error))
    }
    
    public typealias SupplierType = (supply: (ET) -> Void) -> Void
    
    // Supplier is called immediately. The function passed to it is a done
    public convenience init(@noescape supplier: SupplierType) {
        self.init()
        supplier(supply: self.fulfill)
    }
    
    // An uninitialized one
    public required init() {
        super.init()
    }
    
    //   TODO(lewis): Make this more efficient
    public func then<R>(handler: ET -> R) -> Promise<R> {
        return then { val in
            return ErrorOptional(handler(val))
        }
    }

    // splits the call based one rror or success
    public func thenSplit<R>(success: T -> PromiseOrValue<R>, error: ((ErrorType) -> ())? = nil) -> Promise<R> {
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
    
    public func then<R>(handler: ET -> PromiseOrValue<R>) -> Promise<R> {
        let p = Promise<R>()
        
        super.then { val in
            switch handler(val) {
            case let .Promised(promise):
                promise.then(p.fulfill)
            case let .Value(v):
                p.fulfill(v)
            }
        }

        return p
    }
    
    //    // TODO(lewis): Make this more efficient
    public func then<R>(handler: ET -> Promise<R>.ET) -> Promise<R> {
        let p = Promise<R>()
        
        super.then { val in
            p.fulfill(handler(val))
        }
        
        return p
    }
    
    /// Catches an error and propagates it in the optitional
    public func thenChecked<R>(handler: ET throws -> R) -> Promise<R> {
        return then() { val -> ErrorOptional<R> in
            do {
                let newVal = try handler(val)
                return ErrorOptional(newVal)
            } catch let e {
                return ErrorOptional(e)
            }
        }
    }
    
    public func fulfill(value: T) {
        super.fulfill(ET(value))
    }
}
