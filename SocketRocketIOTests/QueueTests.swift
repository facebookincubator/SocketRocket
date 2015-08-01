//
//  QueueTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 7/30/15.
//
//

import XCTest
import SocketRocketIO

class QueueTests: XCTestCase {
    func testMainQueue() {
        let queue = Queue.mainQueue
        
        let expectation = expectationWithDescription("Should dispatch")
        queue.dispatchAsync {
            expectation.fulfill()
        }

        waitForExpectations()
    }
    
    func testMainQueueRecognizesSelf() {
        
        let expectation = expectationWithDescription("Should dispatch")
        let queue = Queue.mainQueue
        
        queue.dispatchAsync {
            XCTAssertTrue(Queue.mainQueue.isCurrentQueue())
            expectation.fulfill()
        }
        
        waitForExpectations()
    }
    
    
    func testCheckIsCurrentQueue() {
        let expectation = expectationWithDescription("Should dispatch")
        let queue = Queue(label: "queueLabel")
        
        queue.dispatchAsync {
            XCTAssertTrue(queue.isCurrentQueue())
            queue.checkIsCurrentQueue()
            expectation.fulfill()
        }
        
        waitForExpectations()
        
        
        XCTAssertFalse(queue.isCurrentQueue())
    }
}

let defaultTimeout: NSTimeInterval = 10

extension XCTestCase {

    func waitForExpectations() -> Void {
        waitForExpectationsWithTimeout(defaultTimeout, handler: nil)
    }
}