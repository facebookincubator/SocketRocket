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

#import <Foundation/Foundation.h>
#import <Security/SecCertificate.h>

typedef NS_ENUM(NSInteger, SRReadyState) {
    SR_CONNECTING   = 0,
    SR_OPEN         = 1,
    SR_CLOSING      = 2,
    SR_CLOSED       = 3,
};

typedef enum SRStatusCode : NSInteger {
    // 0–999: Reserved and not used.
    SRStatusCodeNormal = 1000,
    SRStatusCodeGoingAway = 1001,
    SRStatusCodeProtocolError = 1002,
    SRStatusCodeUnhandledType = 1003,
    // 1004 reserved.
    SRStatusNoStatusReceived = 1005,
    SRStatusCodeAbnormal = 1006,
    SRStatusCodeInvalidUTF8 = 1007,
    SRStatusCodePolicyViolated = 1008,
    SRStatusCodeMessageTooBig = 1009,
    SRStatusCodeMissingExtension = 1010,
    SRStatusCodeInternalError = 1011,
    SRStatusCodeServiceRestart = 1012,
    SRStatusCodeTryAgainLater = 1013,
    // 1014: Reserved for future use by the WebSocket standard.
    SRStatusCodeTLSHandshake = 1015,
    // 1016–1999: Reserved for future use by the WebSocket standard.
    // 2000–2999: Reserved for use by WebSocket extensions.
    // 3000–3999: Available for use by libraries and frameworks. May not be used by applications. Available for registration at the IANA via first-come, first-serve.
    // 4000–4999: Available for use by applications.
} SRStatusCode;

@class SRWebSocket;

extern NSString *const SRWebSocketErrorDomain;
extern NSString *const SRHTTPResponseErrorKey;

#pragma mark - SRWebSocketDelegate

@protocol SRWebSocketDelegate;

#pragma mark - SRWebSocket

@interface SRWebSocket : NSObject <NSStreamDelegate>

/**
 The delegate of the web socket.

 The web socket delegate is notified on all state changes that happen to the web socket.
 */
@property (nonatomic, weak) id <SRWebSocketDelegate> delegate;

/**
 A dispatch queue for scheduling the delegate calls. The queue doesn't need be a serial queue.

 If `nil` and `delegateOperationQueue` is `nil`, the socket uses main queue for performing all delegate method calls.
 */
@property (nonatomic, strong) dispatch_queue_t delegateDispatchQueue;

/**
 An operation queue for scheduling the delegate calls.

 If `nil` and `delegateOperationQueue` is `nil`, the socket uses main queue for performing all delegate method calls.
 */
@property (nonatomic, strong) NSOperationQueue *delegateOperationQueue;

@property (nonatomic, readonly) SRReadyState readyState;
@property (nonatomic, readonly, retain) NSURL *url;

@property (nonatomic, readonly) CFHTTPMessageRef receivedHTTPHeaders;

// Optional array of cookies (NSHTTPCookie objects) to apply to the connections
@property (nonatomic, copy) NSArray<NSHTTPCookie *> *requestCookies;

// This returns the negotiated protocol.
// It will be nil until after the handshake completes.
@property (nonatomic, readonly, copy) NSString *protocol;

// Protocols should be an array of strings that turn into Sec-WebSocket-Protocol.
- (instancetype)initWithURLRequest:(NSURLRequest *)request;
- (instancetype)initWithURLRequest:(NSURLRequest *)request protocols:(NSArray<NSString *> *)protocols;
- (instancetype)initWithURLRequest:(NSURLRequest *)request protocols:(NSArray<NSString *> *)protocols allowsUntrustedSSLCertificates:(BOOL)allowsUntrustedSSLCertificates;

// Some helper constructors.
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protocols;
- (instancetype)initWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protocols allowsUntrustedSSLCertificates:(BOOL)allowsUntrustedSSLCertificates;

// By default, it will schedule itself on +[NSRunLoop SR_networkRunLoop] using defaultModes.
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)unscheduleFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;

// SRWebSockets are intended for one-time-use only.  Open should be called once and only once.
- (void)open;

- (void)close;
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;

///--------------------------------------
#pragma mark Send
///--------------------------------------

/**
 Send a UTF-8 string or binary data to the server.

 @param message UTF-8 String or Data to send.

 @deprecated Please use `sendString:` or `sendData` instead.
 */
- (void)send:(id)message __attribute__((deprecated("Please use `sendString:` or `sendData` instead.")));

/**
 Send a UTF-8 String to the server.

 @param string String to send.
 */
- (void)sendString:(NSString *)string;

/**
 Send binary data to the server.

 @param data Data to send.
 */
- (void)sendData:(NSData *)data;

/**
 Send Ping message to the server with optional data.

 @param data Instance of `NSData` or `nil`.
 */
- (void)sendPing:(NSData *)data;

@end

///--------------------------------------
#pragma mark - SRWebSocketDelegate
///--------------------------------------

@protocol SRWebSocketDelegate <NSObject>

// message will either be an NSString if the server is using text
// or NSData if the server is using binary.
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message;

@optional

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean;
- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload;

// Return YES to convert messages sent as Text to an NSString. Return NO to skip NSData -> NSString conversion for Text messages. Defaults to YES.
- (BOOL)webSocketShouldConvertTextFrameToString:(SRWebSocket *)webSocket;

@end

#pragma mark - NSURLRequest (SRCertificateAdditions)

@interface NSURLRequest (SRCertificateAdditions)

@property (nonatomic, retain, readonly) NSArray *SR_SSLPinnedCertificates;

@end

#pragma mark - NSMutableURLRequest (SRCertificateAdditions)

@interface NSMutableURLRequest (SRCertificateAdditions)

@property (nonatomic, retain) NSArray *SR_SSLPinnedCertificates;

@end

#pragma mark - NSRunLoop (SRWebSocket)

@interface NSRunLoop (SRWebSocket)

+ (NSRunLoop *)SR_networkRunLoop;

@end
