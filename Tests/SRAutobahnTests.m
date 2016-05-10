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
#import "SRAutobahnUtilities.h"

@interface SRAutobahnTests : XCTestCase
@end

@implementation SRAutobahnTests

///--------------------------------------
#pragma mark - Init
///--------------------------------------

/**
 This method is called if Xcode is targeting a specific test or a set of them.
 If you change this method - please make sure you test this behavior in Xcode by running all tests, then running 1+ test.
 */
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

/**
 This method is called by xctest to figure out all the tests that are available.
 All the selector names are also reported back to Xcode and displayed in Test Navigator/Console.
 */
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

+ (void)updateReports
{
    SRAutobahnOperation *operation = SRAutobahnTestUpdateReportsOperation(SRAutobahnTestServerURL(), SRAutobahnTestAgentName());
    [operation start];

    NSAssert([operation waitUntilFinishedWithTimeout:60], @"Timed out on updating reports.");
    NSAssert(!operation.error, @"Updating the report should not have errored %@", operation.error);
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


    XCTAssertTrue([resultOp waitUntilFinishedWithTimeout:60 * 5], @"Test operation timed out.");
    XCTAssertTrue(!testOp.error, @"Test operation should not have failed");
    if (!SRAutobahnIsValidResultBehavior(identifier, resultInfo[@"behavior"])) {
        XCTFail(@"Invalid test behavior %@ for %@.", resultInfo[@"behavior"], identifier);
    }
}

@end
