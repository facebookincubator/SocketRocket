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
}