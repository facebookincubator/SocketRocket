//
//  UnicodeTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/6/15.
//
//

import XCTest
@testable import SocketRocketIO

struct SourceInfo {
    let line: UInt
    let file: String
    
    init(line: UInt = __LINE__, file: String = __FILE__) {
        self.line = line
        self.file = file
    }
}

typealias SI = SourceInfo

class UnicodeTests: XCTestCase {
    func testCodeUnits() {
        let s  = "💩1💩"
        
        
        var data = [UInt8](s.utf8)
        
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
        
        var c = RawUTF8Codec()
        
        var buff = String()
        
        func accumulate(slice: ArraySlice<UInt8>, line: UInt = __LINE__, file: String = __FILE__) {
            do {
                let val = ValueOrEnd<ArraySlice<UInt8>>.Value(slice)
                try c.code(val, output: &buff.unicodeScalars)
            } catch let e {
                XCTFail("\(e)", line:line, file:file)
            }
        }
        
        accumulate(data[0..<2])
        accumulate(data[2..<3])
        accumulate(data[3..<8])
        accumulate(data[8..<9])
        
        do {
            try c.code(ValueOrEnd<ArraySlice<UInt8>>.End, output: &buff.unicodeScalars)
        } catch let e {
            XCTFail("\(e)")
        }
        
        XCTAssertEqual(buff, s)
    }
    
    
    func testDecoding_errorHandling() {
        var uc = UTF8()
        
        let s  = "💩1💩"
        
        var data = [UInt8](s.utf8)
        
        XCTAssertEqual(data.count, 9)
        
        var c = RawUTF8Codec()
        
        var buff = String()
        
        func accumulate(slice: ArraySlice<UInt8>, line: UInt = __LINE__, file: String = __FILE__) {
            do {
                let val = ValueOrEnd<ArraySlice<UInt8>>.Value(slice)
                try c.code(val, output: &buff.unicodeScalars)
            } catch let e {
                XCTFail("\(e)", line:line, file:file)
            }
        }
        
        accumulate(data[0..<2])
        accumulate(data[2..<3])
        accumulate(data[3..<8])
        
        do {
            try c.code(ValueOrEnd<ArraySlice<UInt8>>.End, output: &buff.unicodeScalars)
            XCTFail("Should except")
        } catch {
        }
    }
    
    func testDecoding_Smoke() {
        let filePath = NSBundle(forClass: UnicodeTests.self).pathForResource("UTF8Sample", ofType: "txt", inDirectory: "Fixtures")!
        let s = NSData(contentsOfFile: filePath)!
        
        let nominalString = NSString(data: s, encoding: NSUTF8StringEncoding) as! String
        
        doTestAccumulateSplit(nominalString, splitPoints: [Int](0..<(s.length - 1)))
        
        doTestAccumulateSplit(nominalString, splitPoints: [])
        doTestAccumulateSplit(nominalString, splitPoints: [Int](0..<((s.length - 1) / 2)).map({e in return e / 2}))
    }

    func doTestAccumulateSplit(data: [UInt8], var splitPoints: [Int], si: SI = SI()) -> String {
        var c = RawUTF8Codec()
        
        var buff = String()
        
        func accumulate(slice: ArraySlice<UInt8>, si: SI) {
            do {
                let val = ValueOrEnd<ArraySlice<UInt8>>.Value(slice)
                try c.code(val, output: &buff.unicodeScalars)
            } catch let e {
                XCTFail("\(e)")
                XCTFail("\(e) (from here)", line:si.line, file:si.file)
            }
        }
        
        splitPoints.sortInPlace()
        
        var lastIdx = data.startIndex
        
        for sp in splitPoints {
            let newIdx = data.startIndex.advancedBy(sp)
            accumulate(data[lastIdx..<newIdx], si: si)
            lastIdx = newIdx
        }
        accumulate(data[lastIdx..<data.endIndex], si: si)

        do {
            try c.code(ValueOrEnd<ArraySlice<UInt8>>.End, output: &buff.unicodeScalars)
        } catch let e {
            XCTFail("Should not except \(e)")
        }
        return buff
    }
    
    func doTestAccumulateSplit(string: String, splitPoints: [Int], si: SI = SI()) {
        var data = [UInt8]()
        for s in string.unicodeScalars {
            UTF8.encode(s) { (cu) -> () in
                data.append(cu)
            }
        }
        let r = doTestAccumulateSplit(data, splitPoints: splitPoints, si: si)
        XCTAssertEqual(string, r, line:si.line, file:si.file)
    }
}