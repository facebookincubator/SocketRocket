//
//  NSDataSRB64AdditionsTests.m
//  NSDataSRB64AdditionsTests
//
//  Created by Greg M. Krsak (greg.krsak@gmail.com) on 8/17/13.
//

#import "NSDataSRB64AdditionsTests.h"

// SocketRocket category to add Base64 functionality to NSData
#import "NSData+SRB64Additions.h"

@implementation NSDataSRB64AdditionsTests
{
    NSData *_data;
    NSMutableData *_dataWithNull;
}

- (void)setUp
{
    [super setUp];
    self->_data = [@"TESTING" dataUsingEncoding:NSUTF8StringEncoding];
    self->_dataWithNull = [self->_data mutableCopy];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)test_CanNullTerminateValidData
{
    
    NSMutableData *actual = [self nullTerminate:self->_dataWithNull];
    NSMutableData *expected = [[NSMutableData alloc] initWithBytes:"TESTING\0" length:8];
    STAssertEqualObjects(actual, expected, @"(NSData should be converted to its null-terminated equivalent)");
}

- (void)test_CanGenerateValidBase64FromValidNullTerminatedData
{
    [self nullTerminate:self->_dataWithNull];
    NSString *expected = @"VEVTVElORw==";
    NSString *actual = [self->_dataWithNull SR_stringByBase64Encoding];
    STAssertEqualObjects(actual, expected, @"(NSData should be converted to its base64 equivalent)");
}

// Adds a null to the end of the data
- (id)nullTerminate:(NSMutableData *)data
{
    [data increaseLengthBy:1];
    *((char *)[data bytes] + [data length] - 1) = '\0';
    return data;
}

@end
