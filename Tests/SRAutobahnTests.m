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

@import XCTest;
@import ObjectiveC;

#import <SocketRocket/SRWebSocket.h>

#import "SRTWebSocketOperation.h"
#import "SRAutobahnOperation.h"
#import "XCTestCase+SRTAdditions.h"
#import "SRAutobahnUtilities.h"

@interface SRAutobahnTests : XCTestCase
@end

@implementation SRAutobahnTests

+ (NSArray<NSInvocation *> *)testInvocations
{
    __block NSArray<NSInvocation *> *array = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSInvocation *> *invocations = [NSMutableArray array];
        for (NSUInteger i = 1; i <= SRAutobahnTestCaseCount(); i++) {
            NSDictionary *caseInfo = SRAutobahnTestCaseInfo(i);
            NSString *identifier = caseInfo[@"id"];

            NSInvocation *invocation = [self invocationWithCaseNumber:i identifier:identifier];
            [invocations addObject:invocation];
        }

        array = [invocations sortedArrayUsingComparator:^NSComparisonResult(NSInvocation *_Nonnull obj1, NSInvocation *_Nonnull obj2) {
            return [NSStringFromSelector(obj1.selector) compare:NSStringFromSelector(obj2.selector) options:NSNumericSearch];
        }];
    });
    return array;
}

+ (void)updateReports
{
    SRAutobahnOperation *operation = SRAutobahnTestUpdateReportsOperation(SRAutobahnTestServerURL(), SRAutobahnTestAgentName());
    [operation start];

    SRRunLoopRunUntil(^BOOL{
        return operation.isFinished;
    }, 60 * 60);

    NSAssert(!operation.error, @"Updating the report should not have errored %@", operation.error);
}

///--------------------------------------
#pragma mark - Init
///--------------------------------------

+ (instancetype)testCaseWithSelector:(SEL)selector
{
    NSArray<NSInvocation *> *invocations = [self testInvocations];
    for (NSInvocation *invocation in invocations) {
        if (invocation.selector == selector) {
            return [super testCaseWithSelector:selector];
        }
    }
    return nil;
}

///--------------------------------------
#pragma mark - Setup
///--------------------------------------

+ (NSInvocation *)invocationWithCaseNumber:(NSUInteger)caseNumber identifier:(NSString *)identifier
{
    SEL selector = [self addInstanceMethodForTestCaseNumber:caseNumber identifier:identifier];
    NSMethodSignature *signature = [self instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    return invocation;
}

+ (SEL)addInstanceMethodForTestCaseNumber:(NSInteger)caseNumber identifier:(NSString *)identifier
{
    NSString *selectorName = [NSString stringWithFormat:@"Case #%@", identifier];
    SEL selector = NSSelectorFromString(selectorName);

    IMP implementation = imp_implementationWithBlock(^(SRAutobahnTests *self) {
        [self performTestWithCaseNumber:caseNumber identifier:identifier];
    });
    NSString *typeString = [NSString stringWithFormat:@"%s%s%s",  @encode(id), @encode(id), @encode(SEL)];
    class_addMethod(self, selector, implementation, typeString.UTF8String);

    return selector;
}

///--------------------------------------
#pragma mark - Teardown
///--------------------------------------

+ (void)tearDown
{
    [self updateReports];
    [super tearDown];
}

///--------------------------------------
#pragma mark - Test
///--------------------------------------

- (void)performTestWithCaseNumber:(NSInteger)caseNumber identifier:(NSString *)identifier
{
    NSURL *serverURL = SRAutobahnTestServerURL();
    NSString *agent = SRAutobahnTestAgentName();

    NSOperationQueue *testQueue = [[NSOperationQueue alloc] init];
    testQueue.maxConcurrentOperationCount = 1;

    SRAutobahnOperation *testOp = SRAutobahnTestOperation(serverURL, caseNumber, agent);
    [testQueue addOperation:testOp];

    __block NSDictionary *resultInfo = nil;
    SRAutobahnOperation *resultOp = SRAutobahnTestResultOperation(serverURL, caseNumber, agent, ^(NSDictionary * _Nullable result) {
        resultInfo = result;
    });
    [resultOp addDependency:testOp];
    [testQueue addOperation:resultOp];

    testQueue.suspended = NO;

    [self runCurrentRunLoopUntilTestPasses:^BOOL{
        return resultOp.isFinished;
    } timeout:60 * 60];

    XCTAssertTrue(!testOp.error, @"Test operation should not have failed");
    if (!SRAutobahnIsValidResultBehavior(identifier, resultInfo[@"behavior"])) {
        XCTFail(@"Invalid test behavior %@ for %@.", resultInfo[@"behavior"], identifier);
    }
}

@end
