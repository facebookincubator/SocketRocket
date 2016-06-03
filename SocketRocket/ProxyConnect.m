#import "ProxyConnect.h"
#import "SRError.h"
#import "NSRunLoop+SRWebSocket.h"

static inline void ProxyFastLog(NSString *format, ...);

typedef void (^connectDoneBlock_t)(NSError * error, NSInputStream *readStream, NSOutputStream *writeStream);

@interface ProxyConnect() <NSStreamDelegate>

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSInputStream * inputStream;
@property (nonatomic, strong) NSOutputStream * outputStream;

@end
@implementation ProxyConnect {
    
    connectDoneBlock_t  connectDoneHandler;
    
    NSString *_httpProxyHost;
    uint32_t _httpProxyPort;
    
    CFHTTPMessageRef _receivedHTTPHeaders;

    NSString *_socksProxyHost;
    uint32_t _socksProxyPort;
    NSString *_socksProxyUsername;
    NSString *_socksProxyPassword;
    
    BOOL _secure;
    
    NSMutableArray<NSData *> *_inputQueue;
    NSOperationQueue * _writeQueue;
    
}

-(instancetype)initWithURL:(NSURL *)url
{
    if ([super init]) {
        self.url = url;
        
        NSString *scheme = url.scheme.lowercaseString;
        
        if ([scheme isEqualToString:@"wss"] || [scheme isEqualToString:@"https"]) {
            _secure = YES;
        }
        
        _writeQueue =  [[NSOperationQueue alloc] init];
        _inputQueue = [NSMutableArray arrayWithCapacity:2];
    }
    return self;
}

-(void) openNetworkStreamWithCompletion:(void (^)(NSError *error, NSInputStream *readStream, NSOutputStream *writeStream ))completion
{
    connectDoneHandler = completion;
    [self _configureProxy];
}

-(void) _didConnect
{
    ProxyFastLog(@"_didConnect, return streams");
    if (_secure) {
        if (_httpProxyHost) {
            // Must set the real peer name before turning on SSL
            ProxyFastLog(@"proxy set peer name to real host %@", self.url.host);
            [self.outputStream setProperty:self.url.host forKey:@"_kCFStreamPropertySocketPeerName"];
        }
    }
    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }
    NSInputStream *inputStream = self.inputStream;
    NSOutputStream *outputStream = self.outputStream;
    self.inputStream = nil;
    self.outputStream = nil;
    [inputStream removeFromRunLoop:[NSRunLoop SR_networkRunLoop]
                           forMode:NSDefaultRunLoopMode];
    inputStream.delegate = nil;
    outputStream.delegate = nil;
    connectDoneHandler(nil, inputStream, outputStream);
}

-(void) _failWithError:(NSError *)error
{
    ProxyFastLog(@"_failWithError, return error");
    if (!error) {
        error = SRHTTPErrorWithCodeDescription(500, 2132,@"Proxy Error");
    }
    
    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }
    [self.inputStream removeFromRunLoop:[NSRunLoop SR_networkRunLoop]
                                forMode:NSDefaultRunLoopMode];
    [self.inputStream close];
    [self.outputStream close];
    self.inputStream = nil;
    self.outputStream = nil;
    connectDoneHandler(error, nil, nil);
}

// get proxy setting from device setting
-(void) _configureProxy
{
    ProxyFastLog(@"configureProxy");
    NSDictionary *proxySettings = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    // CFNetworkCopyProxiesForURL doesn't understand ws:// or wss://
    NSURL *httpURL;
    if (_secure)
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", _url.host]];
    else
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", _url.host]];
    
    NSArray *proxies = CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)httpURL, (__bridge CFDictionaryRef)proxySettings));
    if (proxies.count == 0) {
        ProxyFastLog(@"configureProxy no proxies");
        [self _openConnection];
        return;                 // no proxy
    }
    NSDictionary *settings = [proxies objectAtIndex:0];
    NSString *proxyType = settings[(NSString *)kCFProxyTypeKey];
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeAutoConfigurationURL]) {
        NSURL *pacURL = settings[(NSString *)kCFProxyAutoConfigurationURLKey];
        if (pacURL) {
            [self _fetchPAC:pacURL];
            return;
        }
    }
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeAutoConfigurationJavaScript]) {
        NSString *script = settings[(NSString *)kCFProxyAutoConfigurationJavaScriptKey];
        if (script) {
            [self _runPACScript:script];
            return;
        }
    }
    [self _readProxySettingWithType:proxyType settings:settings];

    [self _openConnection];
}

- (void) _readProxySettingWithType:(NSString *)proxyType settings:(NSDictionary *)settings
{
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeHTTP] || [proxyType isEqualToString:(NSString *)kCFProxyTypeHTTPS]) {
        _httpProxyHost = settings[(NSString *)kCFProxyHostNameKey];
        NSNumber *portValue = settings[(NSString *)kCFProxyPortNumberKey];
        if (portValue)
            _httpProxyPort = [portValue intValue];
    }
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeSOCKS]) {
        _socksProxyHost = settings[(NSString *)kCFProxyHostNameKey];
        NSNumber *portValue = settings[(NSString *)kCFProxyPortNumberKey];
        if (portValue)
            _socksProxyPort = [portValue intValue];
        _socksProxyUsername = settings[(NSString *)kCFProxyUsernameKey];
        _socksProxyPassword = settings[(NSString *)kCFProxyPasswordKey];
    }
    if (_httpProxyHost) {
        ProxyFastLog(@"Using http proxy %@:%u", _httpProxyHost, _httpProxyPort);
    } else if (_socksProxyHost) {
        ProxyFastLog(@"Using socks proxy %@:%u", _socksProxyHost, _socksProxyPort);
    } else {
        ProxyFastLog(@"configureProxy no proxies");
    }
}

- (void)_fetchPAC:(NSURL *)PACurl
{
    ProxyFastLog(@"SRWebSocket fetchPAC:%@", PACurl);
    
    if ([PACurl isFileURL]) {
        NSError *nsError = nil;
        NSString *script = [NSString stringWithContentsOfURL:PACurl
                                                usedEncoding:NULL
                                                       error:&nsError];
        
        if (nsError) {
            [self _openConnection];
            return;
        }
        [self _runPACScript:script];
        return;
    }
    
    NSString *scheme = [PACurl.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        // Don't know how to read data from this URL, we'll have to give up
        // We'll simply assume no proxies, and start the request as normal
        [self _openConnection];
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSURLRequest *request = [NSURLRequest requestWithURL:PACurl];
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:
                                  ^(NSData *data, NSURLResponse *response, NSError *error) {
                                      if (!error) {
                                          NSString* script = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                          [weakSelf _runPACScript:script];
                                      } else {
                                          [weakSelf _openConnection];
                                      }
                                      
                                  }];
    [task resume];
}

- (void)_runPACScript:(NSString *)script
{
    if (!script) {
        [self _openConnection];
        return;
    }
    ProxyFastLog(@"runPACScript");
    // From: http://developer.apple.com/samplecode/CFProxySupportTool/listing1.html
    // Work around <rdar://problem/5530166>.  This dummy call to
    // CFNetworkCopyProxiesForURL initialise some state within CFNetwork
    // that is required by CFNetworkCopyProxiesForAutoConfigurationScript.
    NSDictionary *empty;
    CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)_url, (__bridge CFDictionaryRef)empty));
    
    // Obtain the list of proxies by running the autoconfiguration script
    CFErrorRef err = NULL;
    
    // CFNetworkCopyProxiesForAutoConfigurationScript doesn't understand ws:// or wss://
    NSURL *httpURL;
    if (_secure)
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

- (void)_openConnection;
{
    [self _initializeStreams];
    
    [self.inputStream scheduleInRunLoop:[NSRunLoop SR_networkRunLoop]
                                forMode:NSDefaultRunLoopMode];
    //[self.outputStream scheduleInRunLoop:[NSRunLoop SR_networkRunLoop]
    //                           forMode:NSDefaultRunLoopMode];
    [self.outputStream open];
    [self.inputStream open];
}

- (void)_initializeStreams;
{
    assert(_url.port.unsignedIntValue <= UINT32_MAX);
    uint32_t port = _url.port.unsignedIntValue;
    if (port == 0) {
        if (!_secure) {
            port = 80;
        } else {
            port = 443;
        }
    }
    NSString *host = _url.host;
    
    if (_httpProxyHost) {
        host = _httpProxyHost;
        if (_httpProxyPort)
            port = _httpProxyPort;
        else
            port = 80;
    }
    
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    
    ProxyFastLog(@"ProxyConnect connect stream to %@:%u", host, port);
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, port, &readStream, &writeStream);
    
    self.outputStream = CFBridgingRelease(writeStream);
    self.inputStream = CFBridgingRelease(readStream);

    if (_socksProxyHost) {
        ProxyFastLog(@"ProxyConnect set sock property stream to %@:%u user %@ password %@", _socksProxyHost, _socksProxyPort, _socksProxyUsername, _socksProxyPassword);
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

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
{
    ProxyFastLog(@"stream handleEvent %u", eventCode);
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
            
        default:
            ProxyFastLog(@"(default)  %@", aStream);
            break;
    }
}

- (void)_proxyDidConnect
{
    ProxyFastLog(@"Proxy Connected");
    uint32_t port = _url.port.unsignedIntValue;
    if (port == 0) {
        if (!_secure) {
            port = 80;
        } else {
            port = 443;
        }
    }
    // Send HTTP CONNECT Request
    NSString *connectRequestStr = [NSString stringWithFormat:@"CONNECT %@:%u HTTP/1.1\r\nHost: %@\r\nConnection: keep-alive\r\nProxy-Connection: keep-alive\r\n\r\n", _url.host, port, _url.host];
    
    NSData *message =  [connectRequestStr dataUsingEncoding:NSUTF8StringEncoding];
    ProxyFastLog(@"Proxy sending %@", connectRequestStr);
    
    [self _writeData:message];
}

#define BUFFER_MAX  4096

///handles the incoming bytes and sending them to the proper processing method
-(void) _processInputStream
{
    NSMutableData *buf = [NSMutableData dataWithCapacity:BUFFER_MAX];
    uint8_t *buffer = buf.mutableBytes;
    NSInteger length = [_inputStream read:buffer maxLength: BUFFER_MAX];
    
    if (length <= 0)
        return;
    BOOL process = NO;
    if (_inputQueue.count == 0)
        process = YES;
    
    [_inputQueue addObject:[NSData dataWithBytes:buffer length:length]];
    
    if (process)
        [self _dequeueInput];
    
}

///dequeue the incoming input so it is processed in order

-(void) _dequeueInput
{
    while (_inputQueue.count > 0) {
        NSData * data = _inputQueue[0];
        [self _proxyProcessHTTPResponseWithData:data];
        [_inputQueue removeObjectAtIndex:0];
    }
}
//handle checking the proxy  connection status
-(void)  _proxyProcessHTTPResponseWithData:(NSData *)data
{
    if (_receivedHTTPHeaders == NULL) {
        _receivedHTTPHeaders = CFHTTPMessageCreateEmpty(NULL, NO);
    }
    
    CFHTTPMessageAppendBytes(_receivedHTTPHeaders, (const UInt8 *)data.bytes, data.length);
    if (CFHTTPMessageIsHeaderComplete(_receivedHTTPHeaders)) {
        ProxyFastLog(@"Finished reading headers %@", CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(_receivedHTTPHeaders)));
        [self _proxyHTTPHeadersDidFinish];
    }
}

- (void)_proxyHTTPHeadersDidFinish;
{
    NSInteger responseCode = CFHTTPMessageGetResponseStatusCode(_receivedHTTPHeaders);
    
    if (responseCode >= 299) {
        ProxyFastLog(@"Connect to Proxy Request failed with response code %d", responseCode);
        NSError *error = SRHTTPErrorWithCodeDescription(responseCode, 2132,
                                                        [NSString stringWithFormat:@"Received bad response code from proxy server: %d.",
                                                         (int)responseCode]);
        [self _failWithError:error];
        return;
    }
    ProxyFastLog(@"proxy connect return %d, call socket connect", responseCode);
    [self _didConnect];
}

#define timeout 5
-(void)_writeData:(NSData *)data;
{
    const uint8_t * bytes = data.bytes;
    __block NSInteger out = timeout * 1000000; //wait 5 seconds before giving up
    __weak typeof(self) weakSelf = self;
    [_writeQueue addOperationWithBlock:^() {
        if (!weakSelf)
            return;
        NSOutputStream *outStream = weakSelf.outputStream;
        if (!outStream)
            return;
        while ( ![outStream hasSpaceAvailable]) {
            usleep(100); //wait until the socket is ready
            out -= 100;
            if (out < 0) {
                NSError *error = SRHTTPErrorWithCodeDescription(408, 2132,@"Proxy timeout");
                [self _failWithError:error];
            } else if (outStream.streamError != nil) {
                [self _failWithError:outStream.streamError];
            }
        }
        [outStream write:bytes maxLength:data.length];
    }];
}
@end

//#define PROXY_ENABLE_LOG

static inline void ProxyFastLog(NSString *format, ...)  {
#ifdef PROXY_ENABLE_LOG
    __block va_list arg_list;
    va_start (arg_list, format);
    
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:arg_list];
    
    va_end(arg_list);
    
    NSLog(@"[Proxy] %@", formattedString);
#endif
}
