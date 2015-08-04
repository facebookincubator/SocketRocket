//
//  Promise.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/3/15.
//
//

import Foundation

public class Promise<T> {
    private var lock: OSSpinLock = OS_SPINLOCK_INIT
    private var val: T! = nil {
        didSet {
            didSetVal = true
        }
    }
    private var didSetVal = false
    private var nextHandler: (T -> Void)! = nil
    
    typealias ET = ErrorOptional<T>
    // Queue to call the then handler on
    
    // Returns a fulfilled promise
    public static func of<T>(val: T) -> Promise<T> {
        return Promise<T>(val)
    }

    public required init(_ value: T) {
        self.val = value
        self.didSetVal = true
    }
    
    // Supplier is called immediately. The function passed to it is a done
    public convenience init(@noescape supplier: (supply: (T) -> Void) -> Void) {
        self.init()
        supplier(supply: self.fulfill)
    }
    
    public required init(_ nextHandler: ((T) -> Void)!, dispatchedOnQueue: Queue? = nil) {
        self.nextHandler = nextHandler
    }
    
    // An uninitialized one
    public required init() {
        
    }
    
    public func then<R>(handler: T -> Promise<R>) -> Promise<R> {
        let p = Promise<R>()
        
        lockAndFireHandlersIfNeeded() {
            precondition(self.nextHandler == nil, "Should only set nexthandler once")
            self.nextHandler = {resultVal in
                let subP = handler(resultVal)
                subP.finally { newResultVal in
                    p.fulfill(newResultVal)
                }
            }
        }

        return p
    }

    // TODO(lewis): Make this more efficient
    public func then<R>(handler: T -> R) -> Promise<R> {
        let p = Promise<R>()
        
        lockAndFireHandlersIfNeeded() {
            precondition(self.nextHandler == nil, "Should only set nexthandler once")
            self.nextHandler = {resultVal in
                let v = handler(resultVal)
                p.fulfill(v)
            }
        }
        
        return p
    }
    
    // This is terminating. Similar to then
    public func finally(handler: (T) -> Void) {
        then { v -> Void in
            handler(v)
        }
    }

    /// Fulfills the promise. Can only be called once
    public func fulfill(value: T) {
        lockAndFireHandlersIfNeeded() {
            precondition(!self.didSetVal, "Should only fulfill once")
            self.val = value
        }
    }

    private func shouldCallNextHandler() -> Bool {
        return self.nextHandler != nil && didSetVal
    }

    private func lockAndFireHandlersIfNeeded(block: () -> Void) {
        let shouldFire: Bool = lock.withLock {
            block()
            return self.shouldCallNextHandler()
        }
        
        if shouldFire {
            self.nextHandler(val)
        }
    }
}

public class FailablePromise<T> : Promise<ErrorOptional<T>> {
//    public func then<R>(handler: (T) -> R) -> FailablePromise<ErrorOptional<R>> {
//
//
//    }
//
//    public func then<R>(handler: (T) -> PromiseType<R>) -> FailablePromise<ErrorOptional<R>> {
//        return super.then { result
//
//        }
    }

//    override fu
