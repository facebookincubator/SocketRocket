//
//  SRWebSocketProtocol.h
//  SocketRocket
//
//  Created by Oleksandr Dodatko on 2/11/15.
//
//

#import <Foundation/Foundation.h>

@protocol SRWebSocketProtocol <NSObject>

- (void)open;

- (void)close;
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;

// Send a UTF8 String or Data.
- (void)send:(id)data;

@end
