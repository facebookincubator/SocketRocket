//
//  QueueStreamableTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/6/15.
//
//

import XCTest
@testable import SocketRocketIO

class QueueStreamableTests: XCTestCase {
    static let filePath = NSBundle(forClass: QueueStreamableTests.self).pathForResource("FileToReadFrom", ofType: "txt", inDirectory: "Fixtures")!
    
    func testManualAccumulating() {
        let io = dispatch_io_create_with_path(DISPATCH_IO_STREAM, QueueStreamableTests.filePath, O_RDONLY, 0, Queue.mainQueue.queue) { _ in }
        
        let streamer = IOReaderWrapper(baseIO: io)
        
        var accumulated = [UInt8]()
        
        let endExpectation = self.expectationWithDescription("Stream ended")
        
        func thenHandler(t: ErrorOptional<MoreOrEnd<dispatch_data_t>>) {
            switch t {
            case let .Error(e):
                XCTFail("\(e)")

            case let .Some(moreOrEnd):
                switch moreOrEnd {
                case .End:
                    endExpectation.fulfill()
                case let .More(data, continuation):
                    data.apply { buffer in
                        accumulated += buffer
                        return true
                    }
                    
                    continuation.then(handler: thenHandler)
                }
            }
        }
        
        let readQueue = Queue(label: "Read queue")
        let f = streamer.read(Int.max, queue: readQueue)
        
        f.then(handler: thenHandler)
        
        waitForExpectations()
        
        dispatch_io_close(io, 0)
        
        let readData = String(bytes:accumulated, encoding: NSUTF8StringEncoding)
        
        XCTAssertEqual(readData!, "hello\nthis\nis a file\n\nI like to read from it")
    }
    
    
    func testErrorHandling() {
        let io = dispatch_io_create_with_path(DISPATCH_IO_STREAM, QueueStreamableTests.filePath, O_RDONLY, 0, Queue.mainQueue.queue) { _ in }
        
        let streamer = IOReaderWrapper(baseIO: io)
        
        let endExpectation = self.expectationWithDescription("Stream ended")
        
        func thenHandler(t: ErrorOptional<MoreOrEnd<dispatch_data_t>>) {
            switch t {
            case .Error(POSIXError.ECANCELED):
                endExpectation.fulfill()
            default:
                XCTFail("Expected Error of ECANCELED")
            }
        }
        
        let readQueue = Queue(label: "Read queue")
        
        dispatch_suspend(readQueue.queue)

        let f = streamer.read(Int.max, queue: readQueue)
        
        f.then(handler: thenHandler)
        
        dispatch_io_close(streamer.io, DISPATCH_IO_STOP)
        
        dispatch_resume(readQueue.queue)

        waitForExpectations()
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