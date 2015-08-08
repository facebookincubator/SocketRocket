//
//  QueueStreamable.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/5/15.
//
//


public protocol AsyncBaseStream {
    /// The type we operate on
    typealias Collection: CollectionType
}

public protocol AsyncReadable : AsyncBaseStream {
    
    /// reads data until eof or size is reached. handler is invoked on the queue in order (and non-reentrant)
    /// 
    /// The return value of this indicates when the operation is done or if it failed
    mutating func read(size: Collection.Index.Distance, queue: Queue, handler: (AnyRandomAccessCollection<Collection.Generator.Element>) throws -> ()) -> VoidPromiseType
}

public protocol AsyncWritable : AsyncBaseStream {
    /// Writes data to the stream
    ///
    /// THe return value of this indicates when the operation is done or if it failed
    mutating func write<C: CollectionType where C.Generator.Element == Collection.Generator.Element>(data: C) -> VoidPromiseType
    
    /// Closes the stream
    mutating func close() -> VoidPromiseType

}

public extension AsyncReadable where Collection: RangeReplaceableCollectionType, Collection.Index.Distance == Int  {
    /// Buffers everything into one result
    mutating func readAll(size: Collection.Index.Distance = Collection.Index.Distance.max , queue: Queue) -> Promise<Collection> {
        var buffer = Collection()
        
        let vp = read(size, queue: queue) {  (v) -> () in
            buffer.extend(v)
        }
        
        let (r, p) = Promise<Collection>.resolver()
        
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
    typealias InType: CollectionType
    typealias OutType: CollectionType
    
    // TODO(lewis): Maybe make this take chunks more for input
    mutating func code(input: ValueOrEnd<AnyRandomAccessCollection<InType.Generator.Element>>) throws -> OutType
}

extension Codec where InType.Index : RandomAccessIndexType, InType: CollectionType {
    mutating func code(input: ValueOrEnd<InType>) throws -> OutType {
        switch input {
        case let .Value(v):
            let cc = AnyRandomAccessCollection<InType.Generator.Element>(v)
            return try self.code(ValueOrEnd<AnyRandomAccessCollection<InType.Generator.Element>>.Value(cc))
        case .End:
            return try self.code(ValueOrEnd<AnyRandomAccessCollection<InType.Generator.Element>>.End)
        }
    }
}

//
struct EncodedReadable<C: Codec,
                        R: AsyncReadable
                    where R.Collection == C.InType,
                        C.InType.Index.Distance == C.OutType.Index.Distance,
                C.OutType.Index: RandomAccessIndexType
>: AsyncReadable {
    typealias Collection = C.OutType
    
    private var input: R
    private var codec: C
    
    mutating func read(size: Collection.Index.Distance, queue: Queue, handler: (AnyRandomAccessCollection<Collection.Generator.Element>) throws -> ()) -> VoidPromiseType {
        return input.read(size, queue: queue) { (e) -> () in
            let coded = try self.codec.code(ValueOrEnd.Value(e))
            try handler(AnyRandomAccessCollection(coded))
        }.thenChecked { (vo: ErrorOptional<Void>) -> Void  in
            try handler(AnyRandomAccessCollection(self.codec.code(.End)))
            try vo.checkedGet()
        }
    }
}
//
//extension AsyncReadable {
//    func encode<C: Codec where C.InType == Collection>(codec: C) -> EncodedReadable<C, Self> {
//        return EncodedReadable(input: self, codec: codec)
//    }
//}



/// For testing
/// Probably not super efficient
public class Loopback<T: RangeReplaceableCollectionType
        where
            T.Index: RandomAccessIndexType,
            T.Index.Distance == Int,
            T.SubSequence.Generator.Element == T.Generator.Element,
            T.SubSequence.Index : RandomAccessIndexType,
            T.SubSequence: CollectionType
> : AsyncReadable, AsyncWritable {
    public typealias Collection = T
    public typealias ResultPromise = VoidPromiseType
    public typealias Handler = (AnyRandomAccessCollection<T.Generator.Element>) throws -> ()
    
    public typealias Distance = Collection.Index.Distance
    
    let queue: Queue
    
    var closed = false
    
    var buffer = Collection()
    
    var neededPromsises = [(size: Distance, resolver: Resolver<Void>, handler: Handler)]()
    
    public init(queue: Queue) {
        self.queue = queue
    }
    
    public func read(size: Collection.Index.Distance, queue: Queue, handler: (AnyRandomAccessCollection<Collection.Generator.Element>) throws -> ()) -> VoidPromiseType {
        let (r, p) = VoidPromiseType.resolver()
        
        queue.dispatchAsync {
            self.neededPromsises.append((size: size, resolver: r, handler: handler))
            self.produce()
        }

        return p
    }
    
    public func write<C: CollectionType where C.Generator.Element == Collection.Generator.Element>(data: C) -> VoidPromiseType {
        let (r, p) = VoidPromiseType.resolver()
        
        let data = Collection() + data
        queue.dispatchAsync {
            precondition(!self.closed)
            self.buffer.extend(data)
            r.resolve()
            self.queue.dispatchAsync {
                self.produce()
            }
        }
 
        return p
    }
    
    func produce() {
        do {
            while neededPromsises.count > 0 && buffer.count > 0 {
                let (size, resolver, handler) = neededPromsises[0]
                
                let numBytes = min(size, buffer.count)
                
                let newSize = size - numBytes
                
                let usedRange = buffer.startIndex..<buffer.startIndex.advancedBy(numBytes)
                let slice = buffer[usedRange]
                let newC = AnyRandomAccessCollection<T.SubSequence.Generator.Element>(slice)
                precondition(slice.count > 0)
                precondition(newC.count > 0)
                try handler(newC)
                
                buffer.replaceRange(usedRange, with: Collection())
                
                if newSize == 0 {
                    resolver.resolve()
                    neededPromsises.removeAtIndex(0)
                } else {
                    neededPromsises[0] = (newSize, resolver, handler)
                }
            }
            
            if closed && buffer.isEmpty {
                for p in self.neededPromsises {
                    p.resolver.resolve()
                }
                self.neededPromsises.removeAll()
            }
        } catch let e {
            for p in self.neededPromsises {
                p.resolver.reject(e)
            }
            self.neededPromsises.removeAll()
        }
    }
    
    public func close() -> ResultPromise {
        let (r, p) = VoidPromiseType.resolver()

        queue.dispatchAsync {
            self.closed = true
            self.produce()
            r.resolve()
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
