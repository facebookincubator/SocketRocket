//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "SRTWebSocketOperation.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^SRAutobahnSocketTextMessageHandler)(SRWebSocket *socket, NSString  * _Nullable message);
typedef void(^SRAutobahnSocketDataMessageHandler)(SRWebSocket *socket, NSData  * _Nullable message);

@interface SRAutobahnOperation : SRTWebSocketOperation

- (instancetype)initWithServerURL:(NSURL *)url
                  testCommandPath:(NSString *)path
                       caseNumber:(nullable NSNumber *)caseNumber
                            agent:(nullable NSString *)agent
               textMessageHandler:(nullable SRAutobahnSocketTextMessageHandler)textMessageHandler
               dataMessageHandler:(nullable SRAutobahnSocketDataMessageHandler)dataMessageHandler;

@end

extern SRAutobahnOperation *SRAutobahnTestOperation(NSURL *serverURL, NSInteger caseNumber, NSString *agent);

typedef void(^SRAutobahnTestResultHandler)(NSDictionary *_Nullable result);
extern SRAutobahnOperation *SRAutobahnTestResultOperation(NSURL *serverURL, NSInteger caseNumber, NSString *agent, SRAutobahnTestResultHandler handler);

typedef void(^SRAutobahnTestCaseInfoHandler)(NSDictionary *_Nullable caseInfo);
extern SRAutobahnOperation *SRAutobahnTestCaseInfoOperation(NSURL *serverURL, NSInteger caseNumber, SRAutobahnTestCaseInfoHandler handler);

typedef void(^SRAutobahnTestCaseCountHandler)(NSInteger caseCount);
extern SRAutobahnOperation *SRAutobahnTestCaseCountOperation(NSURL *serverURL, NSString *agent, SRAutobahnTestCaseCountHandler handler);

extern SRAutobahnOperation *SRAutobahnTestUpdateReportsOperation(NSURL *serverURL, NSString *agent);

NS_ASSUME_NONNULL_END
