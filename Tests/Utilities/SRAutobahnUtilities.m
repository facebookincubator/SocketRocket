//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "SRAutobahnUtilities.h"

#import "SRAutobahnOperation.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRAutobahnUtilities : NSObject @end
@implementation SRAutobahnUtilities @end

///--------------------------------------
#pragma mark - Test Configuration
///--------------------------------------

NSString *SRAutobahnTestAgentName(void)
{
    return [NSBundle bundleForClass:[SRAutobahnUtilities class]].bundleIdentifier;
}

NSURL *SRAutobahnTestServerURL(void)
{
    return [NSURL URLWithString:@"ws://localhost:9001"];
}

///--------------------------------------
#pragma mark - Validation
///--------------------------------------

NSDictionary<NSString *, id> *SRAutobahnTestConfiguration(void)
{
    static NSDictionary *configuration;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *configurationURL = [[NSBundle bundleForClass:[SRAutobahnUtilities class]] URLForResource:@"autobahn_configuration"
                                                                                          withExtension:@"json"];
        NSInputStream *readStream = [NSInputStream inputStreamWithURL:configurationURL];
        [readStream open];
        configuration = [NSJSONSerialization JSONObjectWithStream:readStream options:0 error:nil];
        [readStream close];
    });
    return configuration;
}

BOOL SRAutobahnIsValidResultBehavior(NSString *caseIdentifier, NSString *behavior)
{
    if ([behavior isEqualToString:@"OK"]) {
        return YES;
    }

    NSArray *cases = SRAutobahnTestConfiguration()[behavior];
    for (NSString *caseId in cases) {
        if ([caseIdentifier hasPrefix:caseId]) {
            return YES;
        }
    }
    return NO;
}

///--------------------------------------
#pragma mark - Utilities
///--------------------------------------

BOOL SRRunLoopRunUntil(BOOL (^predicate)(), NSTimeInterval timeout)
{
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeout];

    NSTimeInterval timeoutTime = [timeoutDate timeIntervalSinceReferenceDate];
    NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];

    while (!predicate() && currentTime < timeoutTime) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        currentTime = [NSDate timeIntervalSinceReferenceDate];
    }
    return (currentTime <= timeoutTime);
}

///--------------------------------------
#pragma mark - Setup
///--------------------------------------

NSUInteger SRAutobahnTestCaseCount(void)
{
    static NSUInteger count;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SRAutobahnOperation *operation = SRAutobahnTestCaseCountOperation(SRAutobahnTestServerURL(),
                                                                           SRAutobahnTestAgentName(),
                                                                           ^(NSInteger caseCount) {
                                                                               count = caseCount;
                                                                           });
        [operation start];

        NSCAssert([operation waitUntilFinishedWithTimeout:10], @"Timed out fetching test case count.");
        NSCAssert(!operation.error, @"CaseGetter should have successfully returned the number of testCases. Instead got error %@", operation.error);
    });
    return count;
}

NSDictionary<NSString *, id> *SRAutobahnTestCaseInfo(NSInteger caseNumber)
{
    __block NSDictionary *caseInfo = nil;
    SRAutobahnOperation *operation = SRAutobahnTestCaseInfoOperation(SRAutobahnTestServerURL(), caseNumber, ^(NSDictionary * _Nullable info) {
        caseInfo = info;
    });
    [operation start];

    NSCAssert([operation waitUntilFinishedWithTimeout:10], @"Timed out fetching test case info %ld.", (long)caseNumber);
    NSCAssert(!operation.error, @"Updating the report should not have errored");
    return caseInfo;
}

NS_ASSUME_NONNULL_END
