//
//  Queue.swift
//  SocketRocket
//
//  Created by Mike Lewis on 7/30/15.
//
// Wrappers areound dispatch_queue_t

import Foundation
import Dispatch

/// Simple wrapper around dispatch_queue_t
public class Queue: NSObject {
    let queue: dispatch_queue_t

    // used to check current queue
    private var ctxKeyValue: UnsafeMutablePointer<Void>
    
    /// same as dispatch_get_main_queue()
    public static let mainQueue = Queue(queue: dispatch_get_main_queue())
    
    public required init(queue: dispatch_queue_t) {
        self.queue = queue
        let destructor: dispatch_function_t! = nil
        
        ctxKeyValue = malloc(1)
        dispatch_queue_set_specific(self.queue, ctxKeyValue, ctxKeyValue, destructor)
    }
    
    public convenience init(label: String, attr: dispatch_queue_attr_t? = DISPATCH_QUEUE_SERIAL) {
        self.init(queue: dispatch_queue_create(label, attr))
    }
    
    deinit {
        let destructor: dispatch_function_t! = nil
        dispatch_queue_set_specific(self.queue, ctxKeyValue, nil, destructor)
        free(ctxKeyValue)
    }
    
    public func dispatchAsync(block: () -> Void) {
        dispatch_async(queue, block)
    }
    
    /// Returns true if we're on the current queue
    public func isCurrentQueue() -> Bool {
        let currentContext = dispatch_get_specific(ctxKeyValue)
        return currentContext == ctxKeyValue
    }
    
    public func checkIsCurrentQueue() {
        precondition(isCurrentQueue(), "Expected to be current queue")
    }
}

