//
//  Unicode.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/6/15.
//
//

extension UTF8 {
    /// Returns number of code units. Throws if its not the first bite of a unicode charactser
    /// result includes selve
    static func numCodeUnits(first: CodeUnit) throws -> Int {
        guard first & 0b1100_0000 != 0b1000_0000  else {
            throw Error.UTF8DecodeError
        }
        
        // If the first bit is 0, its a single code-point
        if first & 0b1000_0000 == 0b0000_0000 {
            return 1
        }
        
        if first & 0b1110_0000 == 0b1100_0000 {
            return 2
        }
        
        if first & 0b1111_0000 == 0b1110_0000 {
            return 3
        }
        
        if first & 0b1111_1000 == 0b1111_0000 {
            return 4
        }
        
        throw Error.UTF8DecodeError
    }
    
    /// Returns the number of valid codeunits from the generator
    static func numValidCodeUnits<G: GeneratorType where G.Element == CodeUnit>(var g: G) throws -> Int {
        var numValidCodeUnits = 0
        outOfCharacters:
            for var c = g.next(); c != nil; c = g.next() {
                let numCodeUnits = try UTF8.numCodeUnits(c!)
                for _ in 0..<(numCodeUnits - 1) {
                    if let c = g.next() {
                        guard UTF8.isContinuation(c) else {
                            throw Error.UTF8DecodeError
                        }
                    } else {
                        break outOfCharacters
                    }
                }
                numValidCodeUnits += numCodeUnits
        }
        
        return numValidCodeUnits
    }
}


struct RawUTF8Codec : Codec {
    typealias InputElement = CodeUnit
    typealias OutputElement = UnicodeScalar
    
    typealias CodeUnit = UInt8
    
    typealias UnicodeCodec = UTF8
    
    /// Used to buffer unfinished UTF8 Sequences
    var inputBuffer = [CodeUnit]()
    
    /// Consumes to our outputbuffer
    mutating func consume<I : GeneratorType, O : RangeReplaceableCollectionType where I.Element == InputElement, O.Generator.Element == OutputElement>(var g: I, inout output: O) throws  {
        var uc = UTF8()
        
        while true {
            switch uc.decode(&g) {
            case .EmptyInput:
                return
            case .Error:
                throw Error.UTF8DecodeError
            case let .Result(scalar):
                output.append(scalar)
            }
        }
    }
    
    
    mutating func code<I : CollectionType, O : RangeReplaceableCollectionType where I.Generator.Element == InputElement, O.Generator.Element == OutputElement, I.Index.Distance == Int>(input: ValueOrEnd<I>, inout output: O) throws {

        switch input {
        case .End:
            if !inputBuffer.isEmpty {
                throw Error.UTF8DecodeError
            }
        case let .Value(v):
            inputBuffer.appendContentsOf(v)

            let numValidCodeUnits = try UTF8.numValidCodeUnits(inputBuffer.generate())
            let slice = inputBuffer[0..<numValidCodeUnits]
            try consume(slice.generate(), output: &output)
            inputBuffer.removeFirst(numValidCodeUnits)
        }
    }
}
