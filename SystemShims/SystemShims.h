//
//  SystemShims.h
//  SystemShims
//
//  Created by Mike Lewis on 7/31/15.
//
//


#import <UIKit/UIKit.h>

//! Project version number for SystemShims.
FOUNDATION_EXPORT double SystemShimsVersionNumber;

//! Project version string for SystemShims.
FOUNDATION_EXPORT const unsigned char SystemShimsVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <SystemShims/PublicHeader.h>


extern int shim_fcntl(int fildes, int cmd, int flags);
extern int shim_bind(int fildes, const void *addr, size_t size);
extern int shim_accept(int fildes, void *addr, socklen_t *size);

#include <netinet/in.h>

typedef union sockaddr_union {
    struct sockaddr addr;
    struct sockaddr_in ipv4;
    struct sockaddr_in6 ipv6;
} sockaddr_union;

// Returns sockaddr from union
extern inline struct sockaddr *sockaddr_union_getsockaddr(sockaddr_union *u) {
    return &u->addr;
}

extern inline const struct sockaddr_in *sockaddr_union_getsockaddr_in(const sockaddr_union *u) {
    return &u->ipv4;
}

extern inline const struct sockaddr_in6 *sockaddr_union_getsockaddr_in6(const sockaddr_union *u) {
    return &u->ipv6;
}

