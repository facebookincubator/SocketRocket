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
        
        let streamer = DispatchIO(io: io)
        
        var accumulated = [UInt8]()
        
        let readQueue = Queue(label: "Read queue")
        
        let p = streamer.read(Int.max, queue: readQueue) { data in
            accumulated += data
        }
        
        expectationWithPromise(p)
        
        dispatch_io_close(io, 0)
        
        let readData = String(bytes:accumulated, encoding: NSUTF8StringEncoding)
        
        XCTAssertEqual(readData!, "hello\nthis\nis a file\n\nI like to read from it")
    }
    
    
    func testErrorHandling() {
        let io = dispatch_io_create_with_path(DISPATCH_IO_STREAM, QueueStreamableTests.filePath, O_RDONLY, 0, Queue.mainQueue.queue) { _ in }
        
        let streamer = DispatchIO(io: io)
        
        let readQueue = Queue(label: "Read queue")
        
        dispatch_suspend(readQueue.queue)

        let f = streamer.read(Int.max, queue: readQueue) { v in
            
        }
        
        
        dispatch_io_close(streamer.io, DISPATCH_IO_STOP)
        
        dispatch_resume(readQueue.queue)
        
        
        expectationWithFailingPromise(f)
    }
    
    
    func testCodeUnits() {
        let s  = "💩1💩"
        
        
        var data = [UInt8]()
        
        for s in s.unicodeScalars {
            UTF8.encode(s) { (cu) -> () in
                data.append(cu)
            }
        }
        
        XCTAssertEqualT(try UTF8.numValidCodeUnits(data.generate()), 9)
        XCTAssertEqualT(try UTF8.numValidCodeUnits(data[0..<8].generate()), 5)
        XCTAssertEqualT(try UTF8.numValidCodeUnits(data[0..<5].generate()), 5)
        XCTAssertEqualT(try UTF8.numValidCodeUnits(data[0..<4].generate()), 4)
        XCTAssertEqualT(try UTF8.numValidCodeUnits(data[0..<3].generate()), 0)
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

func XCTAssertEqualT<T : Equatable>(@autoclosure expression1: () throws -> T, @autoclosure _ expression2: () -> T, _ message: String = "", file: String = __FILE__, line: UInt = __LINE__)
{
    do {
        let v = try expression1()
        XCTAssertEqual(v, expression2(), line: line, file:file)
    } catch let e {
        XCTFail("\(e)", line: line, file:file)
    }
}
