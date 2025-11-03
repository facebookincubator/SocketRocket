//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "SRProxyConnect.h"

#import "NSRunLoop+SRWebSocket.h"
#import "SRConstants.h"
#import "SRError.h"
#import "SRLog.h"
#import "SRURLUtilities.h"

@interface SRProxyConnect() <NSStreamDelegate>

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;

@end

@implementation SRProxyConnect
{
    SRProxyConnectCompletion _completion;

    NSString *_httpProxyHost;
    uint32_t _httpProxyPort;

    CFHTTPMessageRef _receivedHTTPHeaders;

    NSString *_socksProxyHost;
    uint32_t _socksProxyPort;
    NSString *_socksProxyUsername;
    NSString *_socksProxyPassword;

    BOOL _connectionRequiresSSL;

    NSMutableArray<NSData *> *_inputQueue;
    dispatch_queue_t _writeQueue;
}

///--------------------------------------
#pragma mark - Init
///--------------------------------------

-(instancetype)initWithURL:(NSURL *)url
{
    self = [super init];
    if (!self) return self;

    _url = url;
    _connectionRequiresSSL = SRURLRequiresSSL(url);

    _writeQueue = dispatch_queue_create("com.facebook.socketrocket.proxyconnect.write", DISPATCH_QUEUE_SERIAL);
    _inputQueue = [NSMutableArray arrayWithCapacity:2];

    _receivedHTTPHeaders = NULL;

    return self;
}

- (void)dealloc
{
    // If we get deallocated before the socket open finishes - we need to cleanup everything.

    // Remove streams from runloop and close them
    @synchronized(self) {
        if (self.inputStream) {
            self.inputStream.delegate = nil;
            [self.inputStream removeFromRunLoop:[NSRunLoop SR_networkRunLoop] forMode:NSDefaultRunLoopMode];
            [self.inputStream close];
            self.inputStream = nil;
        }
        if (self.outputStream) {
            self.outputStream.delegate = nil;
            [self.outputStream removeFromRunLoop:[NSRunLoop SR_networkRunLoop] forMode:NSDefaultRunLoopMode];
            [self.outputStream close];
            self.outputStream = nil;
        }

        // Clear input queue
        [_inputQueue removeAllObjects];
    }

    // Release any pending CF object
    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }
}

///--------------------------------------
#pragma mark - Open
///--------------------------------------

- (void)openNetworkStreamWithCompletion:(SRProxyConnectCompletion)completion
{
    _completion = completion;
    [self _configureProxy];
}

///--------------------------------------
#pragma mark - Flow
///--------------------------------------

- (void)_didConnect
{
    SRDebugLog(@"_didConnect, return streams");

    if (_connectionRequiresSSL) {
        if (_httpProxyHost) {
            // Must set the real peer name before turning on SSL
            SRDebugLog(@"proxy set peer name to real host %@", self.url.host);
            // Use CF property key for peer name if desired. The original code used a string.
            [self.outputStream setProperty:self.url.host forKey:(id)kCFStreamPropertySocketPeerName];
        }
    }

    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }

    NSInputStream *inputStream = self.inputStream;
    NSOutputStream *outputStream = self.outputStream;

    // Clear properties before returning streams
    self.inputStream = nil;
    self.outputStream = nil;

    if (inputStream) {
        [inputStream removeFromRunLoop:[NSRunLoop SR_networkRunLoop] forMode:NSDefaultRunLoopMode];
        inputStream.delegate = nil;
    }
    if (outputStream) {
        [outputStream removeFromRunLoop:[NSRunLoop SR_networkRunLoop] forMode:NSDefaultRunLoopMode];
        outputStream.delegate = nil;
    }

    if (_completion) {
        _completion(nil, inputStream, outputStream);
    }
}

- (void)_failWithError:(NSError *)error
{
    SRDebugLog(@"_failWithError, return error");
    if (!error) {
        error = SRHTTPErrorWithCodeDescription(500, 2132,@"Proxy Error");
    }

    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }

    // Remove delegates and close streams safely
    @synchronized(self) {
        if (self.inputStream) {
            self.inputStream.delegate = nil;
            [self.inputStream removeFromRunLoop:[NSRunLoop SR_networkRunLoop] forMode:NSDefaultRunLoopMode];
            [self.inputStream close];
            self.inputStream = nil;
        }
        if (self.outputStream) {
            self.outputStream.delegate = nil;
            [self.outputStream removeFromRunLoop:[NSRunLoop SR_networkRunLoop] forMode:NSDefaultRunLoopMode];
            [self.outputStream close];
            self.outputStream = nil;
        }

        // Clear queued input
        [_inputQueue removeAllObjects];
    }

    if (_completion) {
        _completion(error, nil, nil);
    }
}

// get proxy setting from device setting
- (void)_configureProxy
{
    SRDebugLog(@"configureProxy");
    NSDictionary *proxySettings = CFBridgingRelease(CFNetworkCopySystemProxySettings());

    // CFNetworkCopyProxiesForURL doesn't understand ws:// or wss://
    NSURL *httpURL;
    if (_connectionRequiresSSL) {
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", _url.host]];
    } else {
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", _url.host]];
    }

    NSArray *proxies = CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)httpURL, (__bridge CFDictionaryRef)proxySettings));
    if (proxies.count == 0) {
        SRDebugLog(@"configureProxy no proxies");
        [self _openConnection];
        return;                 // no proxy
    }
    NSDictionary *settings = [proxies objectAtIndex:0];
    NSString *proxyType = settings[(NSString *)kCFProxyTypeKey];
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeAutoConfigurationURL]) {
        NSURL *pacURL = settings[(NSString *)kCFProxyAutoConfigurationURLKey];
        if (pacURL) {
            [self _fetchPAC:pacURL withProxySettings:proxySettings];
            return;
        }
    }
    if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeAutoConfigurationJavaScript]) {
        NSString *script = settings[(__bridge NSString *)kCFProxyAutoConfigurationJavaScriptKey];
        if (script) {
            [self _runPACScript:script withProxySettings:proxySettings];
            return;
        }
    }
    [self _readProxySettingWithType:proxyType settings:settings];

    [self _openConnection];
}

- (void)_readProxySettingWithType:(NSString *)proxyType settings:(NSDictionary *)settings
{
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeHTTP] ||
        [proxyType isEqualToString:(NSString *)kCFProxyTypeHTTPS]) {
        _httpProxyHost = settings[(NSString *)kCFProxyHostNameKey];
        NSNumber *portValue = settings[(NSString *)kCFProxyPortNumberKey];
        if (portValue) {
            _httpProxyPort = (uint32_t)[portValue unsignedIntValue];
        }
    }
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeSOCKS]) {
        _socksProxyHost = settings[(NSString *)kCFProxyHostNameKey];
        NSNumber *portValue = settings[(NSString *)kCFProxyPortNumberKey];
        if (portValue)
            _socksProxyPort = (uint32_t)[portValue unsignedIntValue];
        _socksProxyUsername = settings[(NSString *)kCFProxyUsernameKey];
        _socksProxyPassword = settings[(NSString *)kCFProxyPasswordKey];
    }
    if (_httpProxyHost) {
        SRDebugLog(@"Using http proxy %@:%u", _httpProxyHost, _httpProxyPort);
    } else if (_socksProxyHost) {
        SRDebugLog(@"Using socks proxy %@:%u", _socksProxyHost, _socksProxyPort);
    } else {
        SRDebugLog(@"configureProxy no proxies");
    }
}

- (void)_fetchPAC:(NSURL *)PACurl withProxySettings:(NSDictionary *)proxySettings
{
    SRDebugLog(@"SRWebSocket fetchPAC:%@", PACurl);

    if ([PACurl isFileURL]) {
        NSError *error = nil;
        NSString *script = [NSString stringWithContentsOfURL:PACurl
                                                usedEncoding:NULL
                                                       error:&error];

        if (error) {
            [self _openConnection];
        } else {
            [self _runPACScript:script withProxySettings:proxySettings];
        }
        return;
    }

    NSString *scheme = [PACurl.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        // Don't know how to read data from this URL, we'll have to give up
        // We'll simply assume no proxies, and start the request as normal
        [self _openConnection];
        return;
    }
    __weak typeof(self) wself = self;
    NSURLRequest *request = [NSURLRequest requestWithURL:PACurl];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        if (!error) {
            NSString *script = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [sself _runPACScript:script withProxySettings:proxySettings];
        } else {
            [sself _openConnection];
        }
    }] resume];
}

- (void)_runPACScript:(NSString *)script withProxySettings:(NSDictionary *)proxySettings
{
    if (!script) {
        [self _openConnection];
        return;
    }
    SRDebugLog(@"runPACScript");
    // From: http://developer.apple.com/samplecode/CFProxySupportTool/listing1.html
    // Work around <rdar://problem/5530166>.  This dummy call to
    // CFNetworkCopyProxiesForURL initialise some state within CFNetwork
    // that is required by CFNetworkCopyProxiesForAutoConfigurationScript.
    CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)_url, (__bridge CFDictionaryRef)proxySettings));

    // Obtain the list of proxies by running the autoconfiguration script
    CFErrorRef err = NULL;

    // CFNetworkCopyProxiesForAutoConfigurationScript doesn't understand ws:// or wss://
    NSURL *httpURL;
    if (_connectionRequiresSSL)
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", _url.host]];
    else
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", _url.host]];

    NSArray *proxies = CFBridgingRelease(CFNetworkCopyProxiesForAutoConfigurationScript((__bridge CFStringRef)script,(__bridge CFURLRef)httpURL, &err));
    if (!err && [proxies count] > 0) {
        NSDictionary *settings = [proxies objectAtIndex:0];
        NSString *proxyType = settings[(NSString *)kCFProxyTypeKey];
        [self _readProxySettingWithType:proxyType settings:settings];
    }
    [self _openConnection];
}

- (void)_openConnection
{
    [self _initializeStreams];

    // Schedule both streams on the SR network run loop
    if (self.inputStream) {
        [self.inputStream scheduleInRunLoop:[NSRunLoop SR_networkRunLoop] forMode:NSDefaultRunLoopMode];
    }
    if (self.outputStream) {
        [self.outputStream scheduleInRunLoop:[NSRunLoop SR_networkRunLoop] forMode:NSDefaultRunLoopMode];
    }

    [self.outputStream open];
    [self.inputStream open];
}

- (void)_initializeStreams
{
    assert(_url.port.unsignedIntValue <= UINT32_MAX);
    uint32_t port = _url.port.unsignedIntValue;
    if (port == 0) {
        port = (_connectionRequiresSSL ? 443 : 80);
    }
    NSString *host = _url.host;

    if (_httpProxyHost) {
        host = _httpProxyHost;
        port = (_httpProxyPort ?: 80);
    }

    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;

    SRDebugLog(@"ProxyConnect connect stream to %@:%u", host, port);
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, port, &readStream, &writeStream);

    self.outputStream = CFBridgingRelease(writeStream);
    self.inputStream = CFBridgingRelease(readStream);

    if (_socksProxyHost) {
        SRDebugLog(@"ProxyConnect set sock property stream to %@:%u user %@ password %@", _socksProxyHost, _socksProxyPort, _socksProxyUsername, _socksProxyPassword);
        NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithCapacity:4];
        settings[NSStreamSOCKSProxyHostKey] = _socksProxyHost;
        if (_socksProxyPort) {
            settings[NSStreamSOCKSProxyPortKey] = @(_socksProxyPort);
        }
        if (_socksProxyUsername) {
            settings[NSStreamSOCKSProxyUserKey] = _socksProxyUsername;
        }
        if (_socksProxyPassword) {
            settings[NSStreamSOCKSProxyPasswordKey] = _socksProxyPassword;
        }
        [self.inputStream setProperty:settings forKey:NSStreamSOCKSProxyConfigurationKey];
        [self.outputStream setProperty:settings forKey:NSStreamSOCKSProxyConfigurationKey];
    }
    self.inputStream.delegate = self;
    self.outputStream.delegate = self;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    SRDebugLog(@"stream handleEvent %u", eventCode);
    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            if (aStream == self.inputStream) {
                if (_httpProxyHost) {
                    [self _proxyDidConnect];
                } else {
                    [self _didConnect];
                }
            }
            break;
        }
        case NSStreamEventErrorOccurred: {
            [self _failWithError:aStream.streamError];
            break;
        }
        case NSStreamEventEndEncountered: {
            [self _failWithError:aStream.streamError];
            break;
        }
        case NSStreamEventHasBytesAvailable: {
            if (aStream == _inputStream) {
                [self _processInputStream];
            }
            break;
        }
        case NSStreamEventHasSpaceAvailable:
        case NSStreamEventNone:
            SRDebugLog(@"(default)  %@", aStream);
            break;
    }
}

- (void)_proxyDidConnect
{
    SRDebugLog(@"Proxy Connected");
    uint32_t port = _url.port.unsignedIntValue;
    if (port == 0) {
        port = (_connectionRequiresSSL ? 443 : 80);
    }
    // Send HTTP CONNECT Request
    NSString *connectRequestStr = [NSString stringWithFormat:@"CONNECT %@:%u HTTP/1.1\r\nHost: %@\r\nConnection: keep-alive\r\nProxy-Connection: keep-alive\r\n\r\n", _url.host, port, _url.host];

    NSData *message = [connectRequestStr dataUsingEncoding:NSUTF8StringEncoding];
    SRDebugLog(@"Proxy sending %@", connectRequestStr);

    [self _writeData:message];
}

///handles the incoming bytes and sending them to the proper processing method
- (void)_processInputStream
{
    // Read up to default buffer size into a stack buffer to avoid mutableBytes issues
    const NSInteger bufSize = SRDefaultBufferSize();
    uint8_t buffer[bufSize];
    NSInteger length = [self.inputStream read:buffer maxLength:bufSize];

    if (length <= 0) {
        return;
    }

    NSData *readData = [NSData dataWithBytes:buffer length:(NSUInteger)length];

    BOOL shouldProcess = NO;
    @synchronized(self) {
        shouldProcess = (_inputQueue.count == 0);
        [_inputQueue addObject:readData];
    }

    if (shouldProcess) {
        [self _dequeueInput];
    }
}

// dequeue the incoming input so it is processed in order
- (void)_dequeueInput
{
    while (true) {
        NSData *data = nil;
        @synchronized(self) {
            if (_inputQueue.count == 0) {
                data = nil;
            } else {
                data = _inputQueue.firstObject;
                [_inputQueue removeObjectAtIndex:0];
            }
        }

        if (!data) {
            break;
        }

        // No need to process any data further, we got the full header data.
        BOOL headerComplete = [self _proxyProcessHTTPResponseWithData:data];
        if (headerComplete) {
            // Stop processing further queued data now; remaining data (if any) will be handled by upper layer after connect
            break;
        }
    }
}
//handle checking the proxy  connection status
- (BOOL)_proxyProcessHTTPResponseWithData:(NSData *)data
{
    if (_receivedHTTPHeaders == NULL) {
        _receivedHTTPHeaders = CFHTTPMessageCreateEmpty(NULL, NO);
    }

    CFHTTPMessageAppendBytes(_receivedHTTPHeaders, (const UInt8 *)data.bytes, (CFIndex)data.length);
    if (CFHTTPMessageIsHeaderComplete(_receivedHTTPHeaders)) {
        CFDictionaryRef headers = CFHTTPMessageCopyAllHeaderFields(_receivedHTTPHeaders);
        SRDebugLog(@"Finished reading headers %@", CFBridgingRelease(headers));
        [self _proxyHTTPHeadersDidFinish];
        return YES;
    }

    return NO;
}

- (void)_proxyHTTPHeadersDidFinish
{
    NSInteger responseCode = CFHTTPMessageGetResponseStatusCode(_receivedHTTPHeaders);

    if (responseCode >= 299) {
        SRDebugLog(@"Connect to Proxy Request failed with response code %ld", (long)responseCode);
        NSError *error = SRHTTPErrorWithCodeDescription((NSInteger)responseCode, 2132,
                                                        [NSString stringWithFormat:@"Received bad response code from proxy server: %ld.",
                                                         (long)responseCode]);
        [self _failWithError:error];
        return;
    }
    SRDebugLog(@"proxy connect return %ld, call socket connect", (long)responseCode);
    [self _didConnect];
}

static NSTimeInterval const SRProxyConnectWriteTimeout = 5.0;

- (void)_writeData:(NSData *)data
{
    const uint8_t *bytes = data.bytes;
    // Use microseconds for usleep; convert timeout to microseconds
    __block NSInteger timeoutMicros = (NSInteger)(SRProxyConnectWriteTimeout * 1000000.0); // microseconds
    __weak typeof(self) wself = self;
    dispatch_async(_writeQueue, ^{
        __strong typeof(wself) sself = wself;
        if (!sself) {
            return;
        }
        NSOutputStream *outStream = sself.outputStream;
        if (!outStream) {
            return;
        }

        while (![outStream hasSpaceAvailable]) {
            // sleep for 1000 microseconds (1ms) to reduce busy-waiting
            usleep(1000);
            timeoutMicros -= 1000;
            if (timeoutMicros <= 0) {
                NSError *error = SRHTTPErrorWithCodeDescription(408, 2132, @"Proxy timeout");
                [sself _failWithError:error];
                return; // ensure we break out after failure
            } else if (outStream.streamError != nil) {
                [sself _failWithError:outStream.streamError];
                return; // ensure we break out after failure
            }
        }

        NSInteger written = [outStream write:bytes maxLength:(NSInteger)data.length];
        if (written < 0) {
            if (outStream.streamError) {
                [sself _failWithError:outStream.streamError];
            } else {
                NSError *error = SRHTTPErrorWithCodeDescription(500, 2132, @"Write failed");
                [sself _failWithError:error];
            }
        } else if (written < (NSInteger)data.length) {
            SRDebugLog(@"Partial write %ld of %lu bytes", (long)written, (unsigned long)data.length);
            // For a partial write, attempt to write remaining bytes (simple loop, guarded by timeout)
            const uint8_t *remainingPtr = bytes + written;
            NSInteger remainingLen = (NSInteger)data.length - written;
            while (remainingLen > 0) {
                if (![outStream hasSpaceAvailable]) {
                    usleep(1000);
                    timeoutMicros -= 1000;
                    if (timeoutMicros <= 0) {
                        NSError *error = SRHTTPErrorWithCodeDescription(408, 2132, @"Proxy timeout (partial write)");
                        [sself _failWithError:error];
                        return;
                    }
                    if (outStream.streamError) {
                        [sself _failWithError:outStream.streamError];
                        return;
                    }
                    continue;
                }
                NSInteger w = [outStream write:remainingPtr maxLength:remainingLen];
                if (w < 0) {
                    if (outStream.streamError) {
                        [sself _failWithError:outStream.streamError];
                    } else {
                        NSError *error = SRHTTPErrorWithCodeDescription(500, 2132, @"Write failed (partial)");
                        [sself _failWithError:error];
                    }
                    return;
                }
                remainingPtr += w;
                remainingLen -= w;
            }
        }
    });
}

@end
