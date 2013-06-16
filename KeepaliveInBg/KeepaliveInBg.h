//
//  KeepaliveInBg.h
//  KeepaliveInBg
//
//  Created by Wayne W on 13-6-15.
//  https://github.com/henern
//

/*
 *  How to config
 *  1. add detum.dat to the project
 *  2. add "UIBackgroundModes" --> "audio" to the info.plist
 *  3. add frameworks to the project
 */

#import <Foundation/Foundation.h>

extern NSString * const KeepaliveInBgWillBeginNotification;
extern NSString * const KeepaliveInBgDidEndNotification;

@interface KeepaliveInBg : NSObject

+ (KeepaliveInBg*)sharedInstance;

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign, readonly) BOOL isInBackground;

@end
