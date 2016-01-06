//
//  QueueStreamableTests.swift
//  SocketRocket
//
//  Created by Mike Lewis on 8/6/15.
//
//

import XCTest
@testable import SocketRocketIO

/*

class QueueStreamableTests: XCTestCase {
    static let filePath = NSBundle(forClass: QueueStreamableTests.self).pathForResource("FileToReadFrom", ofType: "txt", inDirectory: "Fixtures")!

    func testManualAccumulating() {
        let io = dispatch_io_create_with_path(DISPATCH_IO_STREAM, QueueStreamableTests.filePath, O_RDONLY, 0, dispatch_queue_t.mainQueue.queue) { _ in }
        
        let streamer = DispatchIO(io: io)
        
        var accumulated = [UInt8]()
        
        let readQueue = dispatch_queue_t(label: "Read queue")
        
        let p = streamer.read(readQueue, size: Int.max) { data in
            accumulated += data
        }
        
        expectationWithPromise(p)
        
        dispatch_io_close(io, 0)
        
        let readData = String(bytes:accumulated, encoding: NSUTF8StringEncoding)
        
        XCTAssertEqual(readData!, "hello\nthis\nis a file\n\nI like to read from it")
    }
    
    func testErrorHandling() {
        let io = dispatch_io_create_with_path(DISPATCH_IO_STREAM, QueueStreamableTests.filePath, O_RDONLY, 0, dispatch_queue_t.mainQueue.queue) { _ in }
        
        let streamer = DispatchIO(io: io)
        
        let readQueue = dispatch_queue_t(label: "Read queue")
        
        dispatch_suspend(readQueue.queue)

        let f = streamer.read(readQueue, size: Int.max) { v in
            
        }

        dispatch_io_close(streamer.io, DISPATCH_IO_STOP)
        
        dispatch_resume(readQueue.queue)
        
        expectationWithFailingPromise(f)
    }
    
    func testLoopback() {
        let q = dispatch_queue_t(label: "loopbackQueue")
        
        let l = Loopback<[UInt8]>(queue: q)
        
        let p = l.readAll(q, collectionType: [UInt8].self).thenChecked { v in
            let v = try v.checkedGet()
            XCTAssertEqual(v, [UInt8]("OMG PONIESI LIKE TO EAT PONIES".utf8))
        }
        
        l.write(q, data: [UInt8]("OMG PONIES".utf8))
        l.write(q, data: [UInt8]("I LIKE TO EAT PONIES".utf8))
        
        expectationWithPromise(l.close(q), wait: false)
        
        expectationWithPromise(p)
    }
    
    func testIOReadableWriteable() {
        let acceptExpectation = expectationWithDescription("waiting")
        
        let s = try! Socket.boundListeningSocket(sockaddr_in6.self, address: .Loopback, port: 0)
        
        let q = dispatch_queue_t(label: "testIOReadableWriteable")
        
        let (listenR, listenP) = Promise<Socket>.resolver(q)
        
        let (cancelResolver, closedPromise) = s.startAccepting(dispatch_queue_t.mainQueue) {
            (sock) -> Void in
            listenR.resolve(sock)
            acceptExpectation.fulfill()
        }
        
        let connectAddr = try! s.sockname()
        
        let listenPort = connectAddr.port
        XCTAssertNotEqual(listenPort, 0)
        
        let clientIOPromise: Promise<Void> = Socket.tryConnect(q, sockAddr: connectAddr)
            .thenChecked { v -> DispatchIO in
                
                let sock = try v.checkedGet()
                let io = dispatch_io_create(DISPATCH_IO_STREAM, sock.fd, q.queue, { _ in try! sock.close() })
                
                return DispatchIO(io: io)
        }
            .thenSplit { io in
                io.write(q, data: [UInt8]("OMG PONIES".utf8))
                io.write(q, data: [UInt8]("I LIKE TO EAT PONIES".utf8))
                return .Promised(io.close(q))
        }
        
        
        var serverIO: DispatchIO! = nil
        
        let serverIOPromise: Promise<Void> = listenP
            .thenChecked { v -> DispatchIO in
                let sock = try v.checkedGet()
                let io = dispatch_io_create(DISPATCH_IO_STREAM, sock.fd, q.queue, { _ in try! sock.close() })
                return DispatchIO(io: io)
            }
            .thenSplit { io -> PromiseOrValue<[UInt8]> in
                serverIO = io
                return .Promised(io.readAll(q, collectionType: [UInt8].self))
            }
            .thenChecked { v in
                let v = try v.checkedGet()
                XCTAssertEqual(v, [UInt8]("OMG PONIESI LIKE TO EAT PONIES".utf8))
            }
            .thenSplit { v in
                return .Promised(serverIO.close(q))
        }
        

        self.expectationWithPromise(serverIOPromise, wait:false)
        self.expectationWithPromise(clientIOPromise, wait:false)
        
        waitForExpectations()
        
        cancelResolver.resolve()
        
        self.expectationWithPromise(closedPromise)
    }
}


*/
