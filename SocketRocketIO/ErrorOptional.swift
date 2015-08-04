//
//  ErrorOptional.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/3/15.
//
//

// Like optional but instead of None, it can take a nil
public enum ErrorOptional<T> {
    case Error(ErrorType)
    case Some(T)
    
    /// Returns nil if ierrored. Using checkedGet is recommended
    var orNil: T? {
        get {
            switch self {
            case let Some(some):
                return some
            case Error:
                return nil
            }
            
        }
    }
    
    var hasError: Bool {
        get {
            switch self {
            case Some:
                return false
            case Error:
                return true
            }
        }
    }
    
    func checkedGet() throws -> T  {
        switch self {
        case let Some(some):
            return some
        case let Error(e):
            throw e
        }
    }
    
    /// Construct a non-`nil` instance that stores `some`.
    init(_ some: T) {
        self = Some(some)
    }
    
    init(_ error: ErrorType) {
        self = Error(error)
    }
    
    // Will catch the first error and return with error wrapped in error optinal
    static func attempt(block: () throws -> T) -> ErrorOptional<T> {
        do {
            return try ErrorOptional(block())
        } catch let e {
            return ErrorOptional(e)
        }
    }
    
    // Will make it overload if there's no throws
    static func attempt(block: () -> T) -> ErrorOptional<T> {
        return ErrorOptional(block())
    }
}

