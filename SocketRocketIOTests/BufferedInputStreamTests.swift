//
//  BufferedInputStreamTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 1/6/16.
//
//

import Foundation
import XCTest
@testable import SocketRocketIO

class BufferedInputStreamTests: XCTestCase {
    
    func testReadSize() {
        let loopback = LoopbackStream<UInt8>()
        
        let bufferedInput = BufferedInputStream(stream: loopback)
        
        loopback.write(Array("abcdefg".utf8))
        
        let val = bufferedInput
            .read(3)
            .map(Array.init)
            .subscribeFuture(self)
            .get()
            .flatMap { $0 }
        
        XCTAssertEqual(val, Array("abc".utf8))
        
        let future2 = bufferedInput
            .read(10)
            .map(Array.init)
            .subscribeFuture(self)
        
        loopback.write(Array("hij".utf8))
        loopback.close()
        
        let val2 = future2.get()
            .flatMap { $0 }
        XCTAssertEqual(val2, Array("defghij".utf8))
        
    }
    func testReadUTF8() {
        let loopback = LoopbackStream<UInt8>()
        
        let bufferedInput = BufferedInputStream(stream: loopback)
        
        loopback.write(Array("abcdefg".utf8))
        
        let val = bufferedInput
            .read(3)
            .encode(RawUTF8Codec.init)
            .subscribeFuture(self)
            .get()
            .flatMap { $0 }
        
        var str = ""
        str.unicodeScalars.appendContentsOf(val)
        XCTAssertEqual(str, "abc")
    }
    
    func testSplitterCRLF() {
        var buf = [UInt8]("omg\r\na b c d e\r\n".utf8)
        var (len, finished) = buf.withUnsafeBufferPointer { try! crlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 5)
        XCTAssertTrue(finished)
        
        buf = [UInt8]("omgomg\r".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 6)
        XCTAssertFalse(finished)
        
        buf = [UInt8]("\r".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 0)
        XCTAssertFalse(finished)
    }
    
    func testSplitterCRLFcRLF() {
        var buf = [UInt8]("omg\r\na b c d e\r\n\r\n".utf8)
        var (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, buf.count)
        XCTAssertTrue(finished)
        
        buf = [UInt8]("\r\n\r\n".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, buf.count)
        XCTAssertTrue(finished)
        
        buf = [UInt8]("omgomg\r".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 6)
        XCTAssertFalse(finished)
        
        buf = [UInt8]("\r".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 0)
        XCTAssertFalse(finished)
        
        buf = [UInt8]("aaa".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 3)
        XCTAssertFalse(finished)
        
        buf = [UInt8]("aaaa".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 4)
        XCTAssertFalse(finished)
        
        buf = [UInt8]("aaaa\r".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 4)
        XCTAssertFalse(finished)
        
        buf = [UInt8]("aaaa\r\n".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 4)
        XCTAssertFalse(finished)
        
        buf = [UInt8]("aaaa\r\n\r".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 4)
        XCTAssertFalse(finished)
        
        buf = [UInt8]("".utf8)
        (len, finished) = buf.withUnsafeBufferPointer { try! crlfCrlfSplitFunc(currentBuffer: $0, atEnd: true) }
        XCTAssertEqual(len, 0)
        XCTAssertFalse(finished)
    }
}