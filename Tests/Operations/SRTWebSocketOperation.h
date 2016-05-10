//
// Copyright 2012 Square Inc.
// Portions Copyright (c) 2016-present, Facebook, Inc.
//
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import <SocketRocket/SRWebSocket.h>

@interface SRTWebSocketOperation : NSOperation <SRWebSocketDelegate>

@property (nonatomic) BOOL isFinished;
@property (nonatomic) BOOL isExecuting;

@property (nonatomic, strong, readonly) NSError *error;

- (instancetype)initWithURL:(NSURL *)URL;

// We override these methods.  Please call super
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean NS_REQUIRES_SUPER;
- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error NS_REQUIRES_SUPER;

- (BOOL)waitUntilFinishedWithTimeout:(NSTimeInterval)timeout;

@end
