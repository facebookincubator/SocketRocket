//
//  IOTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 7/31/15.
//
//


enum FailureError: ErrorType {
    case Failure
}

import XCTest
@testable import SocketRocketIO

class IOTests: XCTestCase {
    let sockaddrTypes: [SockAddr.Type] = [sockaddr_in.self, sockaddr_in6.self]
    
    func testGetAddrInfoAsync() {
            let promise: Promise<[AddrInfo]>  = getaddrinfoAsync("squareup.com", servname: "443")
                .thenChecked { v in
                    let v = try v.checkedGet()
                    XCTAssertGreaterThan(v.count, 0)
                    return v
                }
                .thenChecked(Queue.mainQueue) { (v: ErrorOptional<[AddrInfo]>) throws in
                    guard Queue.mainQueue.isCurrentQueue() else {
                        throw FailureError.Failure
                    }
                    return try v.checkedGet()
            }
            
            self.expectationWithPromise(promise)
    }
    
    func testGetAddrInfoAsyncFailure() {
        let promise: Promise<[AddrInfo]>  = getaddrinfoAsync("", servname: "")
        self.expectationWithFailingPromise(promise)
    }
    
    func testListen() {
        for t in sockaddrTypes {
            let acceptExpectation = expectationWithDescription("waiting")
            
            let s = try! Socket.boundListeningSocket(t, address: .Loopback, port: 0)
            
            let q = Queue(label: "testListen")
            
            let (cancelResolver, closedPromise) = s.startAccepting(Queue.mainQueue) {
                (sock) -> Void in
                try! sock.close()
                acceptExpectation.fulfill()
            }
            
            let connectAddr = try! s.sockname()
            
            let listenPort = connectAddr.port
            XCTAssertNotEqual(listenPort, 0)
            
            let connectPromise = Socket.tryConnect(q, sockAddr: connectAddr)
                .thenChecked { v in
                    try v.checkedGet().close()
            }
            
            self.expectationWithPromise(connectPromise, wait:false)
            
            waitForExpectations()
            
            cancelResolver.resolve()
            
            self.expectationWithPromise(closedPromise)
        }
    }
    
    func testListenIPV6Name() {
        let acceptExpectation = expectationWithDescription("waiting")
        
        let s = try! Socket.boundListeningSocket(sockaddr_in6.self, address: .IPv6Addr(address: "::1"), port: 0)
        
        let q = Queue(label: "testListen")
        
        let (cancelResolver, closedPromise) = s.startAccepting(Queue.mainQueue) {
            (sock) -> Void in
            try! sock.close()
            acceptExpectation.fulfill()
        }
        
        let connectAddr = try! s.sockname()
        
        let listenPort = connectAddr.port
        XCTAssertNotEqual(listenPort, 0)
        
        let connectPromise = Socket.tryConnect(q, sockAddr: connectAddr)
            .thenChecked { v in
                try v.checkedGet().close()
        }
        
        self.expectationWithPromise(connectPromise, wait:false)
        
        waitForExpectations()
        
        cancelResolver.resolve()
        
        self.expectationWithPromise(closedPromise)
    }
    
    func testListenIPV4Name() {
        let acceptExpectation = expectationWithDescription("waiting")
        
        let s = try! Socket.boundListeningSocket(sockaddr_in.self, address: .IPv4Addr(address: "127.0.0.1"), port: 0)
        
        let q = Queue(label: "testListen")
        
        let (cancelResolver, closedPromise) = s.startAccepting(Queue.mainQueue) {
            (sock) -> Void in
            try! sock.close()
            acceptExpectation.fulfill()
        }
        
        let connectAddr = try! s.sockname()
        
        let listenPort = connectAddr.port
        XCTAssertNotEqual(listenPort, 0)
        
        let connectPromise = Socket.tryConnect(q, sockAddr: connectAddr)
            .thenChecked { v in
                try v.checkedGet().close()
        }
        
        self.expectationWithPromise(connectPromise, wait:false)
        
        waitForExpectations()
        
        cancelResolver.resolve()
        
        self.expectationWithPromise(closedPromise)
    }
    
    func testListen_multiconnect() {
        for t in sockaddrTypes {
            let acceptExpectation = expectationWithDescription("waiting")
            
            let s = try! Socket.boundListeningSocket(t, address: .Loopback, port: 0)
            
            
            let q = Queue(label: "testListen")
            
            let (cancelResolver, closedPromise) = s.startAccepting(Queue.mainQueue) {
                (sock) -> Void in
                try! sock.close()
                acceptExpectation.fulfill()
            }
            
            let connectAddr = try! s.sockname()
            
            let listenPort = connectAddr.port
            XCTAssertNotEqual(listenPort, 0)
            
            let connectPromise = getaddrinfoAsync("localhost", servname: "\(listenPort)")
                .thenSplit(q) { v -> PromiseOrValue<Socket> in
                    return .Promised(Socket.tryConnect(q, sockAddrs: v.map { ai in return ai.sockAddr}))
                }.thenChecked { v in
                    try v
                        .checkedGet()
                        .close()
            }
            
            self.expectationWithPromise(connectPromise, wait:false)
            
            waitForExpectations()
            
            cancelResolver.resolve()
            
            self.expectationWithPromise(closedPromise)
        }
    }
    
    func testTryConnect() {
        for t in sockaddrTypes {
            let acceptExpectation = expectationWithDescription("waiting")
            
            let s = try! Socket.boundListeningSocket(t, address: .Loopback, port: 0)
            
            let q = Queue(label: "testListen")
            
            let (cancelResolver, closedPromise) = s.startAccepting(Queue.mainQueue) {
                (sock) -> Void in
                try! sock.close()
                acceptExpectation.fulfill()
            }
            
            let connectAddr = try! s.sockname()
            
            let listenPort = connectAddr.port
            XCTAssertNotEqual(listenPort, 0)
            
            let connectPromise = Socket.tryConnect(q, hostname: "localhost", port: listenPort)
                .thenChecked { v in
                    try v
                        .checkedGet()
                        .close()
            }
            
            self.expectationWithPromise(connectPromise, wait:false)
            
            waitForExpectations()
            
            cancelResolver.resolve()
            
            self.expectationWithPromise(closedPromise)
        }
    }
}
