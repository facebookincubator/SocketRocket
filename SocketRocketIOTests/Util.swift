//
//  Util.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/6/16.
//
//

import Foundation
import XCTest
import RxSwift

func XCTAssertEqualT<T : Equatable>(@autoclosure expression1: () throws -> T, @autoclosure _ expression2: () -> T, _ message: String = "", file: String = __FILE__, line: UInt = __LINE__){
    do {
        let v = try expression1()
        XCTAssertEqual(v, expression2(), line: line, file:file)
    } catch let e {
        XCTFail("\(e)", line: line, file:file)
    }
}

extension POSIXError: CustomDebugStringConvertible {
    public var debugDescription: String {
        get {
            var buffer = [CChar](count: 1024, repeatedValue: 0)
            
            guard strerror_r(rawValue, &buffer, buffer.count) == 0 else {
                return "Unknown!!"
            }
            
            return "Posix Error \(rawValue) " + (String.fromCString(&buffer) ?? "Issue converting to cstring")
        }
    }
}

var defaultWaitTimeout: NSTimeInterval = 10.0


/// Wraps a test case and an observable to block on the result and wait for values
public class ObservableFuture<E> {
    let description: String
    let testCase: XCTestCase /// Where we were created
    
    let disposeBag = DisposeBag()
    
    let replayObservable: ConnectableObservable<E>
    
    private init<O: ObservableType where O.E == E>(description: String, observable: O, testCase: XCTestCase) {
        self.description = description
        self.testCase = testCase
        
        replayObservable = observable.replay(1024)
        
        replayObservable.connect().addDisposableTo(disposeBag)
    }
    
    /// Call this to wait for the expectation and get the value
    public func get(timeout timeout: NSTimeInterval=defaultWaitTimeout, file: String=__FILE__, line: UInt=__LINE__) -> [E] {
        let expectation = testCase.expectationWithDescription(description)
        
        var result = [E]()
        
        replayObservable
            .subscribeOn(MainScheduler.instance)
            .subscribe(
                onNext: {
                    val in result.append(val)
                },
                onError: { e in
                    XCTFail("Error with observable  \(Mirror(reflecting: e).description)", file: file, line: line)
                },
                onCompleted: { expectation.fulfill() })
            .addDisposableTo(disposeBag)
        
        testCase.waitForExpectations(timeout)
        
        return result
    }
}

public extension SequenceType where Generator.Element == UInt8 {
    // Converts to a string w/ UTF8 data
    var utf8String: String? {
        // Append a zero to ourselves
        let buff = Array(self) + [0]
        return buff.withUnsafeBufferPointer { ptr in
            return String.fromCString(unsafeBitCast(ptr.baseAddress, UnsafePointer<Int8>.self))
        }
    }
}
extension ObservableType {
    /// Makes a Future out of an observable. It requires a test since it depends on waiting for expectations.
    /// It starts recording immediately. One should call get on the resultss
    @warn_unused_result
    public func subscribeFuture(test: XCTestCase, description: String? = nil) -> ObservableFuture<E> {
        let description = description ?? "Completion of observable \(Mirror(reflecting: self).description)"
        
        return ObservableFuture(description: description, observable: self, testCase: test)
    }
}

extension XCTestCase {
    
    /// Making it so you can easily wait for expectation
    public func waitForExpectations(timeout: NSTimeInterval=defaultWaitTimeout) {
        self.waitForExpectationsWithTimeout(timeout, handler: nil)
    }
}