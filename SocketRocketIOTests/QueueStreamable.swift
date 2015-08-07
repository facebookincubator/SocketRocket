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




public protocol AsyncBaseStream {
    /// The type we operate on
    typealias Element
    
    /// Reads and writes return this value. This promise indicates
    /// that the operation completed
    ///
    /// One should call then on the handler to make sure it terminates
    typealias ResultPromise: VoidPromiseType = VoidPromiseType
}

public protocol AsyncReadable : AsyncBaseStream {
    
    /// reads data until eof or size is reached. handler is invoked on the queue in order (and non-reentrant)
    /// 
    /// The return value of this indicates when the operation is done or if it failed
    mutating func read(size: Int, queue: Queue, handler: (Element) throws -> ()) -> VoidPromiseType
}

protocol AsyncWritable : AsyncBaseStream {
    /// Writes data to the stream
    ///
    /// THe return value of this indicates when the operation is done or if it failed
    mutating func write(data: Element) -> ResultPromise
    
    /// Closes the stream
    mutating func close() -> ResultPromise
}

public extension AsyncReadable where Element: RangeReplaceableCollectionType  {
    /// Buffers everything into one result
    mutating func readAll(size: Int, queue: Queue) -> Promise<Element> {
        var buffer = Element()
        
        let vp = read(size, queue: queue) {  (v: Element) -> () in
            buffer.extend(v)
        }
        
        let (r, p) = Promise<Element>.resolver()
        
        vp.then { (voidP: ErrorOptional<Void>) -> () in
            r.attemptResolve {
                try voidP.checkedGet()
                return buffer
            }
        }
        
        return p
    }
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
    mutating func code(input: ValueOrEnd<InType>) throws -> OutType
}


struct EncodedReadable<C: Codec, R: AsyncReadable where R.Element == C.InType>: AsyncReadable {
    typealias Element = C.OutType
    typealias Handler = (Element) throws -> ()
    
    private var input: R
    private var codec: C
    
    mutating func read(size: Int, queue: Queue, handler: Handler) -> VoidPromiseType {
        let otherP = input.read(size, queue: queue) { (e) -> () in
            try handler(self.codec.code(.Value(e)))
        }
        
        return otherP.thenChecked { (vo: ErrorOptional<Void>) -> Void  in
            try handler(self.codec.code(.End))
            try vo.checkedGet()
        }
    }
}

extension AsyncReadable {
    func encode<C: Codec where C.InType == Element>(codec: C) -> EncodedReadable<C, Self> {
        return EncodedReadable(input: self, codec: codec)
    }
}

/// For testing
/// Probably not super efficient
struct Loopback<T where T: RangeReplaceableCollectionType, T.Index.Distance == Int> : AsyncReadable, AsyncWritable {
    typealias Element = T
    typealias ResultPromise = VoidPromiseType
    typealias Handler = (Element) throws -> ()
    
    let queue: Queue
    
    var closed = false
    
    var buffer = Element()
    
    var neededPromsises = [(size: Int, resolver: Resolver<Void>, handler: Handler)]()
    
    mutating func read(size: Int, queue: Queue, handler: Handler) -> VoidPromiseType {
        let (r, p) = VoidPromiseType.resolver()
        
        queue.dispatchAsync {
            self.neededPromsises.append((size: size, resolver: r, handler: handler))
            self.produce()
        }

        return p
    }
    
    mutating func write(data: Element) -> ResultPromise {
        let (r, p) = VoidPromiseType.resolver()
        
        queue.dispatchAsync {
            precondition(!self.closed)
            self.buffer.extend(data)
            r.resolve()
            self.produce()
        }

        return p
    }
    
    mutating func produce() {
        while !neededPromsises.isEmpty && buffer.isEmpty {
            let (size, resolver, handler) = neededPromsises[0]
            
            let numBytes = min(size, buffer.count)
            
            let newSize = size - numBytes
            
            if newSize == 0 {
                resolver.resolve()
                neededPromsises.removeAtIndex(0)
            } else {
                neededPromsises[0] = (newSize, resolver, handler)
            }
        }
    }
    
    mutating func close() -> ResultPromise {
        let (r, p) = VoidPromiseType.resolver()

        queue.dispatchAsync {
            r.resolve()
            self.closed = true
        }
        
        return p
    }
}

extension Queue {
    static let defaultCleanupQueue = Queue.defaultGlobalQueue
}

/// Chains two generators together
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
