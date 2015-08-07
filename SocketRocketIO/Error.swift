//
//  Error.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/7/15.
//
//

/// Wraps errors. Has an uknown type if it cant resolve to an oserror
enum Error: ErrorType {
    case Unknown(status: Int32)
    case CodecError
    case UTF8DecodeError
    case Canceled
    
    /// For functions that return negative value on error and expect errno to be set
    static func checkReturnCode(returnCode: Int32) -> ErrorType? {
        guard returnCode < 0 else {
            return nil
        }
        return errorFromStatusCode(errno)
    }
    
    /// Returns an error type based on status code
    static func errorFromStatusCode(status: Int32) -> ErrorType? {
        guard status != 0 else {
            return nil
        }
        
        if let e = POSIXError(rawValue: status) {
            return e
        }
        
        return Error.Unknown(status: status)
    }
    
    static func throwIfNotSuccess(status: Int32) throws  {
        if let e = errorFromStatusCode(status) {
            throw e
        }
    }
    
    // Same as above, but checks if less than 0, and uses errno as the varaible
    static func throwIfNotSuccessLessThan0(returnCode: Int32) throws  {
        if let e = checkReturnCode(returnCode) {
            throw e
        }
    }
}
