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

#include <Security/SecureTransport.h>

#include "DispatchIO.h"
#include "DispatchData.h"
#include "SecureIO.h"

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

- (void)testDialTLS;
{
    SecureIO *raw_io = nullptr;
    bool finished = false;
    
    auto cleanupBlock = [&finished, raw_io](int error) {
        dispatch_async(dispatch_get_main_queue(), [raw_io]{
            delete raw_io;
        });
        NSLog(@"FINISHED");
        finished = true;
    };
    
    SSLContextRef ctx = SSLCreateContext(CFAllocatorGetDefault(), kSSLClientSide, kSSLStreamType);
    
    DialTLS("localhost", "10248", ctx, dispatch_get_main_queue(), dispatch_get_main_queue(), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), [&raw_io, self, &finished](squareup::dispatch::SecureIO *io, int error, const char *error_message) {
        
        STAssertEquals(error, 0, @"Should not have errored, but got %s", error_message);
        STAssertTrue(io != nullptr, @"io should be valid");
        
        if (!io) {
            finished = true;
            return;
        }
        
        raw_io = io;
        
        __block bool seenInner = false;
        __block bool seenOuter = false;
//        
//        raw_io->Write(Data("HELLO THERE!\n", dispatch_get_main_queue()), ^(bool done, dispatch_data_t data, int error) {
//            STAssertEquals(error, 0, @"Error should == 0");
//            STAssertFalse(seenOuter, @"Should only see the outer once");
//            if (done) {
//                seenOuter = true;
//            }
//            if (done && !error) {
//                
//            }
//        });
//        
//        raw_io->Write(Data("HELLO THERE2!\n", dispatch_get_main_queue()), ^(bool done, dispatch_data_t data, int error) {
//            STAssertFalse(seenInner, @"Shouldn't have seen inner yet");
//            if (done) {
//                seenInner = done;
//            }
//            STAssertEquals(error, 0, @"Error should == 0");
//            STAssertFalse(finished, @"Shouldn't have finished");
//        });
        
        
        raw_io->Read(INT_MAX, ^(bool done, dispatch_data_t data, int error) {
            if (!error) {
                raw_io->Write(data, ^(bool done, dispatch_data_t data, int error) {
                    
                });
            } else {
                STAssertTrue(error == ECANCELED, @"Server should terminate");
                
                if (done && !error) {
                    raw_io->Close(0);
                }    
            }
        });
        
    }, cleanupBlock);
    
    [self runCurrentRunLoopUntilTestPasses:[&finished](){
        return (BOOL)finished;
    } timeout:100.0];
}

@end
