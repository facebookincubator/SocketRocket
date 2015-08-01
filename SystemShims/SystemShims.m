//
//  SystemShims.c
//  SocketRocket
//
//  Created by Mike Lewis on 7/31/15.
//
//

#import "SystemShims.h"

#import <sys/fcntl.h>
#import <sys/socket.h>

extern int shim_fcntl(int fildes, int cmd, int flags) {
    return fcntl(fildes, cmd, flags);
}

extern int shim_bind(int fildes, const void *addr, size_t size) {
    return bind(fildes, addr, (socklen_t)size);
}

extern int shim_accept(int fildes, void *addr, socklen_t *size) {
    return accept(fildes, addr, size);
}
