//
//  KeepaliveInBg.m
//  KeepaliveInBg
//
//  Created by Wayne W on 13-6-15.
//  https://github.com/henern
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
#define KIBLOG(...)       NSLog(__VA_ARGS__)
#else
#define KIBLOG(...)
#endif

NSString * const kPlayerStatus      = @"status";

KeepaliveInBg *g_instKeepalive = nil;

@interface KeepaliveInBg () <AVAudioPlayerDelegate>
{
    NSString *_oldAudioCategory;
    UIBackgroundTaskIdentifier _bgtID;
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
        _bgtID = UIBackgroundTaskInvalid;
        
        // create the player
        NSString *path = [self _path4mutedAudio];
        if (path && [path length] > 0)
        {
            NSData *audioData = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:path]];
            // [[AVAudioPlayer alloc] initWithContentsOfURL:] not work on iOS 5.0,5.1
            self.player = [[AVAudioPlayer alloc] initWithData:audioData
                                                        error:nil];
            NSAssert(self.player, @"ERROR");
            self.player.numberOfLoops = -1;
            [self.player prepareToPlay];
        }
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
    // check if player is ready
    if (!self.player)
    {
        return NO;
    }
    
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
    
    if (self.player.isPlaying)
    {
        return YES;
    }
    
    NSAssert(self.player, @"ERROR");
    
    // hook
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
    
    // open background-task
    [self _closeBackgroundTask];
    _bgtID = [instAPP beginBackgroundTaskWithExpirationHandler:^{
        KIBLOG(@"[beginBackgroundTaskWithExpirationHandler] ID:%d", _bgtID);
        
        [self _closeBackgroundTask];
    }];
    
    // setup audio session
    {
        NSError *err = nil;
        [instAUDIOSession setActive:YES error:&err];
        NSAssert(!err, @"ERROR");
    }
    
    // turn on the mode if not active
    if (UIApplicationStateActive != instAPP.applicationState)
    {
        [self performSelectorOnMainThread:@selector(_start) withObject:nil waitUntilDone:NO];
    }
    
    return (nil != self.player);
}

- (void)_doCleanUp
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self _stop];
}

- (void)_start
{   
    if (self.player.delegate &&
        self.player.delegate != self)
    {
        // FAIL because it's hooked by another code
        NSAssert(0, @"ERROR");
        return;
    }
    
    if (self.enabled && self.player && !self.player.isPlaying)
    {
        KIBLOG(@"[_start]");
        [[NSNotificationCenter defaultCenter] postNotificationName:KeepaliveInBgWillBeginNotification
                                                            object:self
                                                          userInfo:nil];
        
        // TODO: AVAudioSessionInterruptionNotification
        // monitor audio session
        self.player.delegate = self;
        
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
    self.player.delegate = nil;
    [self _closeBackgroundTask];
    
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

- (void)_closeBackgroundTask
{
    if (UIBackgroundTaskInvalid != _bgtID)
    {
        KIBLOG(@"%s, background-task-id:%u", __FUNCTION__, (NSUInteger)_bgtID);
        
        [instAPP endBackgroundTask:_bgtID];
        _bgtID = UIBackgroundTaskInvalid;
    }
    
    NSAssert(UIBackgroundTaskInvalid == _bgtID, @"ERROR");
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
    if (!self.enabled)
    {
        return;
    }
    
    KIBLOG(@"%s, background-task-id:%u", __FUNCTION__, (NSUInteger)_bgtID);
}

#pragma mark AVAudioPlayerDelegate
- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player;
{
    KIBLOG(@"[beginInterruption]");
    
    if (!self.enabled || instAPP.applicationState == UIApplicationStateActive)
    {
        NSAssert(0, @"Unexpected!");
        [self _stop];       // stop it for safety!
        return;
    }
    
    if (!self.player.isPlaying)
    {
        // re-start
        [self.player stop];
        [self.player play];
    }
    
    KIBLOG(@"[beginInterruption] restart the player, isplaying == %d", self.player.isPlaying);
    if (!self.player.isPlaying)
    {
        NSAssert(0, @"Failed to restart audio playback!");
        [self.player stop];     // stop the audio for safety!
    }
}

/* the interruption is over */
- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player withFlags:(NSUInteger)flags
{
    KIBLOG(@"[endInterruptionWithFlags]");
    
    if (instAPP.applicationState != UIApplicationStateActive)
    {
        [self _start];
    }
}

@end
