#import <Foundation/Foundation.h>

@interface ProxyConnect : NSObject
-(instancetype)initWithURL:(NSURL *)url;
-(void) openNetworkStreamWithCompletion:(void (^)(NSError *error, NSInputStream *readStream, NSOutputStream *writeStream ))completion;
@end								  
