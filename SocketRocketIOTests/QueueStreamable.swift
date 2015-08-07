//
//  QueueStreamable.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/5/15.
//
//


/// These are basically promises that won't terminate until they hit the end
public enum MoreOrEnd<T> {
    public typealias ValueTuple = (T, Promise<MoreOrEnd<T>>)
    indirect case More(ValueTuple)
    case End
}




protocol AsyncBaseStream {
    /// The type we operate on
    typealias Element
    
    /// Reads and writes return this value. This promise indicates
    /// that the operation completed
    ///
    /// One should call then on the handler to make sure it terminates
    typealias ResultPromise = VoidPromiseType
}

protocol AsyncReadable : AsyncBaseStream {
    typealias Handler = (Element) -> ()
    
    /// reads data until eof or size is reached. handler is invoked on the queue in order (and non-reentrant)
    /// 
    /// The return value of this indicates when the operation is done or if it failed
    mutating func read(size: Int, queue: Queue, handler: Handler) -> ResultPromise
}

protocol AsyncWritable : AsyncBaseStream {
    /// Writes data to the stream
    ///
    /// THe return value of this indicates when the operation is done or if it failed
    func write(data: Element) -> ResultPromise
}


/// Wraps an io since it is a protocol
struct DispatchIO {
    let io: dispatch_io_t
}


enum ValueOrEnd<V> {
    /// :param consumed: the size of the input stream consumed
    /// :param value: result value for the coded
    case Value(V)
    
    /// If we're out of data
    case End
}

protocol Codec {
    typealias InType
    typealias OutType
    
    // TODO(lewis): Maybe make this take chunks more for input
    mutating func code(input: ValueOrEnd<InType>) throws -> ValueOrEnd<OutType>
}


struct EncodedReadable<C: Codec, R: AsyncReadable where R.Element == C.InType>: AsyncReadable {
    typealias Element = C.OutType
    typealias Handler = (Element) -> ()
    
    private let input: R
    private var codec: C
    
    func read(size: Int, queue: Queue, handler: Handler) -> VoidPromiseType {
        return VoidPromiseType.reject(POSIXError.ENOENT)
    }
}

extension AsyncReadable {
    func encode<C: Codec where C.InType == Element>(codec: C) -> EncodedReadable<C, Self> {
        return EncodedReadable(input: self, codec: codec)
    }
}

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
    typealias OutType = String
    
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


    mutating func code(input: ValueOrEnd<InType>) throws -> ValueOrEnd<OutType> {
        defer {
            outputBuffer.removeAll(keepCapacity: true)
        }
        
        switch input {
        case .End:
            if inputBuffer.isEmpty {
                return .End
            } else {
                throw Error.UTF8DecodeError
            }
        case let .Value(v):
            let totalSize = inputBuffer.count + v.count
            
            outputBuffer.reserveCapacity(totalSize)
            
            let g = inputBuffer.generate() + v.generate()
            
            let numValidCodeUnits = try UTF8.numValidCodeUnits(g)

            let numUnfinished = totalSize - numValidCodeUnits
            
            
            // If this happens, we didn't get enough for even one character
            if numUnfinished == totalSize {
                inputBuffer += v
                return ValueOrEnd.Value("")
            }
            
            if numUnfinished > 0 {
                let truncatedG = v[v.startIndex..<v.endIndex.advancedBy(-numUnfinished)].generate()
                let g = inputBuffer.generate() + truncatedG
                
                try consume(g)
            } else {
                try consume(g)
            }
            
            inputBuffer.removeAll(keepCapacity: true)
            if numUnfinished > 0 {
                inputBuffer += v[v.endIndex.advancedBy(-numUnfinished)..<v.endIndex]
            }

            
            return .Value(outputBuffer)
        }
    }
}

extension DispatchIO: AsyncReadable {
    typealias Element = UnsafeBufferPointer<UInt8>
    
    func read(size: Int, queue: Queue, handler: (Element) -> ()) -> VoidPromiseType {
        let (r, p) = VoidPromiseType.resolver()
        
        dispatch_io_read(io, 0, size, queue.queue) { finished, data, error in
            guard error == 0 else {
                r.reject(Error.errorFromStatusCode(error)!)
                return
            }
            
            data.apply { d in
                handler(d)
            }
            
            if finished {
                r.resolve(Void())
            }
        }

        return p
    }
}

//struct Coder<InType, OutType> {
//}

extension Queue {
    static let defaultCleanupQueue = Queue.defaultGlobalQueue
}

//public struct IOReaderWrapper: AsyncReadable {
//    public let io: dispatch_io_t
//    
//    public typealias ChunkType = dispatch_data_t
//    
//    public let completed: VoidPromiseType
//    
//    public typealias StreamPromise = Promise<MoreOrEnd<ChunkType>>
//    typealias SP = Promise<MoreOrEnd<ChunkType>>
//    
//    /// Makes a reader from a root IO
//    /// :param readqueue: this is the queue all reads are performed on
//    init(baseIO: dispatch_io_t) {
//        let (resolver, completed) = VoidPromiseType.resolver()
//        self.completed = completed
//        io = dispatch_io_create_with_io(DISPATCH_IO_STREAM, baseIO, Queue.defaultCleanupQueue.queue) { code in
//            resolver.attemptResolve {
//                try Error.throwIfNotSuccess(code)
//            }
//        }
//    }
//
//    public func read(size: Int, queue: Queue) -> StreamPromise {
//        var (r, p) = streamingResolver(ChunkType.self)
//        
//        dispatch_io_read(io, 0, size, queue.queue) { finished, data, error in
//            guard error == 0 else {
//                r.reject(Error.errorFromStatusCode(error)!)
//                return
//            }
//            
//            if !data.empty {
//                r.produce(data)
//            }
//            
//            if finished {
//                r.end()
//            }
//        }
//        
//        return p
//    }
//}
//extension dispatch_io {
//    
//}

struct ChainedGenerator<L: GeneratorType, R: GeneratorType, T where L.Element == R.Element, T == L.Element>: GeneratorType, SequenceType {
    typealias Element = T
    
    typealias Generator = ChainedGenerator<L, R, T>
    
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
