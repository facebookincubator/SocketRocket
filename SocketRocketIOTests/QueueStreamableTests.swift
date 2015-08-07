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
    
    
    func testDecoding() {
        var uc = UTF8()
        
        let s  = "💩1💩"
        
        var data = [UInt8]()
        
        for s in s.unicodeScalars {
            UTF8.encode(s) { (cu) -> () in
                data.append(cu)
            }
        }

        XCTAssertEqual(data.count, 9)

        var c = RawUTF8Codec<ArraySlice<UInt8>, ArraySlice<UInt8>.Generator>()
        
        var buff = String()
        
        func accumulate(slice: ArraySlice<UInt8>, line: UInt = __LINE__, file: String = __FILE__) -> Bool {
            do {
                let v = try c.code(ValueOrEnd.Value(slice))
                
                switch v {
                case .End:
                    return true
                case let .Value(v):
                    buff += v
                    return false
                }
            } catch let e {
                XCTFail("\(e)", line:line, file:file)
                return false
            }
        }
        
        
        XCTAssertFalse(accumulate(data[0..<2]))
        XCTAssertFalse(accumulate(data[2..<3]))
        XCTAssertFalse(accumulate(data[3..<8]))
        XCTAssertFalse(accumulate(data[8..<9]))
        
        
        do {
            let r = try c.code(.End)
            
            switch r {
            case .Value:
                XCTFail()
            default:
                break
            }
        } catch let e {
            XCTFail("\(e)")
        }
        
        XCTAssertEqual(buff, s)
    }
    
    
    func testDecoding_errorHandling() {
        var uc = UTF8()
        
        let s  = "💩1💩"
        
        var data = [UInt8]()
        
        for s in s.unicodeScalars {
            UTF8.encode(s) { (cu) -> () in
                data.append(cu)
            }
        }
        
        XCTAssertEqual(data.count, 9)
        
        var c = RawUTF8Codec<ArraySlice<UInt8>, ArraySlice<UInt8>.Generator>()
        
        var buff = String()
        
        func accumulate(slice: ArraySlice<UInt8>, line: UInt = __LINE__, file: String = __FILE__) -> Bool {
            do {
                let v = try c.code(ValueOrEnd.Value(slice))
                
                switch v {
                case .End:
                    return true
                case let .Value(v):
                    buff += v
                    return false
                }
            } catch let e {
                XCTFail("\(e)", line:line, file:file)
                return false
            }
        }
        
        XCTAssertFalse(accumulate(data[0..<2]))
        XCTAssertFalse(accumulate(data[2..<3]))
        XCTAssertFalse(accumulate(data[3..<8]))
        
        do {
            try c.code(.End)
            XCTFail("Should except")
        } catch {
        }
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

struct ChainedGenerator<L: GeneratorType, R: GeneratorType, T where L.Element == R.Element, T == L.Element>: GeneratorType {
    typealias Element = T
    
    var l: L
    var r: R
    
    var onfirst = true
    
    init(lhs: L, rhs: R) {
        l = lhs
        r = rhs
        
    }
    
    mutating func next() -> Element? {
        if onfirst {
            if let v = l.next() {
                return v
            } else {
                onfirst = false
            }
        }
        
        return r.next()
    }
}

func + <L: GeneratorType, R: GeneratorType, T where L.Element == R.Element, T == L.Element >(lhs: L, rhs: R) -> ChainedGenerator<L, R, T> {
    return ChainedGenerator(lhs: lhs, rhs: rhs)
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
