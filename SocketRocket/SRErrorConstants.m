//
//  SRErrorConstants.m
//  SocketRocket
//
//  Created by Oleksandr Dodatko on 2/13/15.
//
//

#import "SRErrorConstants.h"

@implementation SRErrorConstants

+(NSString *)SRWebSocketErrorDomain
{
    return @"SRWebSocketErrorDomain";
}

+(NSString *)SRHTTPResponseErrorKey
{
    return @"HTTPResponseStatusCode";
}

@end
