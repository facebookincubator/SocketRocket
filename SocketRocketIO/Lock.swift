//
//  Lock.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/3/15.
//
//



protocol Lock {
    mutating func lock()
    mutating func unlock()
}

extension Lock {
    mutating func withLock<Result>(fn: () -> Result) -> Result {
        lock()
        defer {
         unlock()
        }
        return fn()
    }

    mutating func withLock<Result>(fn: () throws -> Result) throws -> Result {
        lock()
        defer {
            unlock()
        }
        return try fn()
    }
}

extension OSSpinLock: Lock {
    mutating func lock() {
        withUnsafeMutablePointer(&self, OSSpinLockLock)
    }
    
    mutating func unlock() {
        withUnsafeMutablePointer(&self, OSSpinLockUnlock)
    }
}
