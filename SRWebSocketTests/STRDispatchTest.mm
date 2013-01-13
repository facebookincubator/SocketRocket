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
#include "DispatchData.h"

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


- (void)testSimpleDial;
{
    RawIO *raw_io = nullptr;
    bool finished = false;
    
    auto cleanupBlock = [&finished](int error) {
        finished = true;
    };

    SimpleDial("localhost", "9934", dispatch_get_main_queue(), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), [&raw_io, self, &finished](squareup::dispatch::RawIO *io, int error, const char *error_message) {
        
        STAssertEquals(error, 0, @"Should not have errored, but got %s", error_message);
        STAssertTrue(io != nullptr, @"io should be valid");
        
        
        if (!io) {
            finished = true;
            return;
        }
        raw_io = io;

        io->Write(Data("HELLO THERE!", dispatch_get_main_queue()), [self, &raw_io](bool done, dispatch_data_t data, int error) {
            STAssertEquals(error, 0, @"Error should == 0");
            if (done) {
                raw_io->Close(0);
            }
        });
        
    }, cleanupBlock);
    
    [self runCurrentRunLoopUntilTestPasses:[&finished](){
        return (BOOL)finished;
    } timeout:100.0];
}

@end
