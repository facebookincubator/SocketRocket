//
//  SecureIO.h
//  SocketRocket
//
//  Created by Michael Lewis on 1/12/13.
//
//

#ifndef __SocketRocket__SecureIO__
#define __SocketRocket__SecureIO__

#include "DispatchIO.h"
#include "DispatchData.h"

#include <deque>
#include <vector>

struct SSLContext;

namespace squareup {
   namespace dispatch {
       class SecureIO;
       
       // You are responsible for removing inputStream and outputStream
       typedef void (^dial_tls_callback)(SecureIO *io, int error, const char *error_message);
       
       void DialTLS(const char *hostname, const char *servname, SSLContextRef ssl_context, dispatch_queue_t callback_queue, dispatch_queue_t work_queue, dispatch_queue_t parent_io_queue, dial_tls_callback dial_callback, void(^close_handler)(int error) = nullptr);
       
       
       template <typename FuncType>
       class QueuedHandle {
       private:
           __strong FuncType _handler = nullptr;
           __sr_maybe_strong__ dispatch_queue_t _queue = nullptr;
       public:
           inline QueuedHandle() {
           }
           
           inline QueuedHandle(dispatch_queue_t queue, FuncType handler) {
               _handler = [handler copy];
               _queue = queue;
               sr_dispatch_retain(_queue);
           }
           
           inline QueuedHandle(const QueuedHandle<FuncType> &other) : QueuedHandle(other._queue, other._handler){
           }
           
           
           inline QueuedHandle &operator=(const QueuedHandle &other){
               _handler = other._handler;
               _queue = other._queue;
               sr_dispatch_release(_queue);
               return *this;
           }
           
           inline ~QueuedHandle() {
               if (_queue) {
                   sr_dispatch_release(_queue);
               }
           }
           
           inline bool Valid() const {
               return _handler != nullptr;
           }
           
           inline void Invalidate() {
               _handler = nullptr;
           }
           
           template<typename... Args>
           void operator () (Args... args) const {
               assert(Valid());
               FuncType handler = _handler;
               dispatch_async(_queue, [handler, args...]{
                   handler(args...);
               });
           }
       };
       
       typedef QueuedHandle<dispatch_io_handler_t> DispatchHandler;
       
       struct WriteJob {
           bool isLast;
           size_t rawBytes = 0;
           size_t cryptedBytes = 0;
           DispatchHandler handler;
       };
       
       struct ReadRequest {
           // How many rawBytes we're expecting to read.
           // This is populated in SSLRead.
           size_t rawBytesRemaining = 0;
    
           DispatchHandler handler;
       };

       class SecureIO : public IO {
           IO *_io;
           SSLContext *_context;
           dispatch_queue_t _workQueue;
           
           std::deque<WriteJob> _writeJobs;
           std::deque<ReadRequest> _readRequests;
           
           Data _waitingCryptedData;
           size_t _cryptedBytesRequested = 0;
           size_t _rawBytesRequested = 0;
           
           size_t _highWater = SIZE_MAX;
           size_t _lowWater = 1024 * 8;
           
           bool _cancelled = false;
           bool _closing = false;
           
           // Set when we're inside of HandleSSLRead
           // If we're reading and get a call to our SSLWriteHandler, the connection is probably being closed
           bool _handlingRead = false;
           
           // presence of this means handshake is in progress
           DispatchHandler _handshakeHandler;
           
           // This is set to true when we send a NULL data ptr.  This is so we can request data we need.
           bool _calculatingRequestSize = false;
           
           std::vector<uint8_t> _sslReadBuffer;
           
       public:
           // Takes ownership of IO and delete it when done
           SecureIO(IO *io, SSLContextRef context, dispatch_queue_t workQueue);
           ~SecureIO();
           
           // This performs the handshake.
           // There will be no data sent back to handler, but it will be called on completion
           void Handshake(dispatch_queue_t queue, dispatch_io_handler_t handler);
           
           void Close(dispatch_io_close_flags_t flags);
           void Read(size_t length, dispatch_queue_t queue, dispatch_io_handler_t handler);
           void Write(dispatch_data_t data, dispatch_queue_t queue, dispatch_io_handler_t handler);
           void Barrier(dispatch_block_t barrier);
           

           inline void SetHighWater(size_t high_water) {
               _highWater = high_water;
           }
           
           void SetLowWater(size_t low_water) {
               _lowWater = low_water;
           }

       private:
           // Requests will ask the underlying stream for lenght - _rawBytesRequested 
           void RequestBytes(size_t length);
           
           void Cancel(dispatch_io_close_flags_t flags, int error);
           
           void CheckHandshake();
           void InnerWrite(dispatch_data_t data, const DispatchHandler &handler);

           // These really should be private
       public:
           OSStatus SSLReadHandler(void *data, size_t *dataLength);
           OSStatus SSLWriteHandler(const void *data, size_t *dataLength);
           
           
       private:
           void HandleSSLWrite(bool done, size_t requestedLength, int error);
           void HandleSSLRead(bool done, dispatch_data_t data, int error);
           
           void PumpSSLRead();
           void DoSSLRead();
           
       };
   }
}

#endif /* defined(__SocketRocket__SecureIO__) */
