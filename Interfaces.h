#import <Foundation/Foundation.h>

@interface DOCKFileTile : NSObject

-(NSString*) label;
-(void) setLabel:(NSString*)arg1 stripAppSuffix:(BOOL)arg2;
-(NSString*) bundleIdentifier;
@end

@interface NSObject (twk)
-(int) processIdentifier;
@end