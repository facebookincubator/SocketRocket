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
                    if g.next() == nil {
                        break outOfCharacters
                    }
                }
                numValidCodeUnits += numCodeUnits
        }
        
        return numValidCodeUnits
    }
}


struct RawUTF8Codec<CT: CollectionType, GT: GeneratorType where CT.Generator == GT, GT.Element == UInt8, CT.Index.Distance == Int, CT.Index: RandomAccessIndexType, CT.Generator.Element == UInt8, CT.SubSequence.Generator.Element == UInt8> : Codec {
    typealias InType = CT
    typealias OutType = String.UnicodeScalarView
    
    typealias CodeUnit = UInt8
    
    typealias UnicodeCodec = UTF8
    
    
    var outputBuffer = String()
    
    /// Used to buffer unfinished UTF8 Sequences
    var inputBuffer = [CodeUnit]()
    
    /// Consumes to our outputbuffer
    mutating func consume<G: GeneratorType where G.Element == CodeUnit>(var g: G) throws  {
        var uc = UTF8()
        
        while true {
            switch uc.decode(&g) {
            case .EmptyInput:
                return
            case .Error:
                throw Error.UTF8DecodeError
            case let .Result(scalar):
                outputBuffer.append(scalar)
            }
        }
    }
    
    
    mutating func code(input: ValueOrEnd<AnyRandomAccessCollection<InType.Generator.Element>>) throws -> OutType {
        defer {
            outputBuffer.removeAll(keepCapacity: true)
        }
        
        switch input {
        case .End:
            if inputBuffer.isEmpty {
                return "".unicodeScalars
            } else {
                throw Error.UTF8DecodeError
            }
        case let .Value(v):
            let totalSize = inputBuffer.count + v.count
            
            outputBuffer.reserveCapacity(Int(totalSize))
            
            let numValidCodeUnits = try UTF8.numValidCodeUnits(inputBuffer.generate() + v.generate())
            
            let numUnfinished = totalSize - numValidCodeUnits
            
            
            // If this happens, we didn't get enough for even one character
            if numUnfinished == totalSize {
                inputBuffer += v
                return "".unicodeScalars
            }
            
            if numUnfinished > 0 {
                let truncatedG = v[v.startIndex..<v.endIndex.advancedBy(-numUnfinished)].generate()
                let g = inputBuffer.generate() + truncatedG
                
                try consume(g)
            } else {
                try consume(inputBuffer.generate() + v.generate())
            }
            
            inputBuffer.removeAll(keepCapacity: true)
            if numUnfinished > 0 {
                inputBuffer += v[v.endIndex.advancedBy(-numUnfinished)..<v.endIndex]
            }
            
            return outputBuffer.unicodeScalars
        }
    }
}

extension DispatchIO: AsyncReadable {
    typealias Collection = UnsafeBufferPointer<UInt8>
    
    func read(size: Collection.Index.Distance, queue: Queue, handler: (AnyRandomAccessCollection<Collection.Generator.Element>) throws -> ()) -> VoidPromiseType {
        let (r, p) = VoidPromiseType.resolver()
        
        dispatch_io_read(io, 0, size, queue.queue) { finished, data, error in
            guard error == 0 else {
                r.reject(Error.errorFromStatusCode(error)!)
                return
            }
            
            do {
                try data.apply { d in
                    try handler(AnyRandomAccessCollection(d))
                }
            } catch let e {
                // TODO(don't double-call this error)
                r.reject(e)
                return
            }
            
            if finished {
                r.resolve(Void())
            }
        }
        
        return p
    }
}

