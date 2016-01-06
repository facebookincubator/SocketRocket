//
//  Locks.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/6/16.
//
//

import Foundation

public protocol Lock {
    mutating func lock()
    mutating func unlock()
}

public struct SpinLock : Lock {
    private var osSpinLock: OSSpinLock = OS_SPINLOCK_INIT
    
    public mutating func lock() {
        OSSpinLockLock(&osSpinLock)
    }
    
    public mutating func unlock() {
        OSSpinLockUnlock(&osSpinLock)
    }
}



public class RecursiveLock : Lock {
    private var mutex: pthread_mutex_t
    
    public init() {
        var attr = pthread_mutexattr_t()
        mutex = pthread_mutex_t()
        
        pthread_mutexattr_init(&attr)
        defer { pthread_mutexattr_destroy(&attr) }
        
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE)
        pthread_mutex_init(&mutex, &attr)
    }
    
    deinit {
        pthread_mutex_destroy(&mutex)
    }
    
    public func lock() {
        pthread_mutex_lock(&mutex)
    }
    
    public func unlock() {
        pthread_mutex_unlock(&mutex)
    }
}


extension Lock {
    public mutating func locked<Result>(@noescape body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}