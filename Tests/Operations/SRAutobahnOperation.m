//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "SRAutobahnOperation.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRAutobahnOperation ()

@property (nonatomic, copy, readonly) SRAutobahnSocketMessageHandler messageHandler;

@end

@implementation SRAutobahnOperation

- (instancetype)initWithServerURL:(NSURL *)url
                  testCommandPath:(NSString *)path
                       caseNumber:(nullable NSNumber *)caseNumber
                            agent:(nullable NSString *)agent
                   messageHandler:(SRAutobahnSocketMessageHandler)messageHandler
{
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    components.path = (components.path ? [components.path stringByAppendingPathComponent:path] : path);

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithCapacity:2];
    if (caseNumber) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"case" value:caseNumber.stringValue]];
    }
    if (agent) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"agent" value:agent]];
    }
    components.queryItems = queryItems;
    self = [self initWithURL:components.URL];
    if (!self) return self;

    _messageHandler = [messageHandler copy];

    return self;
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    self.messageHandler(webSocket, message);
}

@end

SRAutobahnOperation *SRAutobahnTestOperation(NSURL *serverURL, NSInteger caseNumber, NSString *agent)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/runCase"
                                               caseNumber:@(caseNumber)
                                                    agent:agent
                                           messageHandler:^(SRWebSocket * _Nonnull socket, id  _Nullable message) {
                                               //TODO: (nlutsenko) Use proper callbacks, instead of a unifying one.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                                               [socket send:message];
#pragma clang diagnostic pop
                                           }];
}

extern SRAutobahnOperation *SRAutobahnTestResultOperation(NSURL *serverURL, NSInteger caseNumber, NSString *agent, SRAutobahnTestResultHandler resultHandler)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/getCaseStatus"
                                               caseNumber:@(caseNumber)
                                                    agent:agent
                                           messageHandler:^(SRWebSocket * _Nonnull socket, id  _Nullable message) {
                                               NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
                                               NSDictionary *result = [NSJSONSerialization JSONObjectWithData:messageData options:0 error:NULL];
                                               resultHandler(result);
                                           }];
}

extern SRAutobahnOperation *SRAutobahnTestCaseInfoOperation(NSURL *serverURL, NSInteger caseNumber, SRAutobahnTestCaseInfoHandler handler)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/getCaseInfo"
                                               caseNumber:@(caseNumber)
                                                    agent:nil
                                           messageHandler:^(SRWebSocket * _Nonnull socket, id  _Nullable message) {
                                               NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
                                               NSDictionary *result = [NSJSONSerialization JSONObjectWithData:messageData options:0 error:NULL];
                                               handler(result);
                                           }];
}

extern SRAutobahnOperation *SRAutobahnTestCaseCountOperation(NSURL *serverURL, NSString *agent, SRAutobahnTestCaseCountHandler handler)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/getCaseCount"
                                               caseNumber:nil
                                                    agent:agent
                                           messageHandler:^(SRWebSocket * _Nonnull socket, id  _Nullable message) {
                                               NSInteger count = [message integerValue];
                                               handler(count);
                                           }];
}

extern SRAutobahnOperation *SRAutobahnTestUpdateReportsOperation(NSURL *serverURL, NSString *agent)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/updateReports"
                                               caseNumber:nil
                                                    agent:agent
                                           messageHandler:^(SRWebSocket * _Nonnull socket, id  _Nullable message) {
                                               // Nothing to do
                                           }];
}

NS_ASSUME_NONNULL_END
