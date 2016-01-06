//
//  Extensions.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/6/15.
//
//

import Dispatch

extension dispatch_data_t {
    func apply(applier: UnsafeBufferPointer<UInt8> -> Bool) -> Bool {
        return dispatch_data_apply(self) { (_, offset, buffer, size) -> Bool in
            let mappedBuffer = unsafeBitCast(buffer, UnsafePointer<UInt8>.self)
            let buffer = UnsafeBufferPointer(start: mappedBuffer.advancedBy(offset), count: size - offset)
            return applier(buffer)
        }
    }
    
    func apply(applier: UnsafeBufferPointer<UInt8> -> ()) -> Bool {
        return self.apply { d -> Bool in
            applier(d)
            return true
        }
    }
    
    func apply(applier: UnsafeBufferPointer<UInt8> throws -> ()) throws -> Bool {
        var error: ErrorType? = nil
        let ret = self.apply { d -> Bool in
            do {
                try applier(d)
                return true
            } catch let e {
                error = e
                return false
            }
        }
        
        if let e = error {
            throw e
        }
        
        return ret
    }
}



extension dispatch_queue_t {
    func dispatchAsync(block: () -> ()) {
        dispatch_async(self, block)
    }
}