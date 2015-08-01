//
//  IOTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 7/31/15.
//
//

import XCTest
import SocketRocketIO

class IOTests: XCTestCase {

    func testListen() {
        
        do {
            let acceptExpectation = expectationWithDescription("waiting")
            
            let cancelGroup = dispatch_group_create()
            dispatch_group_enter(cancelGroup)
            let s = try Socket<sockaddr_in>(listenAddr: .Loopback, listenPort: 9231)
            let canceler = s.startAccepting(Queue.mainQueue, cancelHandler: {
                dispatch_group_leave(cancelGroup)
                }) {
                    (fd) -> Void in
                    close(fd)
                    acceptExpectation.fulfill()
            }
            
            
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
        //        s.startAcceptin
    }
}
