//
//  WebSocketVersionNumber.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/7/16.
//
//

import Foundation

/// Versions defined in RFC6455 section 11.6 https://tools.ietf.org/html/rfc6455#section-11.6
/// We only care about one currently
public enum WebSocketVersionNumber : Int {
    /// Standard version number
    case RFC6455 = 13
}

/// opcodes defined in RFC6455 section 11.8 https://tools.ietf.org/html/rfc6455#section-11.8
public enum WebSocketOpcode : Int {
    case Continuation = 0
    case Text = 1
    case Binary = 2
    case ConnectionClose = 3
    case Ping = 9
    case Pong = 10
}

/// Known close codes. These are defined in https://tools.ietf.org/html/rfc6455#section-7.4
public enum WebSocketCloseCode : Int {
    case NormalClosure = 1000
    case GoingAway = 1001
    case ProtocolError = 1002
    case UnsupportedData = 1003
    // 1004 is reserved
    case NoStatusRcvd = 1005
    case AbnormalClosure = 1006
    case InvalidFramePayloadData = 1007
    case PolicyViolation = 1008
    case MessageTooBig = 1009
    case MandatoryExt = 1010
    case InternalServerError = 1011
    case TLSHandshake = 1015
}

/// Represents either a known close code or unknown
public enum AnyWebSocketCloseCode {
    /// This is for known close codes
    case Known(WebSocketCloseCode)
    /// Unknown close codes
    case Unknown(Int)
    
    init(_ code: Int){
        if let knownCode = WebSocketCloseCode(rawValue: code) {
            self = .Known(knownCode)
        } else {
            self = .Unknown(code)
        }
    }
    
    public var code: Int {
        switch self {
        case let .Known(val):
            return val.rawValue
        case let .Unknown(val):
            return val
        }
    }
    /// Whether or not it was a clean closure
    public var isClean: Bool {
        switch self {
        case .Known(.NormalClosure):
            return true
        default:
            return false
        }
    }
}