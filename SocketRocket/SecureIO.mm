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
        
        SecureIO::SecureIO(IO *io, SSLContextRef context, dispatch_queue_t workQueue, dispatch_queue_t callbackQueue) : _io(io), _context(context), _workQueue(workQueue) {
            dispatch_retain(_workQueue);
            dispatch_retain(_callbackQueue);

            SSLSetIOFuncs(_context, readFunc, writeFunc);
        }
        
        SecureIO::~SecureIO() {
            dispatch_release(_workQueue);
        }
        
        void SecureIO::Close(dispatch_io_close_flags_t flags) {
            
        }
        
        void SecureIO::Read(size_t length, dispatch_io_handler_t handler) {
            
        }
        
        void SecureIO::Write(dispatch_data_t data, dispatch_io_handler_t handler) {
            Data d(data);
            
            handler = [handler copy];
            
            dispatch_async(_workQueue, [=]{
                bool success = true;
                d.Apply([&](dispatch_data_t region, size_t offset, const void *buffer, size_t size) -> bool {
                    size_t sslSize = size;
                    OSStatus result = SSLWrite(buffer, &sslSize);
                    if (result != 0) {
                        dispatch_async(_callbackQueue, ^{
                            handler(true, data, result);
                        });
                        _io->Close(DISPATCH_IO_STOP);
                        success = false;
                        return false;
                    }
                    // We should be able to make this assumptions
                    assert(sslSize == size);
                    return true;
                });
                
                if (success) {
                    dispatch_async(_callbackQueue, ^{
                        handler(true, dispatch_data_empty, 0);
                    });
                }
            });
        }
        
        OSStatus SecureIO::SSLWrite(const void *data, size_t *dataLength) const {
            _io->Write(Data(data, *dataLength, _workQueue), ^(bool done, dispatch_data_t data, int error) {
                // TODO handle error
                assert(error == 0);
            });
            
            return 0;
        }
        
        void SecureIO::Barrier(dispatch_block_t barrier) {
            _io->Barrier(barrier);
        }

        OSStatus readFunc(SSLConnectionRef connection, void *data, size_t *dataLength) {
            return reinterpret_cast<const SecureIO *>(connection)->SSLRead(data, dataLength);
        };
        
        OSStatus writeFunc(SSLConnectionRef connection, const void *data, size_t *dataLength) {
            return reinterpret_cast<const SecureIO *>(connection)->SSLWrite(data, dataLength);
        };
        
    }
}
