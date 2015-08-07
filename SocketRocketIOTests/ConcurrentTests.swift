//
//  ConcurrentTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/7/15.
//
//

@testable import SocketRocketIO
import XCTest

class ConcurrentTests: XCTestCase {
    func testOnce_simple() {
        var once = Once()
        
        let e2 = expectationWithDescription("All done")
        
        let g = dispatch_group_create()
        let g2 = dispatch_group_create()
        
        dispatch_group_enter(g)
        dispatch_group_notify(g2, Queue.defaultGlobalQueue.queue) {
            e2.fulfill()
        }
        
        for bit in 0..<8 {
            let e = expectationWithDescription("Once filled")
            for _ in 0..<1000 {
                dispatch_group_enter(g2)
                dispatch_group_notify(g, Queue.defaultGlobalQueue.queue) {
                    once.doMaybe(bit, block: {
                        e.fulfill()
                    })
                    dispatch_group_leave(g2)
                }
            }
        }
        

        dispatch_group_leave(g)
        waitForExpectations()
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
