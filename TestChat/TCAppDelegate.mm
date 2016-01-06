//
//  TCAppDelegate.m
//  TestChat
//
//  Created by Mike Lewis on 1/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "TCAppDelegate.h"
#import <Security/SecureTransport.h>

#import "SecureIO.h"
#import <string>

using namespace squareup::dispatch;

@implementation TCAppDelegate {
    SecureIO *_io;
}

@synthesize window = _window;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    /*
     Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
     Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
     */
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    /*
     Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
     If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
     */
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    /*
     Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
     */
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    SSLContextRef ctx = SSLCreateContext(CFAllocatorGetDefault(), kSSLClientSide, kSSLStreamType);
    
    auto finishBlock = [self](int error) {
        NSLog(@"Done");
    };
    
    dispatch_queue_t workQueue = dispatch_queue_create("squareup.dispatch work queue", DISPATCH_QUEUE_SERIAL);
    
    DialTLS("localhost", "10248", ctx, dispatch_get_main_queue(), workQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), [self, _cmd](squareup::dispatch::SecureIO *io, int error, const char *error_message) {
        
        NSAssert(error == 0, @"Should not have errored, but got %s", error_message);
        NSAssert(io != nullptr, @"io should be valid");
        
        if (!io) {
            return;
        }
        
        _io = io;
        
//        __block bool seenInner = false;
//        __block bool seenOuter = false;
//
//        _io->Write(Data("HELLO THERE!\n", dispatch_get_main_queue()), ^(bool done, dispatch_data_t data, int error) {
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
//        _io->Write(Data("HELLO THERE2!\n", dispatch_get_main_queue()), ^(bool done, dispatch_data_t data, int error) {
//            STAssertFalse(seenInner, @"Shouldn't have seen inner yet");
//            if (done) {
//                seenInner = done;
//            }
//            STAssertEquals(error, 0, @"Error should == 0");
//            STAssertFalse(finished, @"Shouldn't have finished");
//        });

        
        for (int i = 0; i < 4096; i++) {

            _io->Read(1024 * 1024* 13, dispatch_get_main_queue(), [self, _cmd, i](bool readDone, dispatch_data_t data, int error) {
                if (!error) {
                    
                    _io->Write(data, dispatch_get_main_queue(), [self, readDone, i](bool done, dispatch_data_t data, int error) {
                    });
                } else {
                    NSAssert(error == ECANCELED, @"Server should terminate");
                    
                    if (readDone && !error) {
                        _io->Close(0);
                    }
                }
            });
        }
        
    }, finishBlock);

    /*
     Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
     */
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    /*
     Called when the application is about to terminate.
     Save data if appropriate.
     See also applicationDidEnterBackground:.
     */
}

@end
