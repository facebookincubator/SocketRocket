//
//  SecureIO.cpp
//  SocketRocket
//
//  Created by Michael Lewis on 1/12/13.
//
//

#include <Security/SecureTransport.h>

#include "SecureIO.h"
#include "DispatchData.h"

namespace squareup {
    namespace dispatch {
        static OSStatus readFunc(SSLConnectionRef connection, void *data, size_t *dataLength);
        static OSStatus writeFunc(SSLConnectionRef connection, const void *data, size_t *dataLength);
        
        void DialTLS(const char *hostname,
                     const char *servname,
                     SSLContextRef ssl_context,
                     dispatch_queue_t callback_queue,
                     dispatch_queue_t work_queue,
                     dispatch_queue_t parent_io_queue,
                     dial_tls_callback dial_callback,
                     void(^close_handler)(int error)) {
            
            if (close_handler != nullptr) {
                close_handler = [close_handler copy];
            }
            
            dial_callback = [dial_callback copy];
            sr_dispatch_retain(callback_queue);
            
            // The work queue is the outer ones callback_queue
            SimpleDial(hostname, servname, work_queue, parent_io_queue, [=](squareup::dispatch::RawIO *io, int error, const char *error_message) {
                if (error != 0 || io == nullptr) {
                    dispatch_async(callback_queue, ^{
                        dial_callback(nullptr, error, error_message);
                    });
                    sr_dispatch_release(callback_queue);
                    return;
                }
                
                SecureIO *newIO = new SecureIO(io, ssl_context, work_queue, callback_queue);
                
                sr_dispatch_release(callback_queue);
                
                newIO->Handshake([newIO, dial_callback](bool done, dispatch_data_t data, int error) {
                    SecureIO *io = newIO;
                    if (error) {
                        delete io;
                        io = nullptr;
                    }
                    
                    // TODO: maybe add message?
                    dial_callback(io, error, nullptr);
                });
                
            }, close_handler);
        }
        
        
        SecureIO::SecureIO(IO *io, SSLContextRef context, dispatch_queue_t workQueue, dispatch_queue_t callbackQueue) :
        _io(io), _context(context), _workQueue(workQueue), _callbackQueue(callbackQueue) {
            sr_dispatch_retain(_workQueue);
            sr_dispatch_retain(_callbackQueue);
            CFRetain(_context);
            
            SSLSetConnection(_context, reinterpret_cast<const void *>(this));
            SSLSetIOFuncs(_context, readFunc, writeFunc);
            
            // TODO: delegate certificate authentication
            #if DEBUG
            SSLSetSessionOption(_context, kSSLSessionOptionBreakOnServerAuth, true);
            #endif
        }
        
        SecureIO::~SecureIO() {
            sr_dispatch_release(_workQueue);
            sr_dispatch_release(_callbackQueue);
            CFRelease(_context);
            
            // make sure things closed before we delete the io
            assert(!_io);
        }
        
        void SecureIO::Handshake(dispatch_io_handler_t handler) {
            _handshakeHandler = [handler copy];
            dispatch_async(_workQueue, [this]{
                CheckHandshake();
            });
        }
        
        void SecureIO::Close(dispatch_io_close_flags_t flags) {
            assert(!_closing);
            dispatch_async(_workQueue, [this, flags]{
                assert(!_closing);
                _closing = true;
                OSStatus status = SSLClose(_context);
                
                // This shouldn't be a blocking operation
                assert(status != errSSLWouldBlock);
                
                Cancel(flags, status);
                return;
            });
        }
        
        void SecureIO::Read(size_t length, dispatch_io_handler_t handler) {
            handler = [handler copy];
            dispatch_async(_workQueue, [length, handler, this]{
                if (_cancelled) {
                    dispatch_async(_callbackQueue, [handler]{
                        handler(true, nullptr, ECANCELED);
                    });
                    return;
                }
                
                ReadRequest readRequest;
                readRequest.handler = handler;
                readRequest.rawBytesRemaining = length;
                
                _readRequests.push_back(readRequest);
                // TODO: run on queue
                _rawBytesRequested += length;
                PumpSSLRead();
            });
        }
        
        void SecureIO::PumpSSLRead() {
            _calculatingRequestSize = true;
            
            size_t dummyProcessed;
            // Make sure we are requesting enough;
            OSStatus status = ::SSLRead(_context, nullptr, _rawBytesRequested, &dummyProcessed);
            assert(status == errSSLWouldBlock);
            
            _calculatingRequestSize = false;
        }
        
        void SecureIO::Write(dispatch_data_t data, dispatch_io_handler_t handler) {

            sr_dispatch_retain(data);
            handler = [handler copy];

            Data(data).Apply(^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                return true;
            });

            
            dispatch_async(_workQueue, [data, handler, this]{
                InnerWrite(data, handler);
                sr_dispatch_release(data);
            });
        }
        
        void SecureIO::InnerWrite(dispatch_data_t data, dispatch_io_handler_t handler) {
            if (_cancelled) {
                dispatch_async(_callbackQueue, [handler]{
                    handler(true, nullptr, ECANCELED);
                });
                return;
            }
            
            OSStatus result = 0;
            
            size_t totalSize = dispatch_data_get_size(data);
            
            dispatch_data_apply(data, [&](dispatch_data_t region, size_t offset, const void *buffer, size_t size) -> bool {
                WriteJob newJob;
                newJob.handler = handler;
                newJob.rawBytes = size;
                newJob.isLast = offset + size == totalSize;
                newJob.cryptedBytes = 0;
                
                _writeJobs.push_back(newJob);
                
                // WriteSSL will fill in the crypted bytes
                // isLast will be set to True for the last one
                size_t sizeWritten = 0;
                result = ::SSLWrite(_context, buffer, size, &sizeWritten);
                
                // I think we can make this assumption since we don't block at all in our handler.
                
                if (result != 0) {
                    return false;
                };
                
                // We should be able to make this assumptions since our write func never blocks
                assert(sizeWritten == size);
                return true;
            });
            
            if (result) {
                Cancel(0, result);
                return;
            }

        }
        
        void SecureIO::RequestBytes(size_t bytesWanted) {
            if (bytesWanted > _cryptedBytesRequested) {
                size_t requestSize = bytesWanted - _cryptedBytesRequested;
                
                _cryptedBytesRequested += requestSize;
                
                _io->Read(requestSize, [this](bool done, dispatch_data_t data, int error) {
                    HandleSSLRead(done, data, error);
                });
            }
        };
        
        OSStatus SecureIO::SSLReadHandler(void *data, size_t *dataLength) {
            if (_calculatingRequestSize) {
                RequestBytes(*dataLength);
                *dataLength = 0;
                return errSSLWouldBlock;
            }
            
            size_t bytesRequested = *dataLength;
            
            // If _calculatingRequestSize is true, always return errSSLWouldBlock and pretend we don't have any data
            
            size_t bytesToCopy = std::min(_waitingCryptedData.Size(), bytesRequested);
            
            *dataLength = bytesToCopy;
            
            if (bytesToCopy > 0) {
                // Advance it forward
                _waitingCryptedData = _waitingCryptedData.TakeInto(bytesToCopy, data);
            }
            
            if (bytesToCopy < bytesRequested) {
                RequestBytes(bytesRequested - bytesToCopy);
                return errSSLWouldBlock;
            }
            
            return noErr;
        }
        
        OSStatus SecureIO::SSLWriteHandler(const void *data, size_t *dataLength) {
            size_t requestedLength = *dataLength;
            
            SSLSessionState state;
            SSLGetSessionState(_context, &state);
            
            NSLog(@"State %d", state);
            
            if (!_handshakeHandler && !_closing) {
                assert(_writeJobs.size() > 0);
                _writeJobs.back().cryptedBytes += requestedLength;
            }
            
            _io->Write(Data(data, requestedLength, _workQueue), [this, requestedLength](bool done, dispatch_data_t data, int error) {
                HandleSSLWrite(done, requestedLength, error);
            });
            
            
            return 0;
        }
        
        void SecureIO::HandleSSLRead(bool done, dispatch_data_t data, int error) {
            assert(_handshakeHandler || _readRequests.size() > 0);
//            
//            if (error == ECANCELED) {
//                Cancel();
//                return;
//            }
            
            if (error != 0) {
                dispatch_io_handler_t handler = nullptr;
                if (_handshakeHandler) {
                    handler = _handshakeHandler;
                } else {
                    assert(_readRequests.size() > 0);
                    handler = _readRequests.front().handler;
                }
                handler(done, nullptr, error);
                return;
            }
            
            // We got some data, so append it
            Data d(data);
            _cryptedBytesRequested -= d.Size();
            _waitingCryptedData += d;
            
            if (_handshakeHandler) {
                CheckHandshake();
                return;
            }
            
            assert(_readRequests.size() > 0);
            
            ReadRequest &frontRead = _readRequests.front();
            dispatch_io_handler_t handler = frontRead.handler;
            
            size_t length = frontRead.rawBytesRemaining;
            
            // Let's cap length at 2x the bytes we have available.  probably won't use all of it (it will probably be less than 1x)
            length = std::min(length, 2 * _waitingCryptedData.Size());
            length = std::min(length, _highWater);
            
            size_t sizeRead = 0;
            
            void *buffer = malloc(length);
            assert(buffer);
            
            // TODO: optimize this and not malloc memory each time
            assert(_calculatingRequestSize == false);
            
            OSStatus status = ::SSLRead(_context, buffer, length, &sizeRead);
            if (status != 0 && status != errSSLWouldBlock && status != errSSLClosedGraceful) {
                free(buffer);
                buffer = nullptr;
                // TODO: handle error better
                dispatch_async(_callbackQueue, [handler, error]{
                    handler(true, nullptr, error);
                });
                _readRequests.pop_front();
                return;
            }
            
            Data rawData(dispatch_data_create(buffer, sizeRead, _workQueue, DISPATCH_DATA_DESTRUCTOR_FREE), false);
            
            frontRead.rawBytesRemaining -= sizeRead;
            
            bool isDone = (frontRead.rawBytesRemaining == 0);
            
            // TODO: honor watermarks
            dispatch_async(_callbackQueue, [isDone, rawData, handler]{
                handler(isDone, rawData, 0);
            });
            
            if (status == errSSLClosedGraceful) {
                // TODO: handle close
            }
            
            if (isDone) {
                _readRequests.pop_front();
            }
            
            PumpSSLRead();
        }
        
        void SecureIO::HandleSSLWrite(bool done, size_t requestedLength, int error) {
            if (_handshakeHandler) {
                CheckHandshake();
                return;
            }
            
            if (_closing) {
                return;
            }
            
            assert(_writeJobs.size() > 0);
            
            // TODO(lewis): handle rest of errors better
            if (error != 0) {
                _writeJobs.front().handler(true, dispatch_data_empty, error);
                return;
            }
            
            assert(_writeJobs.size());
            
            // We only want to call the handlers when we are "done".
            // This way we can approximate the bytes that are written
            if (done) {
                // if we're an error we want to go to the last one
                if (error) {
                    Cancel(0, error);
                    return;
                }
                
                assert(_writeJobs.size());
                
                _writeJobs.front().cryptedBytes -= requestedLength;
                
                WriteJob writeJob = _writeJobs.front();
                
                // Only call them when we're "done" for now, because we don't want to do bookkeeping of remaining data to consume
                // TODO: probably change this
                if (writeJob.isLast) {
                    dispatch_async(_callbackQueue, [writeJob, error]{
                        writeJob.handler(writeJob.isLast, dispatch_data_empty, error);
                    });
                }
                
                if (writeJob.cryptedBytes == 0) {
                    _writeJobs.pop_front();
                }
            }
        }
        
        
        void SecureIO::CheckHandshake() {
            assert(_handshakeHandler);
            OSStatus status = ::SSLHandshake(_context);
            // If it would block we got nothing to do
            if (status == errSSLWouldBlock) {
                return;
            }
            
            #if DEBUG
            
            // TODO: make this better
            if (status == errSSLPeerAuthCompleted) {
                CheckHandshake();
                return;
            }
            
            #endif
            
            dispatch_io_handler_t handler = _handshakeHandler;
            _handshakeHandler = nullptr;
            
            dispatch_async(_callbackQueue, [handler, status]{
                handler(true, dispatch_data_empty, status);
            });
        }
        
        void SecureIO::Cancel(dispatch_io_close_flags_t flags, int error) {
            _cancelled = true;
            NSLog(@"Cancelled");
            for (const ReadRequest &req : _readRequests) {
                dispatch_async(_callbackQueue, [req]{
                    req.handler(true, nullptr, ECANCELED);
                });
            }
            
            for (const WriteJob &job : _writeJobs) {
                dispatch_async(_callbackQueue, [job]{
                    job.handler(true, nullptr, ECANCELED);
                });
            }
            
            _readRequests.clear();
            _writeJobs.clear();
            
            _io->Close(flags);
            delete _io;
            _io = nullptr;
        }
        
        void SecureIO::Barrier(dispatch_block_t barrier) {
            _io->Barrier(barrier);
        }
        
        OSStatus readFunc(SSLConnectionRef connection, void *data, size_t *dataLength) {
            return reinterpret_cast<SecureIO *>((void *)connection)->SSLReadHandler(data, dataLength);
        };
        
        OSStatus writeFunc(SSLConnectionRef connection, const void *data, size_t *dataLength) {
            return reinterpret_cast<SecureIO *>((void *)connection)->SSLWriteHandler(data, dataLength);
        };
    }
}
