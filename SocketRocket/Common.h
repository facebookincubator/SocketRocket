//
//  Common.h
//  SocketRocket
//
//  Created by Michael Lewis on 1/15/13.
//
//

#ifndef SocketRocket_Common_h
#define SocketRocket_Common_h

#ifdef __cplusplus
extern "C" {
#endif
    
#if OS_OBJECT_USE_OBJC_RETAIN_RELEASE
#define sr_dispatch_retain(x)
#define sr_dispatch_release(x)
#define __sr_maybe_bridge__ __bridge
#define __sr_maybe_strong__ __strong
#else
#define sr_dispatch_retain(x) dispatch_retain(x)
#define sr_dispatch_release(x) dispatch_release(x)
#define __sr_maybe_bridge__
#define __sr_maybe_strong__
#endif
    
#ifdef __cplusplus
}
#endif

#endif
