//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "SRPinningSecurityPolicy.h"
#import <openssl/x509.h>

#import <Foundation/Foundation.h>

#import "SRLog.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRPinningSecurityPolicy ()

@property (nonatomic, copy, readonly) NSArray *pinnedCertificates;
@property (nonatomic, assign, readonly) BOOL comparesPublicKeys;

@end

@implementation SRPinningSecurityPolicy

- (instancetype)initWithCertificates:(NSArray *)pinnedCertificates comparesPublicKeys:(BOOL)comparesPublicKeys
{
    // Do not validate certificate chain since we're pinning to specific certificates.
    self = [super initWithCertificateChainValidationEnabled:NO];
    if (!self) { return self; }

    if (pinnedCertificates.count == 0) {
        @throw [NSException exceptionWithName:@"Creating security policy failed."
                                       reason:@"Must specify at least one certificate when creating a pinning policy."
                                     userInfo:nil];
    }
    _pinnedCertificates = [pinnedCertificates copy];
    _comparesPublicKeys = comparesPublicKeys;

    return self;
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain
{
    SRDebugLog(@"Pinned cert count: %d", self.pinnedCertificates.count);
    NSUInteger requiredCertCount = self.pinnedCertificates.count;

    NSUInteger validatedCertCount = 0;
    CFIndex serverCertCount = SecTrustGetCertificateCount(serverTrust);
    for (CFIndex i = 0; i < serverCertCount; i++) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(serverTrust, i);
        NSData *data = CFBridgingRelease(SecCertificateCopyData(cert));
        for (id ref in self.pinnedCertificates) {
            SecCertificateRef trustedCert = (__bridge SecCertificateRef)ref;
            // TODO: (nlutsenko) Add caching, so we don't copy the data for every pinned cert all the time.
            NSData *trustedCertData = CFBridgingRelease(SecCertificateCopyData(trustedCert));
            if ([self isServerCertificateDataValid:data trustedCertData:trustedCertData]) {
                validatedCertCount++;
                break;
            }
        }
    }
    return (requiredCertCount == validatedCertCount);
}

- (BOOL)isServerCertificateDataValid:(NSData *)serverCertData trustedCertData:(NSData *)trustedCertData
{
    if (_comparesPublicKeys) {
        return [[self getPublicKeyStringFromData:trustedCertData] isEqualToString:[self getPublicKeyStringFromData:serverCertData]];
    } else {
        return [trustedCertData isEqualToData:serverCertData];
    }
}

- (NSString *)getPublicKeyStringFromData:(NSData *)data
{
    const unsigned char *certificateDataBytes = (const unsigned char *)[data bytes];
    X509 *certificateX509 = d2i_X509(NULL, &certificateDataBytes, [data length]);
    ASN1_BIT_STRING *pubKey2 = X509_get0_pubkey_bitstr(certificateX509);
    
    NSString *publicKeyString = [[NSString alloc] init];
    
    for (int i = 0; i < pubKey2->length; i++) {
        NSString *aString = [NSString stringWithFormat:@"%02x", pubKey2->data[i]];
        publicKeyString = [publicKeyString stringByAppendingString:aString];
    }
    
    X509_free(certificateX509);
    
    return publicKeyString;
}

@end

NS_ASSUME_NONNULL_END
