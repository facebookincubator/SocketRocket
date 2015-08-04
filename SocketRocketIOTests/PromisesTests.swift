//
//  PromisesTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/3/15.
//
//

import SocketRocketIO
import XCTest


class PromisesTests: XCTestCase {
    func testAlreadyReady() {
        
        let firstPromise = Promise(3)
        
        
        let lastPromise = firstPromise
        
        self.expectationWithPromise(lastPromise) { v in v == 3 }

    }
    
    func testAlreadyReady_chained() {
        let lastPromise = Promise(3)
            .then({ v in return .of(v + 4) } )
            .then({ v in return v + 5 })
        
        self.expectationWithPromise(lastPromise) { v in v == 12 }
    }
    
    func testNotReady_chained() {
        let p = Promise<Int>()
        
        let lastPromise = p
            .then({ v in return .of(v + 4) } )
            .then({ v in return v + 5 })
        
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 12 }
        
        p.fulfill(3)
        
        self.waitForExpectations()
    }
    
    func testNotReady_withSupplierBlock() {
        let p = Promise<Int>() { supply in
            dispatch_async(dispatch_get_main_queue()) {
                supply(3)
            }
        }
        
        
        let lastPromise = p
            .then() { v in .of(v + 4) }
            .then() { v in v + 5 }
            .then() { v -> Promise<Int> in
                let resulting = Promise<Int>()
                
                dispatch_async(dispatch_get_main_queue()) {
                    resulting.fulfill(v + 3)
                }
                
                return resulting
        }
        
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 15 }
        
        self.waitForExpectations()
    }
}

extension XCTestCase {
    // Terminates a promise and returns an XCTestExpectation for it
    func expectationWithPromise<T>(promise: Promise<T>, wait: Bool = true, file: String = __FILE__, line: UInt = __LINE__, predicate: (T) -> Bool = { _ in true}) -> XCTestExpectation {

        let description = "Waiting for promise \(promise) to fulfill"
    

        let expectation = self.expectationWithDescription(description)
        
        promise.finally() { v in
            if !predicate(v) {
                XCTFail("Predicate failed for promise \(promise) for value \(v)", file:file, line:line)
            }
            expectation.fulfill()
        }
        
        if wait {
            self.waitForExpectations()
        }
        
        return expectation
    }
}

