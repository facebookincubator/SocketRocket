//
//  DispatchChannel.cpp
//  SocketRocket
//
//  Created by Michael Lewis on 1/12/13.
//
//

#include "DispatchChannel.h"
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
            int error = fcntl(fd, F_SETFL, curflags | O_NONBLOCK | O_ASYNC);
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
                NSLog(@"event try");
                TryConnect(false, fd, readSource);
            });
            
            dispatch_source_set_cancel_handler(readSource, [fd]{
                close(fd);
                NSLog(@"Pew");
            });
            
            NSLog(@"Normal Try");

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
            
            Connector *slf = this;
            addrinfo *res = _res0;
            
            finish_callback callback = [_finishCallback copy];
            
            // If we get this far, we're done
            dispatch_async(_workQueue, ^{
                callback(slf, res, fd, 0, nullptr);
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
                dispatch_sync(callback_queue, [=]{
                    callback(fd, error_code, error_message);
                    
                    if (res0) {
                        freeaddrinfo(res0);
                    }
                    
                    dispatch_release(callback_queue);
                    
                    if (connector) {
                        // Delete it after it doesn't reference this block anymore
                        dispatch_async(callback_queue, [workQueue, connector]{
                            delete connector;
                        });
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
}
}
