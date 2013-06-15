//
//  KeepaliveInBg.h
//  KeepaliveInBg
//
//  Created by Wayne W on 13-6-15.
//
//

#import <Foundation/Foundation.h>

@interface KeepaliveInBg : NSObject

+ (KeepaliveInBg*)sharedInstance;

@property (nonatomic, assign) BOOL enabled;

@end
