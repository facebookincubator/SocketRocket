//
//  DispatchData.h
//  SocketRocket
//
//  Created by Michael Lewis on 1/12/13.
//
//

#ifndef __SocketRocket__DispatchData__
#define __SocketRocket__DispatchData__

#include <string.h>

#include <iostream>
#include <dispatch/dispatch.h>
#include <deque>

#include "Common.h"

namespace squareup {
namespace dispatch {
    class Data {
        __sr_maybe_strong__ dispatch_data_t _data;
    public:
        inline Data() : Data(dispatch_data_empty) {
            
        }
        
        // Initializes a new data. retains the data by default
        // Data always releases _data;
        inline Data(dispatch_data_t data, bool retain = true) : _data(data) {
            if (retain && _data) {
                sr_dispatch_retain(_data);
            }
        }
        
        // Will copy the data
        inline Data(const char *str, dispatch_queue_t release_queue) :
            _data(dispatch_data_create(reinterpret_cast<const void *>(str), strlen(str), release_queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT)) {
        }
        
        // Copy constructor
        inline Data(const Data &other)  : Data(static_cast<dispatch_data_t>(other), true) {
            
        }
        
        inline Data(const void *bytes, size_t length, dispatch_queue_t release_queue) :
        _data(dispatch_data_create(bytes, length, release_queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT)) {
        }

        
        inline Data Concat(dispatch_data_t other) const {
            return Data(dispatch_data_create_concat(_data, other), false);
        }
        
        
        inline Data operator + (dispatch_data_t other) const {
            return Concat(other);
        }
        
        inline Data Subrange(size_t offset, size_t length) const {
            return Data(dispatch_data_create_subrange(_data, offset, length), false);
        }
        
        // copies bytes into the buffer, and returns the remaining.
        inline Data TakeInto(size_t length, void *bytes) const {
            size_t size = Size();
            assert(length <= size);
            
            
            Apply([&](dispatch_data_t region, size_t offset, const void *buffer, size_t size) -> bool {
                size_t numToCopy = std::min(size, length - offset);

                memcpy(reinterpret_cast<void *>(reinterpret_cast<uint8_t *>(bytes) + offset), buffer, numToCopy);
                
                return size + offset <= length;
            });
            
            if (length == size) {
                return dispatch_data_empty;
            }
            return Subrange(length, size - length);
        }
        
        inline Data Map(const void **buffer_ptr, size_t *size_ptr) const {
            return Data(dispatch_data_create_map(_data, buffer_ptr, size_ptr), false);
        }
        
        inline Data CopyRegion(size_t location, size_t *offset_ptr) const {
            return Data(dispatch_data_copy_region(_data, location, offset_ptr), false);
        }
        
        inline bool Apply(dispatch_data_applier_t applier) const {
            return dispatch_data_apply(_data, applier);
        }
        
        inline size_t Size() const {
            return dispatch_data_get_size(static_cast<dispatch_data_t>(*this));
        }
        
        inline operator dispatch_data_t() const {
            return _data;
        }
        
        inline Data &operator = (const dispatch_data_t &other) {
            if (other) {
                sr_dispatch_retain(other);
            }
            if (_data) {
                sr_dispatch_release(_data);
            }
            _data = other;
            return *this;
        }
        
        inline Data &operator += (const Data &other) {
            return (*this = Concat(other));
        }
        
        virtual ~Data() {
            if (_data) {
                sr_dispatch_release(_data);
            }
        }
        
        static const Data empty;
    };
}
}

#endif /* defined(__SocketRocket__DispatchData__) */
