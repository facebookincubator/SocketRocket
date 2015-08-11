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
    func testPGroup_noerr() {
        let p = PGroup<Int>(queue: Queue.mainQueue)
        
        p.resolve(3)
        
        for i in 0..<20 {
            let e = self.expectationWithDescription("e \(i)")
            p.then { v in
                XCTAssertFalse(v.hasError)
                e.fulfill()
            }
        }
        
        self.waitForExpectations()
    }

    func testPGroup_after() {
        let p = PGroup<Int>(queue: Queue.mainQueue)

        for i in 0..<20 {
            let e = self.expectationWithDescription("e \(i)")
            p.then { v in
                XCTAssertFalse(v.hasError)
                e.fulfill()
                switch v {
                case let .Some(val):
                    XCTAssertEqual(val, 3)
                default:
                    XCTFail()
                }
            }
        }

        p.resolve(3)

        self.waitForExpectations()
    }
    
    func testPGroup_calledOnce() {
        let p = PGroup<Int>(queue: Queue.mainQueue)
        
        for i in 0..<20 {
            let e = self.expectationWithDescription("e \(i)")
            p.then { v in
                switch v {
                case let .Some(val):
                    XCTAssertEqual(val, 3)
                default:
                    XCTFail()
                }
                e.fulfill()
            }
        }
        
        
        p.resolve(3)
        p.resolve(4)
        p.reject(Error.Canceled)
        
        self.waitForExpectations()
    }
    
    func testPGroup_canceled() {
        let p = PGroup<Int>(queue: Queue.mainQueue)
        
        for i in 0..<20 {
            let e = self.expectationWithDescription("e \(i)")
            p.then { v in
                switch v {
                case .Error(Error.Canceled):
                    break
                default:
                    XCTFail()
                }
                e.fulfill()
            }
        }
        
        p.cancel()

        p.resolve(3)
        p.resolve(4)
        p.reject(Error.Canceled)
        
        self.waitForExpectations()
    }
}
