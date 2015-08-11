//
//  IO.swift
//  SocketRocket
//
//  Created by Mike Lewis on 7/30/15.
//
//

import Foundation
import SystemShims

public struct CloseFlags : OptionSetType {
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    public let rawValue: UInt
    public static let Stop = CloseFlags(rawValue: DISPATCH_IO_STOP)
}

public protocol SockAddr {
    init()
    
    var family: sa_family_t { get set }
    var len: UInt8 { get set }
    var port: UInt16 { get set }

    
    mutating func setAddress(address: Address) throws
    
    /// This is the default address family
    static var addressFamily: sa_family_t { get }
    /// Size to set socklen to
    static var size: Int { get }
    
    
    mutating func withUnsafeSockAddrMutablePointer<T>(@noescape fn: (ptr: UnsafeMutablePointer<sockaddr>, len: socklen_t) -> (T)) -> T
    mutating func withUnsafeSockAddrPointer<T>(@noescape fn: (ptr: UnsafePointer<sockaddr>, len: socklen_t) -> (T)) -> T
}

public enum Address {
    case Loopback
    case Any
    case IPv6Addr(address: String)
    case IPv4Addr(address: String)
}

extension sockaddr_in6: SockAddr {
    public var family: sa_family_t {
        get {
            return self.sin6_family
        }
        set {
            self.sin6_family = newValue
        }
    }

    public var port: UInt16 {
        get {
            return self.sin6_port.bigEndian
        }
        set {
            self.sin6_port = newValue.bigEndian
        }
    }
    
    public var len: UInt8 {
        get {
            return self.sin6_len
        }
        set {
            self.sin6_len = newValue
        }
    }
    
    mutating public func setAddress(address: Address) throws {
        switch address {
        case .Any:
            self.sin6_addr = in6addr_any
        case let .IPv6Addr(address: address):
            switch inet_pton(Int32(sockaddr_in6.addressFamily), address, &self.sin6_addr) {
            case 0:
                throw Error.NotParseableAddress
            case -1:
                throw POSIXError(rawValue: errno)!
            default:
                break
            }
        case .IPv4Addr:
            fatalError("Cannot listen to IPV4Address in an ipv6 socket")
        case .Loopback:
            self.sin6_addr = in6addr_loopback
        }
    }
    
    mutating public func withUnsafeSockAddrMutablePointer<T>(@noescape fn: (ptr: UnsafeMutablePointer<sockaddr>, len: socklen_t) -> (T)) -> T {
        return withUnsafeMutablePointer(&self) { ptr in
            return fn(ptr: unsafeBitCast(ptr, UnsafeMutablePointer<sockaddr>.self), len: socklen_t(sizeofValue(self)))
        }
    }
    
    mutating public func withUnsafeSockAddrPointer<T>(@noescape fn: (ptr: UnsafePointer<sockaddr>, len: socklen_t) -> (T)) -> T {
        return withUnsafePointer(&self) { ptr in
            return fn(ptr: unsafeBitCast(ptr, UnsafePointer<sockaddr>.self), len: socklen_t(sizeofValue(self)))
        }
    }

    public static let size = sizeof(sockaddr_in6)
    public static let addressFamily = sa_family_t(AF_INET6)
}

let INADDR_ANY = in_addr(s_addr: 0x00000000)
let INADDR_LOOPBACK4 = in_addr(s_addr: UInt32(0x7f000001).bigEndian)

extension sockaddr_in: SockAddr {
    public static let size = sizeof(sockaddr_in)
    public static let addressFamily = sa_family_t(AF_INET)
    
    public var family: sa_family_t {
        get {
            return self.sin_family
        }
        set {
            self.sin_family = newValue
        }
    }
    
    public var port: UInt16 {
        get {
            return self.sin_port.bigEndian
        }
        set {
            self.sin_port = newValue.bigEndian
        }
    }
    
    public var len: UInt8 {
        get {
            return self.sin_len
        }
        set {
            self.sin_len = newValue
        }
    }
    
    mutating public func setAddress(address: Address) throws {
        switch address {
        case .Any:
            self.sin_addr = INADDR_ANY
        case let .IPv4Addr(address: address):
            switch inet_pton(Int32(sockaddr_in.addressFamily), address, &self.sin_addr) {
            case 0:
                throw Error.NotParseableAddress
            case -1:
                throw POSIXError(rawValue: errno)!
            default:
                break
            }
        case .IPv6Addr:
            fatalError("Cannot listen to IPV6Address in an ipv4 socket")
        case .Loopback:
            self.sin_addr = INADDR_LOOPBACK4
        }
    }
    
    
    mutating public func withUnsafeSockAddrMutablePointer<T>(@noescape fn: (ptr: UnsafeMutablePointer<sockaddr>, len: socklen_t) -> (T)) -> T {
        return withUnsafeMutablePointer(&self) { ptr in
            return fn(ptr: unsafeBitCast(ptr, UnsafeMutablePointer<sockaddr>.self), len: socklen_t(sizeofValue(self)))
        }
    }
    
    mutating public func withUnsafeSockAddrPointer<T>(@noescape fn: (ptr: UnsafePointer<sockaddr>, len: socklen_t) -> (T)) -> T {
        return withUnsafePointer(&self) { ptr in
            return fn(ptr: unsafeBitCast(ptr, UnsafePointer<sockaddr>.self), len: socklen_t(sizeofValue(self)))
        }
    }
}



public protocol FileLike {
    var fd: dispatch_fd_t { get }
}

extension FileLike {
    /// Calls fcntl(fd, F_GETFL)
    func fcntlGetFlags() throws -> Int32 {
        return try Error.throwIfNotSuccessLessThan0(shim_fcntl(fd, F_GETFL, 0))
    }
    
    /// Calls fcntl(fd, F_SETFL, flags)
    func fcntlSetFlags(flags: Int32) throws  {
        try Error.throwIfNotSuccessLessThan0(shim_fcntl(fd, F_SETFL, flags))
    }
    
    func close() throws {
        try Error.throwIfNotSuccessLessThan0(Darwin.close(fd))
    }
}

extension sockaddr_union {
    /// Helper function that simulates creating a union and then returns the apppriate sockaddr
    /// :param: block Takes unsafe pointer of a sockaddr with the len socklen_t.
    ///             inside the block, one should call something like Darwin.accept or Darwin.sockname
    public static func withUnsafeMutableSockaddrInput(@noescape block: (ptr: UnsafeMutablePointer<sockaddr>, inout len: socklen_t) -> (Int32)) throws -> (result: Int32, addr: SockAddr) {
        // We're going to make an ipv6 one since it is longer
        var addr = sockaddr_union()
        var socklen = socklen_t(sizeof(sockaddr_union.self))

        let (result, addrbase): (Int32, sockaddr) = withUnsafeMutablePointer(&addr) { ptr in
            let saptr = sockaddr_union_getsockaddr(ptr)
            
            let s = block(ptr: saptr, len: &socklen)
            
            return (s, saptr.memory)
        }
        
        switch addrbase.sa_family {
        case sa_family_t(AF_INET):
            precondition(Int(addrbase.sa_len) == sizeof(sockaddr_in.self))
            precondition(Int(socklen) == sizeof(sockaddr_in.self))
            return (result, sockaddr_union_getsockaddr_in(&addr).memory)
        case sa_family_t(AF_INET6):
            return (result, sockaddr_union_getsockaddr_in6(&addr).memory)
        default:
            throw Error.UnknownSockaddrType(family: addrbase.sa_family)
        }
    
    }
}


public struct Socket: FileLike {
    public let fd: dispatch_fd_t
    
    init(fd: dispatch_fd_t) {
        self.fd = fd
    }
    
    init(addressInfoFamily: Int32, socktype: Int32 = SOCK_STREAM, proto: Int32 = IPPROTO_TCP) throws {
        fd = try Error.throwIfNotSuccessLessThan0(socket(addressInfoFamily, socktype, proto))
    }
    
    /// Wrapper around accept
    func accept() throws -> (socket: Socket, addr: SockAddr) {
        let r = try sockaddr_union.withUnsafeMutableSockaddrInput { (ptr: UnsafeMutablePointer<sockaddr>, inout len: socklen_t) -> (Int32) in
            return Darwin.accept(self.fd, ptr, &len)
        }
        
        return (Socket(fd: r.result), r.addr)
    }
    
    func bind(var addr: SockAddr) throws {
        try Error.throwIfNotSuccessLessThan0(addr.withUnsafeSockAddrMutablePointer({ (ptr, len)  in
            return Darwin.bind(fd, ptr, len)
        }))
    }
    
    func connect(var addr: SockAddr) throws {
        try Error.throwIfNotSuccessLessThan0(addr.withUnsafeSockAddrMutablePointer({ (ptr, len)  in
            return Darwin.connect(fd, ptr, len)
        }))
    }
    
    static let DefaultListenBacklog: Int32 = 5
    
    func listen(backlog: Int32 = DefaultListenBacklog) throws {
        try Error.throwIfNotSuccessLessThan0(Darwin.listen(fd, backlog))
    }
    
    func sockname() throws -> SockAddr {
        return try sockaddr_union.withUnsafeMutableSockaddrInput { (ptr: UnsafeMutablePointer<sockaddr>, inout len: socklen_t) -> (Int32) in
            return Darwin.getsockname(self.fd, ptr, &len)
        }.addr
    }
    
    /// :param: option option like SO_REUSEPORT or SO_REUSEADDR
    func setsockopt(option: Int32, var value: Int32) throws {
        try Error.throwIfNotSuccessLessThan0(Darwin.setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(sizeofValue(value))))
    }
    
    func getsockopt(option: Int32) throws -> Int32 {
        var value: Int32 = 0
        var len = socklen_t(sizeofValue(value))
        try Error.throwIfNotSuccessLessThan0(Darwin.getsockopt(fd, SOL_SOCKET, option, &value, &len))
        return value
    }

//    public func bind(_: Int32, _: UnsafePointer<sockaddr>, _: socklen_t) -> Int32
//    public func connect(_: Int32, _: UnsafePointer<sockaddr>, _: socklen_t) -> Int32
//    public func getpeername(_: Int32, _: UnsafeMutablePointer<sockaddr>, _: UnsafeMutablePointer<socklen_t>) -> Int32
//    
//    public func getsockname(_: Int32, _: UnsafeMutablePointer<sockaddr>, _: UnsafeMutablePointer<socklen_t>) -> Int32
//    
//    public func getsockopt(_: Int32, _: Int32, _: Int32, _: UnsafeMutablePointer<Void>, _: UnsafeMutablePointer<socklen_t>) -> Int32
//    public func listen(_: Int32, _: Int32) -> Int32

}

extension Socket {
    /// Returns a socket that is bound to address and listening.
    /// The socket is set to have REUSEADDR and REUSEPORT and O_NONBLOCK
    static func boundListeningSocket(socktype: SockAddr.Type, address: Address, port: UInt16 = 0) throws -> Socket {
        var successful = false
        
        let s = try Socket(addressInfoFamily: Int32(socktype.addressFamily))
        
        defer {
            if !successful {
                do {
                    try s.close()
                } catch {
                    // Do nothing. we're already probably throwing an exceptions
                }
            }
        }
        
        try s.fcntlSetFlags(s.fcntlGetFlags() | O_NONBLOCK)
        
        try s.setsockopt(SO_REUSEADDR, value: 1)
        try s.setsockopt(SO_REUSEPORT, value: 1)
        
        var addr = socktype.init()
        
        addr.port = port
        addr.len = UInt8(socktype.size)
        addr.family = socktype.addressFamily

        try addr.setAddress(address)
        
        try s.bind(addr)
        try s.listen()
        
        successful = true
        
        return s
    }

    /// Starts accepting connections on workQueue. Generally called after boundListeningSocket
    public func startAccepting(workQueue: Queue, acceptHandler:(socket: Socket) -> Void) -> (cancelResolver: Resolver<Void>, closedPromise: Promise<Void>) {
        precondition(fd >= 0)
        
        let (cancelResolver, canceledPromise) = VoidPromiseType.resolver(workQueue)
        let (closedResolver, closedPromise) = VoidPromiseType.resolver(workQueue)
        
        let eventSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(fd), 0, workQueue.queue)

        canceledPromise.then { _ in
            dispatch_source_cancel(eventSource)
        }

        dispatch_source_set_event_handler(eventSource) {
            do {
                acceptHandler(socket: try self.accept().socket)
            } catch {
                /// Ignore errors for now. Should we cancel the stream?
            }
        }
        
        dispatch_source_set_cancel_handler(eventSource) {
            precondition(self.fd >= 0)
            do {
                try self.close()
            } catch {
                /// Ignore
            }
            
            closedResolver.resolve()
        }
        
        dispatch_resume(eventSource);
        
        return (cancelResolver, closedPromise)
    }

}

extension dispatch_data_t {
    var empty: Bool {
        get {
            return dispatch_data_empty === self
        }
    }
}

private var hints: addrinfo = {
    var hints = addrinfo()
    hints.ai_family = PF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    return hints
}()


extension Queue {
    /// Used to dispatch synchronous operations on a specific queue
    /// :param queue: queue that promise is constructed with. If nil, will use self.
    func blockingPromise<T>(queue: Queue? = nil, blockingFn: () throws -> T) -> Promise<T>  {
        let (r, p) = Promise<T>.resolver(queue ?? self)
        
        self.dispatchAsync {
            r.attemptResolve(blockingFn)
        }
        
        return p
    }
}


extension Socket {
    public static func tryConnect(queue: Queue, sockAddr: SockAddr) -> Promise<Socket> {
        let (r, p) = Promise<Socket>.resolver(queue)

        let socket: Socket
        do {
            socket = try Socket(addressInfoFamily: Int32(sockAddr.family))
        } catch let e {
            r.reject(e)
            return p
        }
        
        let writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, UInt(socket.fd), UInt(0), queue.queue)
        
        dispatch_source_set_event_handler(writeSource) {
            do {
                let sockerr = try socket.getsockopt(SO_ERROR)
                try Error.throwIfNotSuccessLessThan0(sockerr)

                // If we get this far, we're connected!
                
                dispatch_suspend(writeSource)
                
                ///  Give it a null handler since we want to keep our FD
                dispatch_source_set_cancel_handler(writeSource) {
                    r.resolve(socket)
                }
                
                dispatch_resume(writeSource)
                
                dispatch_source_cancel(writeSource)
                
            } catch POSIXError.EINPROGRESS {
                return
            } catch let e {
                dispatch_source_cancel(writeSource)
                r.reject(e)
            }
        }
        
        dispatch_source_set_cancel_handler(writeSource) {
            do {
                try socket.close()
            } catch { }
        }
        
        dispatch_resume(writeSource)

        do {
            try socket.connect(sockAddr)
        } catch POSIXError.EINPROGRESS {
        } catch let e {
            dispatch_source_cancel(writeSource)
            r.reject(e)
            return p
        }
        
        return p
    }
    
        // Tries to connect to a list of addresses
    // Returns a future with the file descriptor that it connected to
    public static func tryConnect(queue: Queue, sockAddrs: [SockAddr]) -> Promise<Socket> {
        guard sockAddrs.count > 0 else {
            return Promise<Socket>.reject(queue, error: Error.NoAddressesRemaining)
        }
        
        func runAtIdx(idx: Int) -> Promise<Socket> {
            return tryConnect(queue, sockAddr: sockAddrs[idx])
                .then { v -> PromiseOrValue<Socket> in
                    switch v {
                        /// If we're the last one in the array propagate the last error
                    case let .Error(e) where idx == sockAddrs.count - 1:
                        return .Value(.Error(e))
                    case .Error:
                        return .Promised(runAtIdx(idx + 1))
                    case .Some:
                        return .Value(v)
                    }
            }
        }
        
        return runAtIdx(0)
    }

    public static func tryConnect(queue: Queue, hostname: String, port: UInt16) -> Promise<Socket> {
        return  getaddrinfoAsync(hostname, servname: "\(port)")
            .thenSplit(queue) { v -> PromiseOrValue<Socket> in
                return .Promised(Socket.tryConnect(queue, sockAddrs: v.map { ai in return ai.sockAddr}))
        }
    }
}
/// denormalized addrinfo. This way we can pass it w/o holding onto memory
public struct AddrInfo {
    /// AI_PASSIVE, AI_CANONNAME, AI_NUMERICHOST, etc.
    var flags: Int32
    /// PF_*
    var family: Int32
    /// SOCK_*
    var socktype: Int32
    /// 0 or IPPROTO_xxx for IPv4 and IPv6
    var proto: Int32
    var canonname: String?
    let sockAddr: SockAddr
    
    
    init?(ai: addrinfo) {
        flags = ai.ai_flags
        family = ai.ai_family
        socktype = ai.ai_socktype
        proto = ai.ai_protocol
        canonname = String.fromCString(ai.ai_canonname)
        
        switch family {
        case AF_INET:
            precondition(ai.ai_addrlen == socklen_t(sizeof(sockaddr_in.self)))
            sockAddr = unsafeBitCast(ai.ai_addr, UnsafePointer<sockaddr_in>.self).memory
        case AF_INET6:
            precondition(ai.ai_addrlen == socklen_t(sizeof(sockaddr_in6.self)))
            sockAddr = unsafeBitCast(ai.ai_addr, UnsafePointer<sockaddr_in6>.self).memory
        default:
            return nil
        }
    }
}

public func getaddrinfoAsync(hostname: String, servname: String, workQueue: Queue = Queue.defaultGlobalQueue) -> Promise<[AddrInfo]> {
    return workQueue.blockingPromise {
        var ai: UnsafeMutablePointer<addrinfo> = nil
        defer {
            if ai != nil {
                freeaddrinfo(ai)
            }
        }
        
        let r = getaddrinfo(hostname, servname, &hints, &ai)
        guard r == 0 else {
            throw Error.GAIError(status: r)
        }
        
        var ret = [AddrInfo]()
        
        for var curAi = ai; curAi != nil; curAi = curAi.memory.ai_next {
            if let ai = AddrInfo(ai: curAi.memory) {
                ret.append(ai)
            }
        }
        
        return ret;
    }
}