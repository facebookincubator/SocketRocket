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



/// A resolver that can produce data many times. It should eventually be terminated by calling .end or 
/// Production/fulfilling on this must be called on the same queue.
struct PromiseSreamResolver<T> {
    typealias PT = Promise<MoreOrEnd<T>>
    typealias PV = PT.ValueType
    typealias ET = ErrorOptional<PV>

    var resolver: Resolver<PV>!
    
    /// Rejects the current promise and sets it to nil. one should not produce after this
    mutating func reject(error: ErrorType) {
        resolver.reject(error)
        resolver = nil
    }
    
    /// Called to end the stream
    mutating func end() {
        resolver.resolve(.End)
        resolver = nil
    }

    /// Similar to resolve in a normal resolver, but resolves the underlying resolver, and creates a new promise
    mutating func produce(value: T) {
        let (r, p) = PT.resolver()
        resolver.resolve(.More((value, p)))
        resolver = r
    }
}

func streamingResolver<T>(_: T.Type = T.self) -> (PromiseSreamResolver<T>, Promise<MoreOrEnd<T>>) {
    let p = Promise<MoreOrEnd<T>>()
    let r = Resolver(promise: p)
    let sr = PromiseSreamResolver(resolver: r)
    return (sr, p)
}

public protocol ChunkedReader {
    
    /// This is the type of chunks we get back from the stream
    typealias ChunkType
    
    /// The owner of this object can use this to listen for the operation finishing
    /// This will either error or not error
    /// Note: This can be called on any thread. use .then with a queue to dispatch it on your queue
    var completed: VoidPromiseType  { get }
    
    /// Promises return chunks until size is reached. Never returns more than size total of chunks
    func read(size: Int, queue: Queue) -> Promise<MoreOrEnd<ChunkType>>
}

typealias dispatch_io_type_t = UInt

extension Queue {
    static let defaultCleanupQueue = Queue.defaultGlobalQueue
}

public struct IOReaderWrapper: ChunkedReader {
    public let io: dispatch_io_t
    
    public typealias ChunkType = dispatch_data_t
    
    public let completed: VoidPromiseType
    
    public typealias StreamPromise = Promise<MoreOrEnd<ChunkType>>
    typealias SP = Promise<MoreOrEnd<ChunkType>>
    
    /// Makes a reader from a root IO
    /// :param readqueue: this is the queue all reads are performed on
    init(baseIO: dispatch_io_t) {
        let (resolver, completed) = VoidPromiseType.resolver()
        self.completed = completed
        io = dispatch_io_create_with_io(DISPATCH_IO_STREAM, baseIO, Queue.defaultCleanupQueue.queue) { code in
            resolver.attemptResolve {
                try Error.throwIfNotSuccess(code)
            }
        }
    }

    public func read(size: Int, queue: Queue) -> StreamPromise {
        var (r, p) = streamingResolver(ChunkType.self)
        
        dispatch_io_read(io, 0, size, queue.queue) { finished, data, error in
            guard error == 0 else {
                r.reject(Error.errorFromStatusCode(error)!)
                return
            }
            
            if !data.empty {
                r.produce(data)
            }
            
            if finished {
                r.end()
            }
        }
        
        return p
    }
}
//extension dispatch_io {
//    
//}