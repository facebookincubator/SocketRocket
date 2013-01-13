//
//  STRDispatchTest.m
//  SocketRocket
//
//  Created by Michael Lewis on 1/12/13.
//
//
extern "C" {
#import <SenTestingKit/SenTestingKit.h>
}

#include "DispatchChannel.h"

using namespace squareup::dispatch;

@interface STRDispatchTest : SenTestCase

@end


@implementation STRDispatchTest

- (void)testConnect;
{
    bool finished = false;
    dispatch_queue_t workQueue = dispatch_queue_create("dispatch queue", DISPATCH_QUEUE_SERIAL);
    
    Dial(workQueue, "localhost", "9932", dispatch_get_main_queue(), [&](dispatch_fd_t fd, int error_code, const char *error_message) {
        NSLog(@"code: %d, msg: %s", error_code, error_message);
        STAssertEquals(error_code, 0, @"Should not error but got %s", error_message);
        finished = true;
    });
    
    [self runCurrentRunLoopUntilTestPasses:[&finished](){
        return (BOOL)finished;
    } timeout:100.0];
}

@end
