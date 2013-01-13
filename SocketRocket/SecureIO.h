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

struct SSLContext;

namespace squareup {
   namespace dispatch {
       class SecureIO : public IO {
           IO *_io;
           SSLContext *_context;
           dispatch_queue_t _workQueue;
           dispatch_queue_t _callbackQueue;
           
       public:
           SecureIO(IO *io, SSLContextRef context, dispatch_queue_t workQueue, dispatch_queue_t callbackQueue);
           ~SecureIO();
           
           void Close(dispatch_io_close_flags_t flags);
           void Read(size_t length, dispatch_io_handler_t handler);
           void Write(dispatch_data_t data, dispatch_io_handler_t handler);
           void Barrier(dispatch_block_t barrier);
           
           OSStatus SSLRead(void *data, size_t *dataLength) const;
           OSStatus SSLWrite(const void *data, size_t *dataLength) const;
       };
   }
}

#endif /* defined(__SocketRocket__SecureIO__) */
