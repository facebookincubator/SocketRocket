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

#import "SenTestCase+SRTAdditions.h"


@implementation XCTestCase (SRTAdditions)

- (void)runCurrentRunLoopUntilTestPasses:(PXPredicateBlock)predicate timeout:(NSTimeInterval)timeout;
{
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeout];
    
    NSTimeInterval timeoutTime = [timeoutDate timeIntervalSinceReferenceDate];
    NSTimeInterval currentTime;
    
    for (currentTime = [NSDate timeIntervalSinceReferenceDate];
         !predicate() && currentTime < timeoutTime;
         currentTime = [NSDate timeIntervalSinceReferenceDate]) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    
    XCTAssertTrue(currentTime <= timeoutTime, @"Timed out");
}

@end
