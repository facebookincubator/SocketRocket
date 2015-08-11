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

func maybeWrap<T>(queue: Queue?, fn:(T) -> ()) -> (T) -> () {
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

extension Resolver {
    /// resolves with the return value. Otherwise if it throws, it will return as an error type
    public func attemptResolve(block: () throws -> T) {
        fulfill(ET.attempt { return try block() })
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

    var queue: Queue {
        get  {
            return self.pgroup.queue
        }
    }
    
    typealias PV = PromiseOrValue<T>
    
    typealias ValueType = T
    
    private init(pgroup: PG) {
        self.pgroup = pgroup
    }
    
    public class func resolve(queue: Queue, value: T) -> Promise<T> {
        return Promise<T>(pgroup: PGroup<T>.resolve(queue, value: value))
    }
    
    public class func reject(queue: Queue, error: ErrorType) -> Promise<T> {
        return Promise<T>(pgroup: PGroup<T>.reject(queue, error: error))
    }
    
    /// Returns a promise and the resolver for it
    ///
    /// :param queue: The queue the then handlers will be invoked on in order.
    ///                 then functions take an optional queue that will be called out to
    public class func resolver(queue: Queue) -> (Resolver<T>, Promise<T>) {
        let p = Promise<T>(queue: queue)
        let r = Resolver(promise: p)
        return (r, p)
    }
    
    // An uninitialized one
    init(queue: Queue) {
        pgroup = PG(queue: queue)
    }

    // splits the call based one rror or success
    public func thenSplit<R>(queue: Queue? = nil, error: ((ErrorType) -> ())? = nil, success: T -> PromiseOrValue<R>) -> Promise<R> {
        return self.then(queue) { (r:ET) -> PromiseOrValue<R> in
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
        let (r, p) = Promise<R>.resolver(queue ?? self.queue)
        
        self.then(queue) { v -> Void in
            let newV = handler(v)
            r.fulfill(newV)
        }
        
        return p
    }
    

    /// Will call a handler on the queue that this promise was constructed with
    func then(queue: Queue? = nil, handler: ET -> Void)  {
        self.pgroup.then(maybeWrap(queue, fn: handler))
    }

    /// Will call handler after promise is fulfilled. if queue is left nil, 
    /// handler will be called on this queue and promise will be constructed with this queue
    public func then<R>(queue: Queue? = nil, handler: ET -> Promise<R>.ET) -> Promise<R> {
        let (r, p) = Promise<R>.resolver(queue ?? self.queue)
        
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
    /// p.thenChecked{ v in
    ///     return try v.checkedGet() + 3
    /// }
    public func thenChecked<R>(queue: Queue? = nil, handler: ET throws -> R) -> Promise<R> {
        return self.then(queue) { val -> ErrorOptional<R> in
            do {
                return ErrorOptional(try handler(val))
            } catch let e {
                return ErrorOptional(e)
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



