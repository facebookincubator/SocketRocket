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

#import <XCTest/XCTest.h>


typedef BOOL (^PXPredicateBlock)();


@interface XCTest (PXAdditions)

- (void)runCurrentRunLoopUntilTestPasses:(PXPredicateBlock)predicate timeout:(NSTimeInterval)timeout;

@end
