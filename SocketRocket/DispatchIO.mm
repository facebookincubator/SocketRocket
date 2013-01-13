//
//  DispatchChannel.cpp
//  SocketRocket
//
//  Created by Michael Lewis on 1/12/13.
//
//

#include "DispatchIO.h"
#include <Block.h>
#include <string>

extern "C" {
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <errno.h>
}

// TODO: add deadlines
namespace squareup {
    namespace dispatch {
        
        class Connector;
        
        typedef void(^finish_callback)(Connector *connector, addrinfo *res0, dispatch_fd_t fd, int error_code, const char *error_message);
        
        class Connector {
            addrinfo *_res;
            addrinfo *_res0;
            __strong finish_callback _finishCallback;
            dispatch_queue_t _workQueue;
            int _lastError;
            const char *_lastErrorMessage;
            
        public:
            // Takes ownership of res0;
            inline Connector(dispatch_queue_t workQueue, struct addrinfo *res0, finish_callback finishCallback) : _res(res0), _res0(res0), _finishCallback([finishCallback copy]), _workQueue(workQueue) {
                dispatch_retain(_workQueue);
            }
            
            virtual ~Connector() {
                dispatch_release(_workQueue);
            }
            
            inline void NextIter() {
                _res = _res->ai_next;
                dispatch_async(_workQueue, ^{
                    DoNext();
                });
            }
            
            inline void DoNext() {
                // We ran out of addresses
                if (!_res) {
                    _finishCallback(this, _res0, -1, _lastError, _lastErrorMessage);
                    return;
                }
                
                dispatch_fd_t fd = socket(_res->ai_family, _res->ai_socktype,
                                          _res->ai_protocol);
                
                if (fd < 0) {
                    _lastError = errno;
                    _lastErrorMessage = strerror(_lastError);
                    NextIter();
                    return;
                }
                
                int curflags = fcntl(fd, F_GETFL);
                if (curflags < 0) {
                    _lastError = errno;
                    _lastErrorMessage = strerror(_lastError);
                    NextIter();
                    return;
                }
                
                // Set it to be nonblocking
                int error = fcntl(fd, F_SETFL, curflags | O_NONBLOCK);
                if (error) {
                    _lastError = errno;
                    _lastErrorMessage = strerror(_lastError);
                    NextIter();
                    return;
                }
                
                dispatch_source_t readSource = nullptr;
                
                readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, fd, 0, _workQueue);
                
                dispatch_resume(readSource);
                
                dispatch_source_set_event_handler(readSource, [this, fd, readSource]{
                    TryConnect(false, fd, readSource);
                });
                
                dispatch_source_set_cancel_handler(readSource, [fd]{
                    close(fd);
                });
                
                TryConnect(true, fd, readSource);
            }
            
        private:
            // returns true if it is done
            // if this is the first try we call connect.  otherwise we check the status
            inline void TryConnect(bool firstTry, dispatch_fd_t fd, dispatch_source_t readSource) {
                // Now, set connection to be non-blocking
                assert(fd != -1);
                
                _lastError = 0;
                if (firstTry) {
                    int error = connect(fd, _res->ai_addr, _res->ai_addrlen);
                    if (error != 0) {
                        _lastError = errno;
                    }
                } else {
                    socklen_t len = sizeof(_lastError);
                    int sockErr = getsockopt(fd, SOL_SOCKET, SO_ERROR, &_lastError, &len);
                    assert(sockErr == 0);
                }
                
                if (_lastError != 0) {
                    if (_lastError != EINPROGRESS) {
                        _lastErrorMessage = strerror(_lastError);
                        dispatch_source_cancel(readSource);
                        dispatch_release(readSource);
                        readSource = nullptr;
                        NextIter();
                    }
                    return;
                }
                
                // Successful connections get here.  Then we don't try anymore
                
                // If we get this far, we're done
                dispatch_async(_workQueue, [this, readSource, fd]{
                    _finishCallback(this, _res0, fd, 0, nullptr);
                    
                    // Dispose of it without canceling it
                    dispatch_release(readSource);
                });
                
                return;
            }
        };
        
        void Dial(dispatch_queue_t workQueue, const char *hostname, const char *servname, dispatch_queue_t callback_queue, dial_callback callback) {
            callback = [callback copy];
            dispatch_retain(callback_queue);
            
            // Does cleanup and whatnot
            dispatch_async(workQueue, ^{
                addrinfo *res0 = nullptr;
                int error;
                const char *cause = nullptr;
                
                struct addrinfo hints = {0};
                hints.ai_family = PF_UNSPEC;
                hints.ai_socktype = SOCK_STREAM;
                
                error = getaddrinfo(hostname, servname, &hints, &res0);
                
                auto finish = [callback_queue, callback, workQueue](Connector *connector, addrinfo *res0, dispatch_fd_t fd, int error_code, const char *error_message){
                    dispatch_async(callback_queue, [=]{
                        callback(fd, error_code, error_message);
                        
                        if (res0) {
                            freeaddrinfo(res0);
                        }
                                                
                        if (connector) {
                            // Delete it after it doesn't reference this block anymore
                            dispatch_async(callback_queue, [workQueue, connector, callback_queue]{
                                delete connector;
                                dispatch_release(callback_queue);
                            });
                        } else {
                            dispatch_release(callback_queue);
                        }
                    });
                };
                
                if (error) {
                    cause = gai_strerror(error);
                    finish(nullptr, res0, -1, error, cause);
                    return;
                }
                
                Connector *connector = new Connector(workQueue, res0, finish);
                connector->DoNext();
            });
        }
        
        
        // callback_queue is what is sent to the clients but also
        // parent_io_queue can be a parallel queue. the
        void SimpleDial(const char *hostname, const char *servname, dispatch_queue_t callback_queue, dispatch_queue_t parent_io_queue, simple_dial_callback dial_callback, void (^close_handler)(int error)) {
            dispatch_queue_t io_queue = dispatch_queue_create("squareup.dispatch.SimpleDial IO Queue", DISPATCH_QUEUE_SERIAL);
            dispatch_set_target_queue(io_queue, parent_io_queue);
            
            dispatch_retain(callback_queue);
            close_handler = [close_handler copy];
            
            Dial(callback_queue, hostname, servname, callback_queue, [=](dispatch_fd_t fd, int error_code, const char *error_message) {
                RawIO *io = nullptr;
                
                if (error_code == 0) {
                    // Going to make the writer the primary.
                    // The write stream is also appropriate for closing
                    io = new RawIO(fd, callback_queue, callback_queue, io_queue, [fd, close_handler](int error) {
                        close(fd);
                        close_handler(error);
                    });
                }
                
                dial_callback(io, error_code, error_message);
                
                dispatch_release(io_queue);
                dispatch_release(parent_io_queue);
            });
        }
        
        void RawIO::Close(dispatch_io_close_flags_t flags) {
            dispatch_io_close(_channel, flags);
        }
        
        void RawIO::Read(size_t length, dispatch_io_handler_t handler) {
            dispatch_io_read(_channel, 0, length, _callbackQueue, handler);
        }
        
        void RawIO::Write(dispatch_data_t data, dispatch_io_handler_t handler)  {
            dispatch_io_write(_channel, 0, data, _callbackQueue, handler);
        }
        
        void RawIO::Barrier(dispatch_block_t barrier) {
            dispatch_io_barrier(_channel, barrier);
        }
    }
}
