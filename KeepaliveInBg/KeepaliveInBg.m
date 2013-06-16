//
//  KeepaliveInBg.m
//  KeepaliveInBg
//
//  Created by Wayne W on 13-6-15.
//
//

#import "KeepaliveInBg.h"
#import <AVFoundation/AVAudioSession.h>
#import <AudioToolbox/AudioSession.h>
#import <AVFoundation/AVAudioPlayer.h>
#import <UIKit/UIKit.h>

NSString * const KeepaliveInBgWillBeginNotification     = @"KeepaliveInBgWillBeginNotification";
NSString * const KeepaliveInBgDidEndNotification        = @"KeepaliveInBgDidEndNotification";
NSString * const kBackgroundModes       = @"UIBackgroundModes";
NSString * const bgModeAudio            = @"audio";

#define instAUDIOSession        ((AVAudioSession *)[AVAudioSession sharedInstance])
#define instAPP                 ([UIApplication sharedApplication])
#ifdef DEBUG
#define KIBLOG(x)       NSLog(x)
#else
#define KIBLOG(x)
#endif

NSString * const kPlayerStatus      = @"status";

KeepaliveInBg *g_instKeepalive = nil;

@interface KeepaliveInBg () <AVAudioSessionDelegate>
{
    NSString *_oldAudioCategory;
}

@property (nonatomic, strong) AVAudioPlayer *player;

- (BOOL)_doSetup;
- (void)_doCleanUp;

- (void)_start;
- (void)_stop;

@end

@implementation KeepaliveInBg

+ (KeepaliveInBg*)sharedInstance
{
    if (!g_instKeepalive)
    {
        g_instKeepalive = [[KeepaliveInBg alloc] init];
    }
    
    return g_instKeepalive;
}

- (id)init
{
    self = [super init];
    if (self)
    {

    }
    
    return self;
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = NO;
    
    if (enabled)
    {
        _enabled = [self _doSetup];
    }
    
    if (!_enabled)
    {
        [self _doCleanUp];
    }
}

- (BOOL)isInBackground
{
    return self.player.isPlaying;
}

#pragma mark private
- (BOOL)_checkConfig
{
    // check if the audio file exist
    if (![self _path4mutedAudio])
    {
        return NO;
    }
    
    // check if the config of app is correct!
    NSArray *modes = [[[NSBundle mainBundle] infoDictionary] objectForKey:kBackgroundModes];
    if (!modes ||
        ![modes isKindOfClass:[NSArray class]] ||
        [modes count] == 0)
    {
        return NO;
    }
    
    for (NSString *iter in modes)
    {
        if (iter &&
            [iter isKindOfClass:[NSString class]] &&
            [iter isEqualToString:bgModeAudio])
        {
            return YES;
        }
    }
    
    return NO;
}

- (NSString*)_path4mutedAudio
{
    return [[NSBundle mainBundle] pathForResource:@"detum" ofType:@"dat"];      // muted.dat ==> detum.dat
}

- (BOOL)_doSetup
{
    if (![self _checkConfig])
    {
        NSAssert(0, @"Invalid Config!");
        return NO;
    }
    
    if (self.player)
    {
        return YES;
    }
    
    UIApplication *app = instAPP;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_appBecameActive:)
                                                 name:UIApplicationDidBecomeActiveNotification object:app];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_appWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification object:app];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_appDidBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    // setup audio session
    {
        NSError *err = nil;
        [instAUDIOSession setActive:YES error:&err];
        NSAssert(!err, @"ERROR");
    }
    
    // create the player
    {
        NSString *path = [self _path4mutedAudio];
        self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:path]
                                                             error:nil];
        self.player.numberOfLoops = -1;
        [self.player prepareToPlay];
    }
    
    return (nil != self.player);
}

- (void)_doCleanUp
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self _stop];
    
    self.player = nil;
}

- (void)_start
{    
    if (instAUDIOSession.delegate &&
        instAUDIOSession.delegate != self)
    {
        // FAIL because it's hooked by another code
        NSAssert(0, @"ERROR");
        return;
    }
    
    if (self.enabled && !self.player.isPlaying)
    {
        KIBLOG(@"[_start]");
        [[NSNotificationCenter defaultCenter] postNotificationName:KeepaliveInBgWillBeginNotification
                                                            object:self
                                                          userInfo:nil];
        
        // monitor audio session
        instAUDIOSession.delegate = self;
        
        // enable background audio
        NSError *err = nil;
        _oldAudioCategory = instAUDIOSession.category;
        [instAUDIOSession setCategory:AVAudioSessionCategoryPlayback error:&err];
        [self _enableMixed];
        
        // play it
        [self.player play];
    }
}

- (void)_stop
{
    [self _disableMixed];
    instAUDIOSession.delegate = nil;
    
    if (_oldAudioCategory)
    {
        NSError *err = nil;
        [instAUDIOSession setCategory:_oldAudioCategory error:&err];
        _oldAudioCategory = nil;
    }
    
    if (self.player.isPlaying)
    {
        KIBLOG(@"[_stop]");
        [self.player stop];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:KeepaliveInBgDidEndNotification
                                                            object:self
                                                          userInfo:nil];
    }
}

- (void)_enableMixed
{
    UInt32 property = TRUE;
    AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, sizeof(property), &property);
}

- (void)_disableMixed
{
    UInt32 property = FALSE;
    AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, sizeof(property), &property);
}

#pragma mark UIApplication notifications
- (void)_appBecameActive:(NSNotification*)notify
{
    KIBLOG(@"[_appBecameActive]");
    [self _stop];
}

- (void)_appWillResignActive:(NSNotification*)notify
{
    KIBLOG(@"[_appWillResignActive]");
    [self _start];
}

- (void)_appDidBackground:(NSNotification*)notify
{
    __block UIBackgroundTaskIdentifier bgtID = 0;
    bgtID = [instAPP beginBackgroundTaskWithExpirationHandler:^{
        KIBLOG(@"[beginBackgroundTaskWithExpirationHandler]");
        [instAPP endBackgroundTask:bgtID];
    }];
}

#pragma mark AVAudioSession
- (void)beginInterruption
{
    KIBLOG(@"[beginInterruption]");
}

/* the interruption is over */
- (void)endInterruptionWithFlags:(NSUInteger)flags
{
    KIBLOG(@"[endInterruptionWithFlags]");
    
    if (instAPP.applicationState != UIApplicationStateActive)
    {
        [self _start];
    }
}

@end
