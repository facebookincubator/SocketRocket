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

#import "SRTWebSocketOperation.h"

#import "SRAutobahnUtilities.h"

@interface SRTWebSocketOperation ()

@end

@implementation SRTWebSocketOperation {
    NSInteger _testNumber;
    SRWebSocket *_webSocket;
    NSURL *_url;
}

@synthesize isFinished = _isFinished;
@synthesize isExecuting = _isExecuting;
@synthesize error = _error;

- (instancetype)initWithURL:(NSURL *)URL;
{
    self = [super init];
    if (self) {
        _url = URL;
        _isExecuting = NO;
        _isFinished = NO;
    }
    return self;
}

- (BOOL)isConcurrent;
{
    return YES;
}

- (void)start;
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _webSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:_url]];
        _webSocket.delegate = self;
        [_webSocket open];
    });
    self.isExecuting = YES;
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean;
{
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _isFinished = YES;
    _isExecuting = NO;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
    _webSocket.delegate = nil;
    _webSocket = nil;
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
{
    _error = error;
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _isFinished = YES;
    _isExecuting = NO;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
    _webSocket.delegate = nil;
    _webSocket = nil;
}

- (BOOL)waitUntilFinishedWithTimeout:(NSTimeInterval)timeout
{
    if (self.isFinished) {
        return YES;
    }
    return SRRunLoopRunUntil(^BOOL{
        return self.isFinished;
    }, timeout);
}

@end
