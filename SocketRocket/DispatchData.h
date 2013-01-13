//
//  DispatchData.h
//  SocketRocket
//
//  Created by Michael Lewis on 1/12/13.
//
//

#ifndef __SocketRocket__DispatchData__
#define __SocketRocket__DispatchData__

extern "C" {
    #include <string.h>
}

#include <iostream>
#include <dispatch/dispatch.h>

namespace squareup {
namespace dispatch {
    class Data {
        dispatch_data_t _data;
    public:

        // Initializes a new data. retains the data by default
        // Data always releases _data;
        inline Data(dispatch_data_t data, bool retain = true) : _data(data) {
            if (retain) {
                dispatch_retain(_data);
            }
        }
        
        // Will copy the data
        inline Data(const char *str, dispatch_queue_t release_queue) :
            _data(dispatch_data_create(reinterpret_cast<const void *>(str), strlen(str), release_queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT)) {
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
            return dispatch_data_get_size(*this);
        }
        
        inline operator dispatch_data_t() const {
            return _data;
        }
        
        virtual ~Data() {
            dispatch_release(_data);
        }
        
        static const Data empty;
    };
}
}

#endif /* defined(__SocketRocket__DispatchData__) */
