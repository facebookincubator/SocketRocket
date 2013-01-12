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

namespace squareup {
namespace dispatch {
    class Channel {
        virtual void Read(size_t length, dispatch_io_handler_t handler, dispatch_queue_t queue) = 0;
        virtual void Write(size_t length, dispatch_data_t data, dispatch_io_handler_t handler, dispatch_queue_t queue) = 0;
        virtual void Close(dispatch_io_close_flags_t flags) = 0;
    };
    
    class RawChannel : Channel {
        dispatch_io_t _channel;
    public:
        inline RawChannel(dispatch_io_type_t type,
                          dispatch_fd_t fd,
                          dispatch_queue_t queue,
                          void (^cleanup_handler)(int error)) {
            _channel = dispatch_io_create(type, fd, queue, cleanup_handler);
        }
        
        // Takes ownership of channel
        inline RawChannel(dispatch_io_t channel) : _channel(channel) {
            dispatch_retain(_channel);
        };
        
        virtual ~RawChannel() {
            dispatch_release(_channel);
            _channel = nullptr;
        }
    };
}
}

#endif /* defined(__SocketRocket__DispatchChannel__) */
