//
//  PromisesTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/3/15.
//
//

@testable import SocketRocketIO
import XCTest


class RawPromiseTests: XCTestCase {
    func testAlreadyReady() {
        let promise = RawPromise(value: 2)
        self.expectationWithPromise(promise) { v in v == 2 }
    }
    
    func testAlreadyReady_chained() {
        let lastPromise = RawPromise(value: 3)
            .then({ x in return .Value(x + 4) })
            .then({ v in return .Value(v + 5) })
        
        self.expectationWithPromise(lastPromise) { v in v == 12 }
    }
    
    func testNotReady_chained() {
        let p = Promise<Int>()
        
        let lastPromise = p
            .thenSplit({ v in return .Value(v + 4) })
            .thenSplit({ v in return .Value(v + 5) })
        
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 12 }
        
        p.fulfill(3)
        
        self.waitForExpectations()
    }
    
}


class PromisesTests: XCTestCase {
    func testAlreadyReady() {
        let firstPromise = Promise(value: 3)
        
        let lastPromise = firstPromise
        
        self.expectationWithPromise(lastPromise) { v in v == 3 }
    }
    
    func testAlreadyReady_chained() {
        let lastPromise = Promise(value: 3)
            .thenSplit({ x in return .Promised(Promise(value: x + 4)) })
            .thenSplit({ v in return .Value(v + 5) })
        
        self.expectationWithPromise(lastPromise) { v in v == 12 }
    }
    
    func testNotReady_chained() {
        let p = Promise<Int>()
        
        let lastPromise = p
            .thenSplit({ v in return .Promised(Promise(value: v + 4)) })
            .thenSplit({ v in return .Value(v + 5) })
        
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 12 }
        
        p.fulfill(3)
        
        self.waitForExpectations()
    }
    
    
    
    
//    func testNotReady_withSupplierBlock() {
//        let p = Promise<Int>() { supply in
//            dispatch_async(dispatch_get_main_queue()) {
//                supply(3)
//            }
//        }
//        
//        
//        let lastPromise = p
//            .then() { v in .of(v + 4) }
//            .then() { v in v + 5 }
//            .then() { v -> Promise<Int> in
//                let resulting = Promise<Int>()
//                
//                dispatch_async(dispatch_get_main_queue()) {
//                    resulting.fulfill(v + 3)
//                }
//                
//                return resulting
//        }
//        
//        self.expectationWithPromise(lastPromise, wait: false) { v in v == 15 }
//        
//        self.waitForExpectations()
//    }
}

extension XCTestCase {
    func expectationWithPromise<T>(promise: RawPromise<T>, wait: Bool = true, file: String = __FILE__, line: UInt = __LINE__, predicate: (T) -> Bool = { _ in true}) -> XCTestExpectation {
        
        let description = "Waiting for promise \(promise) to fulfill"
        
        
        let expectation = self.expectationWithDescription(description)
        
        promise.then { v in
            if !predicate(v)  {
                XCTFail("Predicate failed for promise \(promise) for value \(v)", file:file, line:line)
            }
            expectation.fulfill()
        }
        
        if wait {
            self.waitForExpectations()
        }
        
        return expectation
    }

    
    // Terminates a promise and returns an XCTestExpectation for it
    func expectationWithPromise<T>(promise: Promise<T>, wait: Bool = true, file: String = __FILE__, line: UInt = __LINE__, predicate: (T) -> Bool = { _ in true}) -> XCTestExpectation {

        let description = "Waiting for promise \(promise) to fulfill"
    

        let expectation = self.expectationWithDescription(description)
        
        promise.then { v in
            switch v {
            case .Error:
                XCTFail("Promise failed for promise \(promise) for value \(v)", file:file, line:line)
            case let .Some(newV):
                if !predicate(newV)  {
                    XCTFail("Predicate failed for promise \(promise) for value \(v)", file:file, line:line)
                }

            }
            expectation.fulfill()
        }
        
        if wait {
            self.waitForExpectations()
        }
        
        return expectation
    }
}

