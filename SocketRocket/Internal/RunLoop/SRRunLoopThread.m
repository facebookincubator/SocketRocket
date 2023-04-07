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

#import "SRRunLoopThread.h"
#import <pthread.h>
@interface SRRunLoopThread ()

@property (nonatomic, strong, readwrite) NSRunLoop *runLoop;

@property (assign, nonatomic) pthread_mutex_t lock;
@property (assign, nonatomic) pthread_cond_t cond;
@end

@implementation SRRunLoopThread
- (void)dealloc {
    // 不用需要销毁
    pthread_mutex_destroy(&_lock);
    pthread_cond_destroy(&_cond);
}
- (void)__initMutex:(pthread_mutex_t *)mutex {

    // 1.初始化属性
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    /*
     * Mutex type attributes
     */
    //    #define PTHREAD_MUTEX_NORMAL        0
    //    #define PTHREAD_MUTEX_ERRORCHECK    1
    //    #define PTHREAD_MUTEX_RECURSIVE        2
    //    #define PTHREAD_MUTEX_DEFAULT        PTHREAD_MUTEX_NORMAL
    
    //    pthread_mutexattr_settype(&attr, NULL); 传空，默认 PTHREAD_MUTEX_DEFAULT
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    
    // 2.初始化锁
    pthread_mutex_init(mutex, &attr);
    
    // 3.销毁属性
    pthread_mutexattr_destroy(&attr);
    
    // 初始化条件
    pthread_cond_init(&_cond, NULL);
    // 加锁
    pthread_mutex_lock(mutex);
}

+ (instancetype)sharedThread
{
    static SRRunLoopThread *thread;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        thread = [[SRRunLoopThread alloc] init];
        thread.name = @"com.facebook.SocketRocket.NetworkThread";
        [thread start];
    });
    return thread;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self __initMutex:&_lock];
    }
    return self;
}

- (void)main
{
    
    @autoreleasepool {
        _runLoop = [NSRunLoop currentRunLoop];
        // 激活一个等待该条件的线程
        pthread_cond_signal(&_cond);
        // Add an empty run loop source to prevent runloop from spinning.
        CFRunLoopSourceContext sourceCtx = {
            .version = 0,
            .info = NULL,
            .retain = NULL,
            .release = NULL,
            .copyDescription = NULL,
            .equal = NULL,
            .hash = NULL,
            .schedule = NULL,
            .cancel = NULL,
            .perform = NULL
        };
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &sourceCtx);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);
        
        while ([_runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {
            
        }
        assert(NO);
    }
}

- (NSRunLoop *)runLoop;
{
    // 等待条件（进入休眠，放开mutex锁；被唤醒后，会再次对mutex加锁）
    pthread_cond_wait(&_cond, &_lock);
    return _runLoop;
}

@end
