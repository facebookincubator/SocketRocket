//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "SRURLUtilities.h"

NSString *SRURLOrigin(NSURL *url)
{
    NSMutableString *origin = [NSMutableString string];

    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"wss"]) {
        scheme = @"https";
    } else if ([scheme isEqualToString:@"ws"]) {
        scheme = @"http";
    }
    [origin appendFormat:@"%@://%@", scheme, url.host];

    NSNumber *port = url.port;
    BOOL portIsDefault = (!port ||
                          ([scheme isEqualToString:@"http"] && port.integerValue == 80) ||
                          ([scheme isEqualToString:@"https"] && port.integerValue == 443));
    if (!portIsDefault) {
        [origin appendFormat:@":%@", port.stringValue];
    }
    return origin;
}
