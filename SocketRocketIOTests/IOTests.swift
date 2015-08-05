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
    func testGetAddrInfoAsync() {
        let promise: Promise<[addrinfo]>  = getaddrinfoAsync("squareup.com", servname: "443")
            .thenChecked { v in
                let v = try v.checkedGet()
                XCTAssertGreaterThan(v.count, 0)
                return v
            }
            .thenChecked(Queue.mainQueue) { (v: ErrorOptional<[addrinfo]>) throws in
                guard Queue.mainQueue.isCurrentQueue() else {
                    throw FailureError.Failure
                }
                return try v.checkedGet()
        }
        
        
        self.expectationWithPromise(promise)
    }
    
    func testGetAddrInfoAsyncFailure() {
        let promise: Promise<[addrinfo]>  = getaddrinfoAsync("", servname: "")
        self.expectationWithFailingPromise(promise)
    }
    
    func testListen() {
        return
        do {
            let acceptExpectation = expectationWithDescription("waiting")
            
            let cancelGroup = dispatch_group_create()
            dispatch_group_enter(cancelGroup)
            let s = try Socket<sockaddr_in>(address: .Loopback, port: 9231)
            let canceler = s.startAccepting(
                Queue.mainQueue,
                cancelHandler: {
                    dispatch_group_leave(cancelGroup)
                },
                acceptHandler: {
                    (fd) -> Void in
                    close(fd)
                    acceptExpectation.fulfill()
            })
            
            
            waitForExpectations()
            
            let cancelExpection = expectationWithDescription("Canceled")
            
            dispatch_group_notify(cancelGroup, dispatch_get_main_queue()) {
                cancelExpection.fulfill()
            }
            canceler()
            waitForExpectations()
        } catch let e  {
            XCTFail("\(e)")
        }
    }
}
