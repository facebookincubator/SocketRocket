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
    
        let didSet: Bool = withUnsafeMutablePointer(&count) { ptr in
            return !OSAtomicTestAndSet(UInt32(bit), ptr)
        }
        
        if didSet {
            block()
        }
        
        return didSet
    }
}
