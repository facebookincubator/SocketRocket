//
//  Promise.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/3/15.
//
//

import Foundation


// Only part of a promise protocol. It defines that it can be terminated


// Represents a return type that can either be a promise or a value
public enum PromiseOrValue<V> {
    public typealias P = Promise<V>
    
    case Promised(P)
    case Value(P.ET)
    
    static func of<V>(val: V) -> PromiseOrValue<V> {
        return .Value(ErrorOptional<V>(val))
    }
}

func wrap<T>(queue: Queue?, fn:(T) -> ()) -> (T) -> () {
    if let q = queue {
        return q.wrap(fn)
    }
    
    return fn
}

extension Queue {
    /// wraps a void function and returns a new one. When
    /// the new one is called it will be dispatched on the sender
    func wrap<T>(fn:(T) -> ()) -> (T) -> () {
        return { v in
            self.dispatchAsync {
                fn(v)
            }
        }
    }
}

public struct Resolver<T> {
    public typealias ET = ErrorOptional<T>
    
    typealias P = Promise<T>
    private let promise: P
    
    init(promise: P) {
        self.promise = promise
    }
    
    public func resolve(value: T) {
        fulfill(ET(value))
    }
    
    public func reject(error: ErrorType) {
        fulfill(ET(error))
    }
    
    /// resolves with the return value. Otherwise if it throws, it will return as an error type
    public func attemptResolve(block: () throws -> T) {
        fulfill(ET.attempt { return try block() })
    }
    
    public func fulfill(v: ET) {
        promise.fulfill(v)
    }
    
    // Used for chaining the promise
    public func fulfill(p: Promise<T>) {
        promise.fulfill(p)
    }
    
    // Used for chaining the promise
    public func fulfill(p: PromiseOrValue<T>) {
        promise.fulfill(p)
    }
}


/// Useful for stuff that can only succeed and not return any errors
public typealias VoidPromiseType = Promise<Void>
public typealias VoidResolverType = Resolver<Void>

public class Promise<T> {
    /// Error optional type
    public typealias ET = ErrorOptional<T>
    
    typealias PG = PGroup<T>
    
    var pgroup: PG
    
    typealias PV = PromiseOrValue<T>
    
    typealias ValueType = T
    
    private init(pgroup: PG) {
        self.pgroup = pgroup
    }
    
    public class func resolve(value: T) -> Promise<T> {
        return Promise<T>(pgroup: PGroup<T>.resolve(value))
    }
    
    public class func reject(error: ErrorType) -> Promise<T> {
        return Promise<T>(pgroup: PGroup<T>.reject(error))
    }
    
    // Returns a promise and the resolver for it
    public class func resolver() -> (Resolver<T>, Promise<T>) {
        let p = Promise<T>()
        let r = Resolver(promise: p)
        return (r, p)
    }
    
    // An uninitialized one
    init() {
        pgroup = PG()
    }

    // splits the call based one rror or success
    public func thenSplit<R>(queue: Queue? = nil, error: ((ErrorType) -> ())? = nil, success: T -> PromiseOrValue<R>) -> Promise<R> {
        return self.then { (r:ET) -> PromiseOrValue<R> in
            switch r {
            case let .Error(e):
                error?(e)
                // TODO: improve this .Not very efficient
                return PromiseOrValue.Value(Promise<R>.ET(e))
            case let .Some(val):
                return success(val)
            }
        }
    }
    
    public func then<R>(queue: Queue? = nil, handler: ET -> PromiseOrValue<R>) -> Promise<R> {
        let (r, p) = Promise<R>.resolver()
        
        self.then(queue) { v -> Void in
//            pgroup.fulfill(handler(v))
            let newV = handler(v)
            r.fulfill(newV)
        }
        
        return p
    }
    
    /// Terminating
    func then(queue: Queue? = nil, handler: ET -> Void)  {
        self.pgroup.then(wrap(queue, fn: handler))
    }

    public func then<R>(queue: Queue? = nil, handler: ET -> Promise<R>.ET) -> Promise<R> {
        let (r, p) = Promise<R>.resolver()
        
        self.then(queue) { v -> Void in
            r.fulfill(handler(v))
        }
        
        return p
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
    
    private func fulfill(value: ET) {
        pgroup.fulfill(.Value(value))
    }
    
    private func fulfill(promise: Promise<T>) {
        pgroup.fulfill(.Promised(promise))
    }
    
    private func fulfill(promise: PromiseOrValue<T>) {
        pgroup.fulfill(promise)
    }
}



