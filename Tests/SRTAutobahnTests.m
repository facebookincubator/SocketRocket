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

#import <SocketRocket/SRWebSocket.h>

#import "SRTWebSocketOperation.h"
#import "SRAutobahnOperation.h"
#import "XCTestCase+SRTAdditions.h"

#define SRLogDebug(format, ...)
//#define SRLogDebug(format, ...) NSLog(format, __VA_ARGS__)

@interface SRTAutobahnTests : XCTestCase
@end

@interface NSInvocation (SRTBlockInvocation)

+ (NSInvocation *)invocationWithBlock:(dispatch_block_t)block;

@end

@interface SRTBlockInvoker

- (instancetype)initWithBlock:(dispatch_block_t)block;

- (void)invoke;

@end

@implementation SRTAutobahnTests {
    SRWebSocket *_curWebSocket;
    NSInteger _testCount;
    NSInteger _curTest;
    NSMutableArray *_sockets;
    NSString *_testURLString;
    NSURL *_prefixURL;
    NSString *_agent;
    NSString *_description;
}

- (instancetype)initWithInvocation:(NSInvocation *)anInvocation description:(NSString *)description;
{
    self = [self initWithInvocation:anInvocation];
    if (self) {
        _description = description;
    }
    return self;
}

- (instancetype)initWithInvocation:(NSInvocation *)anInvocation;
{
    self = [super initWithInvocation:anInvocation];
    if (self) {
        _testURLString = [[NSProcessInfo processInfo].environment objectForKey:@"SR_TEST_URL"];
        _prefixURL = [NSURL URLWithString:_testURLString];
        _agent = [NSBundle bundleForClass:[self class]].bundleIdentifier;
    }
    return self;
}

- (NSUInteger)testCaseCount;
{
    if (self.invocation) {
        return [super testCaseCount];
    }

    __block NSUInteger count = 0;
    SRAutobahnOperation *caseGetter = SRAutobahnTestCaseCountOperation(_prefixURL, _agent, ^(NSInteger caseCount) {
        count = caseCount;
    });
    [caseGetter start];

    [self runCurrentRunLoopUntilTestPasses:^BOOL{
        return caseGetter.isFinished;
    } timeout:20.0];

    XCTAssertNil(caseGetter.error, @"CaseGetter should have successfully returned the number of testCases. Instead got error %@", caseGetter.error);
    return count;
}

- (BOOL)isEmpty;
{
    return NO;
}

- (void)performTest:(XCTestCaseRun *) aRun
{
    if (self.invocation) {
        [super performTest:aRun];
        return;
    }
    [aRun start];
    for (NSUInteger i = 1; i <= aRun.test.testCaseCount; i++) {
        SEL sel = @selector(performTestWithNumber:);
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:sel]];

        invocation.selector = sel;
        invocation.target = self;

        [invocation setArgument:&i atIndex:2];

        NSString *description = [self caseDescriptionForCaseNumber:i];

        XCTestCase *testCase = [[[self class] alloc] initWithInvocation:invocation description:description];

        XCTestCaseRun *run = [[XCTestCaseRun alloc] initWithTest:testCase];

        [testCase performTest:run];
    }
    [aRun stop];

    [self updateReports];
}

- (NSInteger)testNum;
{
    NSInteger i;
    [self.invocation getArgument:&i atIndex:2];
    return i;
}

- (NSString *)caseDescriptionForCaseNumber:(NSInteger)caseNumber;
{
    __block NSDictionary *caseInfo = nil;
    SRAutobahnOperation *testInfoOperation = SRAutobahnTestCaseInfoOperation(_prefixURL, caseNumber, ^(NSDictionary * _Nullable caseInfo) {
        caseInfo = caseInfo;
    });

    [testInfoOperation start];

    [self runCurrentRunLoopUntilTestPasses:^BOOL{
        return testInfoOperation.isFinished;
    } timeout:60 * 60];

    XCTAssertNil(testInfoOperation.error, @"Updating the report should not have errored");

    return [NSString stringWithFormat:@"%@ - %@", caseInfo[@"id"], caseInfo[@"description"]];
}

- (NSString *)description;
{
    if (_description) {
        return _description;
    } else {
        return @"Autobahn Test Harness";
    }
}

+ (id) defaultTestSuite
{
    return [[[self class] alloc] init];
}

- (void)performTestWithNumber:(NSInteger)testNumber;
{
    NSOperationQueue *testQueue = [[NSOperationQueue alloc] init];

    testQueue.maxConcurrentOperationCount = 1;

    SRAutobahnOperation *testOp = SRAutobahnTestOperation(_prefixURL, testNumber, _agent);
    [testQueue addOperation:testOp];

    __block NSDictionary *resultInfo = nil;

    SRAutobahnOperation *resultOp = SRAutobahnTestResultOperation(_prefixURL, testNumber, _agent, ^(NSDictionary * _Nullable result) {
        resultInfo = result;
    });
    [resultOp addDependency:testOp];
    [testQueue addOperation:resultOp];

    testQueue.suspended = NO;

    [self runCurrentRunLoopUntilTestPasses:^BOOL{
        return resultOp.isFinished;
    } timeout:60 * 60];

    XCTAssertTrue(!testOp.error, @"Test operation should not have failed");
    XCTAssertEqualObjects(@"OK", resultInfo[@"behavior"], @"Test behavior should be OK");
}

- (void)updateReports
{
    SRAutobahnOperation *operation = SRAutobahnTestUpdateReportsOperation(_prefixURL, _agent);
    [operation start];

    [self runCurrentRunLoopUntilTestPasses:^BOOL{
        return operation.isFinished;
    } timeout:60 * 60];

    XCTAssertNil(operation.error, @"Updating the report should not have errored");
}

@end
