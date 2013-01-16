//
//  DispatchChannel.h
//  SocketRocket
//
//  Created by Michael Lewis on 1/12/13.
//
//

#ifndef __SocketRocket__DispatchChannel__
#define __SocketRocket__DispatchChannel__

#include <dispatch/dispatch.h>

#include <string>

extern "C" {
#include <netdb.h>
}

namespace squareup {
    namespace dispatch {
        class RawIO;

        
        typedef void (^dial_callback)(dispatch_fd_t fd, int error_code, const char *error_message);
        
        void Dial(dispatch_queue_t workQueue, const char *hostname, const char *servname, dispatch_queue_t callback_queue, dial_callback callback);
        
        // You are responsible for removing inputStream and outputStream
        typedef void (^simple_dial_callback)(RawIO *io, int error, const char *error_message);
        
        // callback_queue is what is sent to the clients but also
        // parent_io_queue can be a parallel queue. the
        // close_handler is passed to the RawIO
        void SimpleDial(const char *hostname, const char *servname, dispatch_queue_t callback_queue, dispatch_queue_t parent_io_queue, simple_dial_callback dial_callback, void(^close_handler)(int error) = nullptr);
        
        class IO {
        public:
            virtual void Close(dispatch_io_close_flags_t flags) = 0;
            virtual void Read(size_t length, dispatch_io_handler_t handler) = 0;
            virtual void Write(dispatch_data_t data, dispatch_io_handler_t handler) = 0;
            virtual void Barrier(dispatch_block_t barrier) = 0;
            
            
            virtual void SetHighWater(size_t high_water) = 0;
            virtual void SetLowWater(size_t low_water) = 0;
            
            virtual ~IO();
        };
        
        class RawIO : public IO {
            dispatch_io_t _channel;
            dispatch_queue_t _callbackQueue;
        public:
            
            void Close(dispatch_io_close_flags_t flags);
            void Read(size_t length, dispatch_io_handler_t handler);
            void Write(dispatch_data_t data, dispatch_io_handler_t handler);
            void Barrier(dispatch_block_t barrier);
            
            void SetHighWater(size_t high_water);
            void SetLowWater(size_t low_water);
            
            RawIO(dispatch_fd_t fd,
                  dispatch_queue_t cleanupQueue,
                  dispatch_queue_t callbackQueue,
                  dispatch_queue_t ioQueue,
                  void (^cleanup_handler)(int error));
            
            // Takes ownership of channel
            // retain is only for the channel
            RawIO(dispatch_io_t channel,
                  dispatch_queue_t callbackQueue,
                  bool retain = true);
            
            // Clones an existing IO
            RawIO(dispatch_io_t otherIo,
                  dispatch_queue_t queue,
                  dispatch_queue_t callbackQueue,
                  dispatch_queue_t ioQueue,
                  void (^cleanup_handler)(int error));
            
            inline operator dispatch_io_t () const {
                return _channel;
            }
            
            virtual ~RawIO();
        };
    }
}

#endif /* defined(__SocketRocket__DispatchChannel__) */
