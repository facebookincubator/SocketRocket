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
            .then(nil) { x in return .Value(x + 4) }
            .then(nil) { v in return .Value(v + 5) }
        
        self.expectationWithPromise(lastPromise) { v in v == 12 }
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
            .thenSplit(success: { x in return .Promised(Promise(value: x + 4)) })
            .thenSplit(success: { v in return .of(v + 5) })
        
        self.expectationWithPromise(lastPromise) { v in v == 12 }
    }
    
    func testNotReady_chained() {
        let p = Promise<Int>()
        
        let lastPromise = p
            .thenSplit(success: { v in return .Promised(Promise(value: v + 4)) })
            .thenSplit(success: { v in return .of(v + 5) })
        
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 12 }
        
        p.fulfill(3)
        
        self.waitForExpectations()
    }
    
    
    func testNotReady_chained2() {
        let p = Promise<Int>()
        
        let lastPromise = p
            .thenSplit(success: { v in return .of(v + 4) })
            .thenSplit(success: { v in return .of(v + 5) })
            .then { val -> ErrorOptional<Int> in
                switch val {
                case .Error:
                    preconditionFailure("Should not get here")
                case let .Some(v):
                    return .Some(v + 5)
                }
        }
        
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 17 }
        
        p.fulfill(3)
        
        self.waitForExpectations()
    }
    
    
    func testDispatchesOnQueue_dispatchesOnQue() {
        let p = Promise<Int>()
        
        let e1 = self.expectationWithDescription("1")
        let e2 = self.expectationWithDescription("2")
        
        let q1 = Queue.defaultGlobalQueue
        let q2 = Queue(label: "random queue")
        
        
        let lastPromise = p
            .thenChecked(q1) { v throws -> Int in
                XCTAssertTrue(q1.isCurrentQueue())
                e1.fulfill()
                return try v.checkedGet() + 2
            }
            .thenChecked(q2) { v throws -> Int in
                XCTAssertTrue(q2.isCurrentQueue())
                e2.fulfill()
                return try v.checkedGet() + 2
            }
        
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 7 }
        
        p.fulfill(3)
        
        self.waitForExpectations()
    }

    func testErrorHandling() {
        self.expectationWithFailingPromise(Promise<Int>(error: OSError.OSError(status: 0))) { v in
            switch v {
            case let OSError.OSError(status):
                return status == 0
            default:
                return false
            }
        }
        
        let lastPromise = Promise(value: 3)
            .thenSplit { v in return .of(v + 4) }
            .thenSplit { v in return .of(v + 5) }
            .then { val -> ErrorOptional<Int> in
                return .Error(OSError.OSError(status: 1))
        }

        self.expectationWithFailingPromise(lastPromise)


    }
    
    func testOkChecked() {
        let lastPromise = Promise(value: 3)
            .thenSplit { v in return .of(v + 4) }
            .thenSplit { v in return .of(v + 5) }
            .thenChecked { v throws in
                return try v.checkedGet() + 3
            }
        
        self.expectationWithPromise(lastPromise) { v in
            return v == 15
        }
    }
    
    func testFailedChecked() {
        let lastPromise = Promise(value: 3)
            .thenSplit { v in return .of(v + 4) }
            .thenSplit { v in return .of(v + 5) }
            .thenChecked { _ throws -> Int in
                throw OSError.OSError(status: 32)
            }
        
        self.expectationWithFailingPromise(lastPromise) { v in
            switch v {
            case let OSError.OSError(status):
                return status == 32
            default:
                return false
            }
        }
    }
    
    func testFailedCascade() {
        let lastPromise = Promise(value: 3)
            .thenChecked { _ throws -> Int in
                throw OSError.OSError(status: 32)
            }
            .thenSplit { v in return .of(v + 4) }
            .thenSplit { v in return .of(v + 5) }
            .thenChecked { v throws -> Int in
                try v.checkedGet()
                throw OSError.OSError(status: 55)
            }
        
        self.expectationWithFailingPromise(lastPromise) { v in
            switch v {
            case let OSError.OSError(status):
                return status == 32
            default:
                return false
            }
        }
    }
}

extension XCTestCase {
    func expectationWithPromise<T>(promise: RawPromise<T>, wait: Bool = true, file: String = __FILE__, line: UInt = __LINE__, predicate: (T) -> Bool = { _ in true}) -> XCTestExpectation {
        
        let description = "Waiting for promise \(promise) to fulfill"
        let expectation = self.expectationWithDescription(description)
        
        promise.then(nil) { v in
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
    
    // Terminates a promise and returns an XCTestExpectation for it
    func expectationWithFailingPromise<T>(promise: Promise<T>, wait: Bool = true, file: String = __FILE__, line: UInt = __LINE__, predicate: (ErrorType) -> Bool = { _ in true}) -> XCTestExpectation {
        
        let description = "Waiting for promise \(promise) to fulfill"
        
        
        let expectation = self.expectationWithDescription(description)
        
        promise.then { v in
            switch v {
            case let .Error(e):
                if !predicate(e)  {
                    XCTFail("Predicate failed for promise \(promise) for value \(v)", file:file, line:line)
                }
            case .Some:
                XCTFail("Expected error for promise, but got value promise \(promise) for value \(v)", file:file, line:line)
                
            }
            expectation.fulfill()
        }
        
        if wait {
            self.waitForExpectations()
        }
        
        return expectation
    }

}

