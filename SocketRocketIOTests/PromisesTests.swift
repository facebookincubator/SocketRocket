//
//  PromisesTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/3/15.
//
//

@testable import SocketRocketIO
import XCTest


class PromisesTests: XCTestCase {
    func testAlreadyReady() {
        let firstPromise = Promise.resolve(Queue.mainQueue, value: 3)
        
        let lastPromise = firstPromise
        
        self.expectationWithPromise(lastPromise) { v in v == 3 }
    }
    
    func testAlreadyReady_chained() {
        let lastPromise = Promise.resolve(Queue.mainQueue, value: 3)
            .thenSplit(success: { x in return .Promised(.resolve(Queue.mainQueue, value: x + 4)) })
            .thenSplit(success: { v in return .of(v + 5) })
        
        self.expectationWithPromise(lastPromise) { v in v == 12 }
    }
    
    func testNotReady_chained() {
        let (r, p) = Promise<Int>.resolver(Queue.mainQueue)
        
        let lastPromise = p
            .thenSplit(success: { v in return .Promised(.resolve(Queue.mainQueue, value: v + 4)) })
            .thenSplit(success: { v in return .of(v + 5) })
        
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 12 }
        
        r.resolve(3)
        
        self.waitForExpectations()
    }
    
    
    func testNotReady_chained2() {
        let (r, p) = Promise<Int>.resolver(Queue.mainQueue)
        
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
        
        r.resolve(3)
        
        self.waitForExpectations()
    }
    
    
    func testDispatchesOnQueue_dispatchesOnQue() {
        let (r, p) = Promise<Int>.resolver(Queue.mainQueue)
        
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
        
        r.resolve(3)
        
        self.waitForExpectations()
    }
    
    func testDispatchesOnQueue_dispatchesOnQueWithPromises() {
        let e1 = self.expectationWithDescription("1")
        let e2 = self.expectationWithDescription("2")
        
        let q1 = Queue.defaultGlobalQueue
        let q2 = Queue(label: "random queue")
        
        let (r, p) = Promise<Int>.resolver(q1)

        let lastPromise = p
            .thenChecked { v throws -> Int in
                XCTAssertTrue(q1.isCurrentQueue())
                e1.fulfill()
                return try v.checkedGet() + 2
            }
            .then(q2) { v -> PromiseOrValue<Int> in
                XCTAssertTrue(q2.isCurrentQueue())
                e2.fulfill()
                return PromiseOrValue.Promised(Promise.resolve(q1, value: v.orNil! + 3))
            }
            .thenChecked { v throws -> Int in
                XCTAssertTrue(q2.isCurrentQueue())
                return try v.checkedGet() + 2
            }
            .thenChecked { v throws -> Int in
                XCTAssertTrue(q2.isCurrentQueue())
                return try v.checkedGet() + 2
        }
        
        let p2 = p
            .thenChecked { v throws -> Int in
                XCTAssertTrue(q1.isCurrentQueue())
                return try v.checkedGet() + 2
            }
            .then(q2) { v -> PromiseOrValue<Int> in
                XCTAssertTrue(q2.isCurrentQueue())
                return PromiseOrValue.Promised(Promise.resolve(q1, value: v.orNil! + 3))
            }
            .thenChecked { v throws -> Int in
                XCTAssertTrue(q2.isCurrentQueue())
                return try v.checkedGet() + 2
            }
            .thenChecked { v throws -> Int in
                XCTAssertTrue(q2.isCurrentQueue())
                return try v.checkedGet() + 2
            }
        
        
        self.expectationWithPromise(p2, wait: false)
        self.expectationWithPromise(lastPromise, wait: false) { v in v == 12 }
        
        r.resolve(3)
        
        self.waitForExpectations()
    }


    func testErrorHandling() {
        self.expectationWithFailingPromise(Promise<Int>.reject(Queue.mainQueue, error: POSIXError.ENOEXEC)) { v in
            switch v {
            case POSIXError.ENOEXEC:
                return true
            default:
                return false
            }
        }
        
        let lastPromise = Promise.resolve(Queue.mainQueue, value: 3)
            .thenSplit { v in return .of(v + 4) }
            .thenSplit { v in return .of(v + 5) }
            .then { val -> ErrorOptional<Int> in
                return .Error(POSIXError.ENODATA)
        }

        self.expectationWithFailingPromise(lastPromise)

    }
    
    func testOkChecked() {
        let lastPromise = Promise.resolve(Queue.mainQueue, value: 3)
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
        let lastPromise = Promise.resolve(Queue.mainQueue, value: 3)
            .thenSplit { v in return .of(v + 4) }
            .thenSplit { v in return .of(v + 5) }
            .thenChecked { _ throws -> Int in
                throw POSIXError.ENOENT
            }
        
        self.expectationWithFailingPromise(lastPromise) { v in
            switch v {
            case POSIXError.ENOENT:
                return true
            default:
                return false
            }
        }
    }
    
    func testFailedCascade() {
        let lastPromise = Promise.resolve(.mainQueue, value: 3)
            .thenChecked { _ throws -> Int in
                throw POSIXError.ECANCELED
            }
            .thenSplit { v in return .of(v + 4) }
            .thenSplit { v in return .of(v + 5) }
            .thenChecked { v throws -> Int in
                try v.checkedGet()
                throw POSIXError.ENOENT
            }
        
        self.expectationWithFailingPromise(lastPromise) { v in
            switch v {
            case POSIXError.ECANCELED:
                return true
            default:
                return false
            }
        }
    }
}

extension XCTestCase {
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

