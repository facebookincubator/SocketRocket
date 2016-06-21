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

@property (nullable, nonatomic, copy, readonly) SRAutobahnSocketTextMessageHandler textMessageHandler;
@property (nullable, nonatomic, copy, readonly) SRAutobahnSocketDataMessageHandler dataMessageHandler;

@end

@implementation SRAutobahnOperation

- (instancetype)initWithServerURL:(NSURL *)url
                  testCommandPath:(NSString *)path
                       caseNumber:(nullable NSNumber *)caseNumber
                            agent:(nullable NSString *)agent
               textMessageHandler:(nullable SRAutobahnSocketTextMessageHandler)textMessageHandler
               dataMessageHandler:(nullable SRAutobahnSocketDataMessageHandler)dataMessageHandler
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

    _textMessageHandler = [textMessageHandler copy];
    _dataMessageHandler = [dataMessageHandler copy];

    return self;
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessageWithString:(NSString *)string
{
    if (self.textMessageHandler) {
        self.textMessageHandler(webSocket, string);
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessageWithData:(NSData *)data
{
    if (self.dataMessageHandler) {
        self.dataMessageHandler(webSocket, data);
    }
}

@end

SRAutobahnOperation *SRAutobahnTestOperation(NSURL *serverURL, NSInteger caseNumber, NSString *agent)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/runCase"
                                               caseNumber:@(caseNumber)
                                                    agent:agent
                                       textMessageHandler:^(SRWebSocket * _Nonnull socket, NSString  * _Nullable message) {
                                           [socket sendString:message error:nil];
                                       }
                                       dataMessageHandler:^(SRWebSocket * _Nonnull socket, NSData * _Nullable message) {
                                           [socket sendData:message error:nil];
                                       }];
}

extern SRAutobahnOperation *SRAutobahnTestResultOperation(NSURL *serverURL, NSInteger caseNumber, NSString *agent, SRAutobahnTestResultHandler handler)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/getCaseStatus"
                                               caseNumber:@(caseNumber)
                                                    agent:agent
                                       textMessageHandler:^(SRWebSocket * _Nonnull socket, NSString * _Nullable message) {
                                           NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
                                           NSDictionary *result = [NSJSONSerialization JSONObjectWithData:messageData options:0 error:NULL];
                                           handler(result);
                                       }
                                       dataMessageHandler:nil];
}

extern SRAutobahnOperation *SRAutobahnTestCaseInfoOperation(NSURL *serverURL, NSInteger caseNumber, SRAutobahnTestCaseInfoHandler handler)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/getCaseInfo"
                                               caseNumber:@(caseNumber)
                                                    agent:nil
                                       textMessageHandler:^(SRWebSocket * _Nonnull socket, NSString * _Nullable message) {
                                           NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
                                           NSDictionary *result = [NSJSONSerialization JSONObjectWithData:messageData options:0 error:NULL];
                                           handler(result);
                                       }
                                       dataMessageHandler:nil];
}

extern SRAutobahnOperation *SRAutobahnTestCaseCountOperation(NSURL *serverURL, NSString *agent, SRAutobahnTestCaseCountHandler handler)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/getCaseCount"
                                               caseNumber:nil
                                                    agent:agent
                                       textMessageHandler:^(SRWebSocket * _Nonnull socket, NSString * _Nullable message) {
                                           NSInteger count = [message integerValue];
                                           handler(count);
                                       }
                                       dataMessageHandler:nil];
}

extern SRAutobahnOperation *SRAutobahnTestUpdateReportsOperation(NSURL *serverURL, NSString *agent)
{
    return [[SRAutobahnOperation alloc] initWithServerURL:serverURL
                                          testCommandPath:@"/updateReports"
                                               caseNumber:nil
                                                    agent:agent
                                       textMessageHandler:nil
                                       dataMessageHandler:nil];
}

NS_ASSUME_NONNULL_END
