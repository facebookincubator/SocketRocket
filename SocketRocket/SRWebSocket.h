//
//   Copyright 2012 Square Inc.
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.
//

#import <Foundation/Foundation.h>
#import <Security/SecCertificate.h>

typedef NS_ENUM(NSInteger, SRReadyState) {
    SRReadyStateConnecting = 0,
    SRReadyStateOpen = 1,
    SRReadyStateClosing = 2,
    SRReadyStateClosed = 3,
};

/**
 *  Legacy SRReadyState constants. These map directly to the new constants.
 */
extern SRReadyState const SR_CONNECTING; // SRReadyStateConnecting
extern SRReadyState const SR_OPEN; // SRReadyStateOpen
extern SRReadyState const SR_CLOSING; // SRReadyStateClosing
extern SRReadyState const SR_CLOSED; // SRReadyStateClosed

typedef NS_ENUM(NSInteger, SRStatusCode) {
    SRStatusCodeNormal = 1000,
    SRStatusCodeGoingAway = 1001,
    SRStatusCodeProtocolError = 1002,
    SRStatusCodeUnhandledType = 1003,
    // 1004 reserved.
    SRStatusNoStatusReceived = 1005,
    // 1004-1006 reserved.
    SRStatusCodeInvalidUTF8 = 1007,
    SRStatusCodePolicyViolated = 1008,
    SRStatusCodeMessageTooBig = 1009,
};

extern NSString *const SRWebSocketErrorDomain;
extern NSString *const SRHTTPResponseErrorKey;

#pragma mark - SRWebSocketDelegate

@protocol SRWebSocketDelegate;

#pragma mark - SRWebSocket

@interface SRWebSocket : NSObject <NSStreamDelegate>

/**
 *  Set and retrieve the delegate.
 */
@property (nonatomic, weak) id <SRWebSocketDelegate> delegate;

/**
 *  The current state of the connection.
 */
@property (nonatomic, readonly) SRReadyState readyState;

/**
 *  The connection's endpoint.
 */
@property (nonatomic, readonly) NSURL *url;

@property (nonatomic, readonly) CFHTTPMessageRef receivedHTTPHeaders;

// Optional array of cookies (NSHTTPCookie objects) to apply to the connections
@property (nonatomic, readwrite) NSArray * requestCookies;

// This returns the negotiated protocol.
// It will be nil until after the handshake completes.
@property (nonatomic, readonly, copy) NSString *protocol;

/**
 *  This property determine whether NSString/NSData objects are copied before being sent. The default value of this property is YES. Set this property to NO for a minor performance optimization if you know you are sending objects that won't change before they are written.
 */
@property (nonatomic) BOOL sendDataSafely;

// Protocols should be an array of strings that turn into Sec-WebSocket-Protocol.
- (instancetype)initWithURLRequest:(NSURLRequest *)request protocols:(NSArray *)protocols allowsUntrustedSSLCertificates:(BOOL)allowsUntrustedSSLCertificates;
- (instancetype)initWithURLRequest:(NSURLRequest *)request protocols:(NSArray *)protocols;
- (instancetype)initWithURLRequest:(NSURLRequest *)request;

// Some helper constructors.
- (instancetype)initWithURL:(NSURL *)url protocols:(NSArray *)protocols allowsUntrustedSSLCertificates:(BOOL)allowsUntrustedSSLCertificates;
- (instancetype)initWithURL:(NSURL *)url protocols:(NSArray *)protocols;

/**
 *  Initializes an SRWebSocket with the given URL and nil protocols.
 *
 *  @param url       The URL.
 *
 *  @return An initialized SRWebSocket.
 */
- (instancetype)initWithURL:(NSURL *)url;

/**
 *  Set the delegate operation queue. This property will default to -[NSOperationQueue mainQueue]. This may not be used together with the -[SRWebSocket setDelegateDispatchQueue:] method.
 *
 *  @param queue The NSOperationQueue on which to perform delegate callbacks.
 */
- (void)setDelegateOperationQueue:(NSOperationQueue *)queue;

/**
 *  Set the delegate dispatch queue. This property will default to dispatch_get_main_queue(). This may not be used together with the -[SRWebSocket setDelegateOperationQueue:] method.
 *
 *  @param queue The dispatch_queue_t on which to perform delegate callbacks.
 */
- (void)setDelegateDispatchQueue:(dispatch_queue_t)queue;

// By default, it will schedule itself on +[NSRunLoop SR_networkRunLoop] using defaultModes.

/**
 *  Schedule the socket in the given runloop and modes. By default it will be scheduled in the +[NSRunLoop SR_networkRunLoop] using the NSDefaultRunLoopMode.
 *
 *  @param aRunLoop The run loop in which to schedule the socket.
 *  @param mode     The mode to be scheduled in.
 */
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;

/**
 *  Unschedule the socket from the given runloop and modes.
 *
 *  @param aRunLoop The run loop from which to unschedule the socket.
 *  @param mode     The mode to be unscheduled from.
 */
- (void)unscheduleFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;

/**
 *  Open the socket. SRWebSockets are intended for one-time-use only so this method should not be called more than once.
 */
- (void)open;

/**
 *  Close the socket with the reason: SRStatusCodeNormal and no error.
 */
- (void)close;

/**
 *  Close the socket with the given reason an error.
 *
 *  @param code   The error code.
 *  @param reason The error reason.
 */
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;

/**
 *  Send either an NSData object, or a UTF-8 encoded NSString. See the sendDataSafely property for more info.
 *
 *  @param data Either an NSData object or a encoded UTF-8 NSString.
 */
- (void)send:(id)data;

/**
 *  Send a UTF-8 encoded NSString. See the sendDataSafely property for more info.
 *
 *  @param message A UTF-8 encoded NSString.
 */
- (void)sendString:(NSString *)message;

/**
 *  Send NSData. See the sendDataSafely property for more info.
 *
 *  @param message An NSData object.
 */
- (void)sendData:(NSData *)message;

/**
 *  Send data with an identifier in such a way that you will be notified when the write has completed.
 *
 *  @param message    The data.
 *  @param identifier The identifier.
 */
- (void)sendPartialData:(NSData *)message withIdentifier:(id)identifier;

// Send Data (can be nil) in a ping message.

/**
 *  Send a ping with the given NSData.
 *
 *  @param data An NSData object, or nil.
 */
- (void)sendPing:(NSData *)data;

@end

#pragma mark - SRWebSocketDelegate

@protocol SRWebSocketDelegate <NSObject>

@optional

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean;
- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload;

// message will either be an NSString if the server is using text
// or NSData if the server is using binary.
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message;

- (void)webSocket:(SRWebSocket *)webSocket didReceiveString:(NSString *)message;
- (void)webSocket:(SRWebSocket *)webSocket didReceiveData:(NSData *)message;

- (void)webSocket:(SRWebSocket *)webSocket writeDidFinishWithIdentifier:(id)identifier;

@end

#pragma mark - NSURLRequest (CertificateAdditions)

@interface NSURLRequest (CertificateAdditions)

@property (nonatomic, retain, readonly) NSArray *SR_SSLPinnedCertificates;

@end

#pragma mark - NSMutableURLRequest (CertificateAdditions)

@interface NSMutableURLRequest (CertificateAdditions)

@property (nonatomic, retain) NSArray *SR_SSLPinnedCertificates;

@end

#pragma mark - NSRunLoop (SRWebSocket)

@interface NSRunLoop (SRWebSocket)

+ (NSRunLoop *)SR_networkRunLoop;

@end
