#import "BellpadGameOverlay.h"
#import "BellpadDiagnostics.h"
#include <SDL3/SDL_log.h>

#import <AVFAudio/AVAudioSession.h>
#import <GameController/GameController.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "BellpadDiscValidator.h"
#include "BellpadInput.h"
#include "BellpadSaveData.h"

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <fcntl.h>
#include <mutex>
#include <string>
#include <unistd.h>
#include <utility>

@protocol BPStickDelegate <NSObject>
- (void)stick:(NSInteger)tag changedX:(std::int8_t)x y:(std::int8_t)y;
@end

@interface BPStickView : UIView
@property(nonatomic, weak) id<BPStickDelegate> delegate;
@property(nonatomic) CGFloat deadzone;
- (void)reset;
@end

@implementation BPStickView {
    UIView *_thumb;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.38];
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.46].CGColor;
        self.layer.borderWidth = 2.0;
        _thumb = [UIView new];
        _thumb.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.38];
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = std::min(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = side * 0.5;
    CGFloat diameter = side * 0.42;
    _thumb.bounds = CGRectMake(0, 0, diameter, diameter);
    if (CGPointEqualToPoint(_thumb.center, CGPointZero)) {
        _thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    }
    _thumb.layer.cornerRadius = diameter * 0.5;
}

- (void)update:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = std::max<CGFloat>(1.0, std::min(self.bounds.size.width, self.bounds.size.height) * 0.5);
    CGFloat x = (point.x - center.x) / radius;
    CGFloat y = (point.y - center.y) / radius;
    CGFloat length = std::hypot(x, y);
    if (length > 1.0) {
        x /= length;
        y /= length;
    }
    CGFloat travel = std::max<CGFloat>(0.0, radius - _thumb.bounds.size.width * 0.5 - 4.0);
    _thumb.center = CGPointMake(center.x + x * travel, center.y + y * travel);
    CGFloat magnitude = std::min<CGFloat>(1.0, length);
    CGFloat output = magnitude > self.deadzone ? (magnitude - self.deadzone) / (1.0 - self.deadzone) : 0;
    if (magnitude > 0) { x *= output / magnitude; y *= output / magnitude; }
    [self.delegate stick:self.tag
                changedX:static_cast<std::int8_t>(std::lround(x * 127.0))
                       y:static_cast<std::int8_t>(std::lround(-y * 127.0))];
}

- (void)reset {
    _thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self.delegate stick:self.tag changedX:0 y:0];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)event; [self update:touches.anyObject]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)event; [self update:touches.anyObject]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)touches; (void)event; [self reset]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self touchesEnded:touches withEvent:event]; }

@end

@interface BPGameButton : UIButton
@property(nonatomic) std::uint16_t inputMask;
@end
@implementation BPGameButton
@end

struct BPNativeTextEvent {
    std::string text;
    int command = BELLPAD_NATIVE_TEXT_NONE;
};

static std::mutex sNativeTextMutex;
static std::deque<BPNativeTextEvent> sNativeTextEvents;
static std::atomic_bool sNativeTextRequested{false};
static std::atomic_int sFrameBufferScaleMode{0};
static std::atomic_bool sDidBecomeActive{false};
static std::atomic_bool sWasInactive{false};
static std::atomic_bool sWillResignActive{false};
static std::atomic_bool sHostClockChanged{false};
static std::atomic_bool sAudioAppActive{true};
static std::atomic_bool sAudioInterrupted{false};
static std::atomic_bool sAudioSessionReady{false};
static std::atomic_bool sAudioInterruptionBegan{false};
static std::atomic_bool sAudioInterruptionEnded{false};
static std::atomic_bool sAudioRouteChanged{false};
static NSURL *sApplicationSupportURL;

static NSString *const BPChangeGameDataOnNextLaunchKey = @"BellpadChangeGameDataOnNextLaunch";
static NSString *const BPRemoveGameDataOnNextLaunchKey = @"BellpadRemoveGameDataOnNextLaunch";
static NSString *const BPSaveRecoveryNoticeKey = @"BellpadSaveRecoveryNotice";

static BOOL BellpadConfigureAudioSession(NSString *reason) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *categoryError = nil;
    BOOL categorySet = [session setCategory:AVAudioSessionCategoryAmbient
                                       mode:AVAudioSessionModeDefault
                                    options:AVAudioSessionCategoryOptionMixWithOthers
                                      error:&categoryError];
    if (!categorySet) {
        BellpadLog(@"[AudioSession] Could not set category after %@: %@", reason,
              categoryError.localizedDescription);
        return NO;
    }

    NSError *rateError = nil;
    if (![session setPreferredSampleRate:32000.0 error:&rateError]) {
        BellpadLog(@"[AudioSession] Could not request 32 kHz after %@: %@", reason,
              rateError.localizedDescription);
    }

    NSError *activeError = nil;
    BOOL active = [session setActive:YES error:&activeError];
    if (!active) {
        BellpadLog(@"[AudioSession] Could not activate after %@: %@", reason,
              activeError.localizedDescription);
        return NO;
    }
    BellpadLog(@"[AudioSession] Active after %@ (sample rate %.0f Hz, outputs %lu)",
          reason, session.sampleRate, (unsigned long)session.currentRoute.outputs.count);
    return YES;
}

#if TARGET_OS_SIMULATOR
static void BellpadScheduleAudioSessionSelfTest(void) {
    NSString *requested = NSProcessInfo.processInfo.environment[@"BELLPAD_TEST_AUDIO_SESSION_EVENTS"];
    if (!requested.boolValue) return;

    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    BellpadLog(@"[AudioSessionTest] Scheduling interruption and route-change notifications");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BellpadLog(@"[AudioSessionTest] Posting interruption began");
        [center postNotificationName:AVAudioSessionInterruptionNotification
                              object:session
                            userInfo:@{AVAudioSessionInterruptionTypeKey:
                                           @(AVAudioSessionInterruptionTypeBegan)}];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(14.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BellpadLog(@"[AudioSessionTest] Posting interruption ended");
        [center postNotificationName:AVAudioSessionInterruptionNotification
                              object:session
                            userInfo:@{
                                AVAudioSessionInterruptionTypeKey:
                                    @(AVAudioSessionInterruptionTypeEnded),
                                AVAudioSessionInterruptionOptionKey:
                                    @(AVAudioSessionInterruptionOptionShouldResume),
                            }];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(17.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BellpadLog(@"[AudioSessionTest] Posting old-device-unavailable route change");
        [center postNotificationName:AVAudioSessionRouteChangeNotification
                              object:session
                            userInfo:@{AVAudioSessionRouteChangeReasonKey:
                                           @(AVAudioSessionRouteChangeReasonOldDeviceUnavailable)}];
    });
}
#endif

static NSURL *BellpadResolvedApplicationSupportURL(void) {
    if (sApplicationSupportURL) return sApplicationSupportURL;
    NSString *currentDirectory = NSFileManager.defaultManager.currentDirectoryPath;
    if ([currentDirectory.lastPathComponent isEqualToString:@"Bellpad"]) {
        sApplicationSupportURL = [NSURL fileURLWithPath:currentDirectory isDirectory:YES];
    }
    return sApplicationSupportURL;
}

static NSURL *BellpadCanonicalSaveURL(void) {
    NSURL *supportURL = BellpadResolvedApplicationSupportURL();
    if (!supportURL) return nil;
    return [[[supportURL URLByAppendingPathComponent:@"save" isDirectory:YES]
        URLByAppendingPathComponent:@"card_a" isDirectory:YES]
        URLByAppendingPathComponent:@"DobutsunomoriP_MURA.gci"];
}

static NSURL *BellpadPendingSaveURL(void) {
    NSURL *supportURL = BellpadResolvedApplicationSupportURL();
    if (!supportURL) return nil;
    return [[[supportURL URLByAppendingPathComponent:@"save" isDirectory:YES]
        URLByAppendingPathComponent:@"Import" isDirectory:YES]
        URLByAppendingPathComponent:@"DobutsunomoriP_MURA.pending.gci"];
}

static NSString *BellpadValidateGCIData(NSData *data) {
    const BellpadGCIValidationResult result = BellpadValidateGCI(
        static_cast<const std::uint8_t *>(data.bytes), data.length);
    if (result.valid()) return nil;
    const std::string message = BellpadGCIValidationMessage(result);
    return [NSString stringWithUTF8String:message.c_str()];
}

static NSString *BellpadLoadValidatedGCI(NSURL *url, NSData **outputData) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&error];
    if (!data) {
        return [NSString stringWithFormat:@"The GCI could not be read: %@",
                                          error.localizedDescription ?: @"unknown error"];
    }
    NSString *validationError = BellpadValidateGCIData(data);
    if (validationError) return validationError;
    if (outputData) *outputData = data;
    return nil;
}

static BOOL BellpadSynchronizeFileAndDirectory(NSURL *url, NSError **outputError) {
    int file = open(url.fileSystemRepresentation, O_RDONLY);
    if (file < 0) {
        if (outputError) *outputError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    const int fileResult = fsync(file);
    const int fileError = errno;
    close(file);
    if (fileResult != 0) {
        if (outputError) *outputError = [NSError errorWithDomain:NSPOSIXErrorDomain code:fileError userInfo:nil];
        return NO;
    }

    int directory = open(url.URLByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY);
    if (directory < 0) {
        if (outputError) *outputError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    const int directoryResult = fsync(directory);
    const int directoryError = errno;
    close(directory);
    if (directoryResult != 0) {
        if (outputError) *outputError = [NSError errorWithDomain:NSPOSIXErrorDomain code:directoryError userInfo:nil];
        return NO;
    }
    return YES;
}

static void BellpadApplyPendingSaveImport(void) {
    NSURL *pending = BellpadPendingSaveURL();
    NSURL *destination = BellpadCanonicalSaveURL();
    if (!pending || !destination || ![NSFileManager.defaultManager fileExistsAtPath:pending.path]) return;

    NSData *data = nil;
    NSString *validationError = BellpadLoadValidatedGCI(pending, &data);
    NSFileManager *files = NSFileManager.defaultManager;
    if (validationError) {
        BellpadLog(@"[Save] Discarding invalid pending GCI: %@", validationError);
        [files removeItemAtURL:pending error:nil];
        return;
    }

    NSError *error = nil;
    NSURL *directory = destination.URLByDeletingLastPathComponent;
    [files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error];
    if (!error && [files fileExistsAtPath:destination.path]) {
        NSURL *backup = [directory URLByAppendingPathComponent:@"DobutsunomoriP_MURA.gci.pre-import"];
        [files removeItemAtURL:backup error:nil];
        [files copyItemAtURL:destination toURL:backup error:&error];
        if (!error) BellpadSynchronizeFileAndDirectory(backup, &error);
    }
    if (!error) {
        NSURL *staging = [directory URLByAppendingPathComponent:@"DobutsunomoriP_MURA.importing.gci"];
        [files removeItemAtURL:staging error:nil];
        [data writeToURL:staging options:NSDataWritingAtomic error:&error];
        if (!error) {
            if ([files fileExistsAtPath:destination.path]) {
                [files replaceItemAtURL:destination withItemAtURL:staging backupItemName:nil
                                options:0 resultingItemURL:nil error:&error];
            } else {
                [files moveItemAtURL:staging toURL:destination error:&error];
            }
        }
        if (error) [files removeItemAtURL:staging error:nil];
    }
    if (error) {
        BellpadLog(@"[Save] Pending GCI import failed and was retained: %@", error.localizedDescription);
        return;
    }
    NSError *syncError = nil;
    if (!BellpadSynchronizeFileAndDirectory(destination, &syncError)) {
        BellpadLog(@"[Save] Imported GCI is visible but metadata synchronization failed: %@",
              syncError.localizedDescription);
    }
    [files removeItemAtURL:pending error:nil];
    BellpadLog(@"[Save] Installed validated pending GCI before game startup");
}

static void BellpadSetSaveRecoveryNotice(NSString *title, NSString *message) {
    [NSUserDefaults.standardUserDefaults setObject:@{
        @"title": title,
        @"message": message,
    } forKey:BPSaveRecoveryNoticeKey];
}

static NSURL *BellpadUniqueCorruptSaveURL(NSURL *directory) {
    const long long timestamp = (long long)(NSDate.date.timeIntervalSince1970 * 1000.0);
    NSString *name = [NSString stringWithFormat:@"DobutsunomoriP_MURA.gci.corrupt-%lld", timestamp];
    NSURL *url = [directory URLByAppendingPathComponent:name];
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) return url;
    name = [NSString stringWithFormat:@"DobutsunomoriP_MURA.gci.corrupt-%@", NSUUID.UUID.UUIDString];
    return [directory URLByAppendingPathComponent:name];
}

static BOOL BellpadRecoverCanonicalSaveIfNeeded(void) {
    NSURL *destination = BellpadCanonicalSaveURL();
    NSFileManager *files = NSFileManager.defaultManager;
    if (!destination || ![files fileExistsAtPath:destination.path]) return YES;

    NSString *canonicalError = BellpadLoadValidatedGCI(destination, nil);
    if (!canonicalError) return YES;

    NSURL *directory = destination.URLByDeletingLastPathComponent;
    NSArray<NSString *> *backupNames = @[
        @"DobutsunomoriP_MURA.gci.bak1",
        @"DobutsunomoriP_MURA.gci.bak2",
        @"DobutsunomoriP_MURA.gci.bak3",
        @"DobutsunomoriP_MURA.gci.pre-import",
    ];
    NSData *recoveryData = nil;
    NSString *recoveryName = nil;
    for (NSString *name in backupNames) {
        NSURL *candidate = [directory URLByAppendingPathComponent:name];
        NSData *candidateData = nil;
        if ([files fileExistsAtPath:candidate.path] &&
            !BellpadLoadValidatedGCI(candidate, &candidateData)) {
            recoveryData = candidateData;
            recoveryName = name;
            break;
        }
    }

    NSURL *quarantine = BellpadUniqueCorruptSaveURL(directory);
    if (!recoveryData) {
        NSError *error = nil;
        [files moveItemAtURL:destination toURL:quarantine error:&error];
        if (error) {
            BellpadLog(@"[Save] Invalid canonical GCI could not be quarantined: %@", error.localizedDescription);
            BellpadSetSaveRecoveryNotice(@"Save Needs Attention",
                @"The active GCI is invalid and no valid backup was found. Bellpad could not move it aside, so the game was not started. Export the app container before retrying.");
            return NO;
        }
        NSError *syncError = nil;
        if (!BellpadSynchronizeFileAndDirectory(quarantine, &syncError)) {
            BellpadLog(@"[Save] Quarantined GCI metadata synchronization failed: %@",
                  syncError.localizedDescription);
        }
        BellpadLog(@"[Save] Quarantined invalid canonical GCI as %@; no valid backup was found",
              quarantine.lastPathComponent);
        BellpadSetSaveRecoveryNotice(@"Save Quarantined",
            [NSString stringWithFormat:
                @"The active GCI was invalid and no valid backup was found. Bellpad preserved it as %@ and started without loading the damaged file. You can import a valid Dolphin GCI from Settings.",
                quarantine.lastPathComponent]);
        return YES;
    }

    NSError *error = nil;
    NSURL *staging = [directory URLByAppendingPathComponent:@"DobutsunomoriP_MURA.recovering.gci"];
    [files removeItemAtURL:staging error:nil];
    [recoveryData writeToURL:staging options:NSDataWritingAtomic error:&error];
    if (!error) BellpadSynchronizeFileAndDirectory(staging, &error);
    if (!error) {
        [files replaceItemAtURL:destination withItemAtURL:staging
                 backupItemName:quarantine.lastPathComponent
                        options:NSFileManagerItemReplacementWithoutDeletingBackupItem
               resultingItemURL:nil error:&error];
    }
    if (error) {
        [files removeItemAtURL:staging error:nil];
        BellpadLog(@"[Save] Could not recover invalid canonical GCI from %@: %@",
              recoveryName, error.localizedDescription);
        BellpadSetSaveRecoveryNotice(@"Save Recovery Failed",
            [NSString stringWithFormat:
                @"The active GCI is invalid. A valid backup (%@) was found, but Bellpad could not install it: %@",
                recoveryName, error.localizedDescription]);
        return NO;
    }

    NSError *syncError = nil;
    if (!BellpadSynchronizeFileAndDirectory(destination, &syncError)) {
        BellpadLog(@"[Save] Recovered GCI metadata synchronization failed: %@",
              syncError.localizedDescription);
    }
    BellpadLog(@"[Save] Recovered invalid canonical GCI from %@; preserved damaged file as %@",
          recoveryName, quarantine.lastPathComponent);
    BellpadSetSaveRecoveryNotice(@"Save Recovered",
        [NSString stringWithFormat:
            @"Bellpad restored the newest valid backup (%@). The damaged GCI was preserved as %@.",
            recoveryName, quarantine.lastPathComponent]);
    return YES;
}

static void BellpadQueueNativeText(NSString *text) {
    const char *utf8 = text.UTF8String;
    if (!utf8 || !utf8[0]) return;
    std::lock_guard<std::mutex> lock(sNativeTextMutex);
    if (sNativeTextEvents.size() < 64) {
        sNativeTextEvents.push_back({utf8, BELLPAD_NATIVE_TEXT_NONE});
    }
}

static void BellpadQueueNativeTextCommand(int command) {
    std::lock_guard<std::mutex> lock(sNativeTextMutex);
    if (sNativeTextEvents.size() < 64) {
        sNativeTextEvents.push_back({{}, command});
    }
}

@interface BPNativeTextField : UITextField
- (void)submitText;
- (void)resetProxyText;
@end

@implementation BPNativeTextField {
    BOOL _updatingProxyText;
    BOOL _submitQueued;
}

- (BOOL)hasText {
    // Keep delete enabled while the game, rather than this proxy field, owns
    // the canonical editor contents.
    return YES;
}

- (void)setText:(NSString *)text {
    NSString *replacement = text ?: @"";
    if (_updatingProxyText) {
        [super setText:replacement];
        return;
    }

    // Dictation and accessibility can replace the complete value rather than
    // calling insertText:. Translate the changed suffix into game operations.
    NSString *current = [super text] ?: @"";
    NSUInteger common = 0;
    NSUInteger limit = std::min(current.length, replacement.length);
    while (common < limit && [current characterAtIndex:common] ==
                                 [replacement characterAtIndex:common]) {
        common++;
    }
    for (NSUInteger index = common; index < current.length; index++) {
        BellpadQueueNativeTextCommand(BELLPAD_NATIVE_TEXT_BACKSPACE);
    }
    if (common < replacement.length) {
        BellpadQueueNativeText([replacement substringFromIndex:common]);
    }
    _updatingProxyText = YES;
    [super setText:replacement];
    _updatingProxyText = NO;
}

- (void)setAccessibilityValue:(NSString *)value {
    self.text = value;
}

- (void)insertText:(NSString *)text {
    if ([text isEqualToString:@"\n"] || [text isEqualToString:@"\r"]) {
        [self submitText];
    } else {
        BellpadQueueNativeText(text);
        _updatingProxyText = YES;
        [super setText:[([super text] ?: @"") stringByAppendingString:text]];
        _updatingProxyText = NO;
    }
}

- (void)deleteBackward {
    BellpadQueueNativeTextCommand(BELLPAD_NATIVE_TEXT_BACKSPACE);
    NSString *current = [super text] ?: @"";
    if (current.length > 0) {
        NSRange last = [current rangeOfComposedCharacterSequenceAtIndex:current.length - 1];
        _updatingProxyText = YES;
        [super setText:[current stringByReplacingCharactersInRange:last withString:@""]];
        _updatingProxyText = NO;
    }
}

- (void)paste:(id)sender {
    (void)sender;
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (text.length > 0) [self insertText:text];
}

- (void)submitText {
    if (_submitQueued) return;
    _submitQueued = YES;
    BellpadQueueNativeTextCommand(BELLPAD_NATIVE_TEXT_ENTER);
}

- (void)resetProxyText {
    _submitQueued = NO;
    _updatingProxyText = YES;
    [super setText:@""];
    _updatingProxyText = NO;
}

@end

@interface BPDiscImportViewController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, copy) void (^completion)(NSURL *retainedURL);
@property(nonatomic, strong) NSURL *applicationSupportURL;
@end

@implementation BPDiscImportViewController {
    UILabel *_statusLabel;
    UIButton *_chooseButton;
    UIActivityIndicatorView *_activityIndicator;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.055 blue:0.095 alpha:1.0];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Choose your game data";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];

    UILabel *detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text = @"Bellpad requires a legally obtained Animal Crossing GAFE01 revision 0 ISO or GCM. The selected file is validated and copied to private Application Support. It is never added to the app bundle.";
    detail.numberOfLines = 0;
    detail.textColor = [UIColor colorWithWhite:1.0 alpha:0.76];
    detail.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    detail.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:detail];

    _statusLabel = [UILabel new];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.text = @"No supported game data is stored on this device.";
    _statusLabel.numberOfLines = 0;
    _statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.68];
    _statusLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_statusLabel];

    _chooseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _chooseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_chooseButton setTitle:@"Choose ISO or GCM…" forState:UIControlStateNormal];
    [_chooseButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _chooseButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _chooseButton.backgroundColor = [UIColor colorWithRed:0.22 green:0.48 blue:0.76 alpha:1.0];
    _chooseButton.layer.cornerRadius = 14.0;
    [_chooseButton addTarget:self action:@selector(chooseGameData) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_chooseButton];

    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _activityIndicator.color = UIColor.whiteColor;
    _activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:_activityIndicator];

    UIButton *diagnostics = [UIButton buttonWithType:UIButtonTypeSystem];
    diagnostics.translatesAutoresizingMaskIntoConstraints = NO;
    [diagnostics setTitle:@"Share Diagnostic Report…" forState:UIControlStateNormal];
    [diagnostics addTarget:self action:@selector(shareImportDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:diagnostics];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [title.bottomAnchor constraintEqualToAnchor:detail.topAnchor constant:-18.0],
        [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24.0],
        [detail.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [detail.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor constant:-32.0],
        [detail.widthAnchor constraintLessThanOrEqualToConstant:620.0],
        [detail.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:32.0],
        [_statusLabel.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:20.0],
        [_statusLabel.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_statusLabel.widthAnchor constraintLessThanOrEqualToConstant:620.0],
        [_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:32.0],
        [_chooseButton.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:20.0],
        [_chooseButton.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_chooseButton.widthAnchor constraintEqualToConstant:220.0],
        [_chooseButton.heightAnchor constraintEqualToConstant:50.0],
        [_activityIndicator.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_activityIndicator.topAnchor constraintEqualToAnchor:_chooseButton.bottomAnchor constant:8.0],
        [diagnostics.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-4.0],
        [diagnostics.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
        [diagnostics.heightAnchor constraintEqualToConstant:44.0],
    ]];
}

- (void)shareImportDiagnostics {
    NSError *error = nil;
    NSURL *url = BellpadDiagnosticsReport(@"Game data setup", @"Report created from the import screen; no selected file or game data is included.", &error);
    if (!url) { [self finishWithError:@"The report could not be written. Check available storage and try again."]; return; }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView = _chooseButton;
    share.popoverPresentationController.sourceRect = _chooseButton.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller; BellpadLog(@"disc picker cancelled");
}

- (void)chooseGameData {
    BellpadLog(@"disc picker presented");
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeData ] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    _chooseButton.enabled = !busy;
    _chooseButton.alpha = busy ? 0.45 : 1.0;
    _statusLabel.text = status;
    _statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.76];
    if (busy) [_activityIndicator startAnimating];
    else [_activityIndicator stopAnimating];
}

- (void)finishWithError:(NSString *)message {
    BellpadLog(@"disc import failed: %@", message);
    [self setBusy:NO status:message];
    _statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.58 blue:0.58 alpha:1.0];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *sourceURL = urls.firstObject;
    if (!sourceURL) return;

    BellpadLog(@"disc picker returned selection; validation started");
    [self setBusy:YES status:@"Validating and importing game data…"];
    __weak BPDiscImportViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BPDiscImportViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        BOOL accessed = [sourceURL startAccessingSecurityScopedResource];
        const BellpadDiscValidationResult sourceResult =
            BellpadValidateDiscImage(sourceURL.fileSystemRepresentation);
        if (!sourceResult.valid()) {
            const std::string text = BellpadDiscValidationMessage(sourceResult);
            if (accessed) [sourceURL stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf finishWithError:[NSString stringWithUTF8String:text.c_str()]];
            });
            return;
        }

        NSFileManager *files = NSFileManager.defaultManager;
        NSURL *directory = [strongSelf.applicationSupportURL URLByAppendingPathComponent:@"Game Data"
                                                                             isDirectory:YES];
        NSURL *destination = [directory URLByAppendingPathComponent:@"Animal Crossing.iso"];
        NSURL *staging = [directory URLByAppendingPathComponent:@"Animal Crossing.importing.iso"];
        NSError *error = nil;
        [files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error];
        if (!error && [files fileExistsAtPath:staging.path]) [files removeItemAtURL:staging error:&error];
        if (!error) [files copyItemAtURL:sourceURL toURL:staging error:&error];
        if (accessed) [sourceURL stopAccessingSecurityScopedResource];

        if (!error) {
            const BellpadDiscValidationResult stagedResult =
                BellpadValidateDiscImage(staging.fileSystemRepresentation);
            if (!stagedResult.valid()) {
                error = [NSError errorWithDomain:@"dev.bellpad.import" code:2
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             @"The copied file failed validation. The previous game data was kept."}];
            }
        }
        if (!error) {
            if ([files fileExistsAtPath:destination.path]) {
                [files replaceItemAtURL:destination withItemAtURL:staging backupItemName:nil
                                options:0 resultingItemURL:nil error:&error];
            } else {
                [files moveItemAtURL:staging toURL:destination error:&error];
            }
        }
        if (error) {
            [files removeItemAtURL:staging error:nil];
            NSString *message = [NSString stringWithFormat:@"Import failed: %@", error.localizedDescription];
            dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf finishWithError:message]; });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf setBusy:NO status:@"Supported game data imported. Starting Bellpad…"];
            BellpadLog(@"disc import validated and committed");
            if (strongSelf.completion) strongSelf.completion(destination);
        });
    });
}

@end

static UIWindow *BellpadGameWindow(void);

typedef NS_ENUM(NSInteger, BPDocumentPickerMode) {
    BPDocumentPickerModeNone = 0,
    BPDocumentPickerModeImportSave,
    BPDocumentPickerModeExportSave,
};

@interface BPGameOverlay : UIView <BPStickDelegate, UIDocumentPickerDelegate>
@end

@interface BPGameOverlay ()
- (void)beginSaveImport;
- (void)beginSaveExport;
- (void)presentDocumentPickerWhileHoldingGameLoop:(UIDocumentPickerViewController *)picker;
- (void)scheduleGameDataChange;
- (void)confirmGameDataRemoval;
- (void)presentMessageWithTitle:(NSString *)title message:(NSString *)message;
- (void)setNativeTextActive:(BOOL)active;
@end

@implementation BPGameOverlay {
    BellpadPadState _state;
    BPStickView *_moveStick;
    BPStickView *_cameraStick;
    NSMutableArray<BPGameButton *> *_buttons;
    NSMutableArray<UIGestureRecognizer *> *_editGestures;
    UIButton *_settingsButton;
    UIView *_settingsPanel;
    CGPoint _settingsPanelOffset;
    UIMenu *_dataMenu;
    UILabel *_selectionLabel;
    UILabel *_fpsLabel;
    NSTimer *_diagnosticsTimer;
    NSUInteger _diagnosticsTicks;
    BOOL _autoHideControls;
    BOOL _hapticsEnabled;
    UISlider *_deadzoneSlider;
    UIImpactFeedbackGenerator *_feedback;
    UIScrollView *_settingsScrollView;
    UISlider *_opacitySlider;
    UISlider *_scaleSlider;
    UISlider *_selectedScaleSlider;
    UISegmentedControl *_renderScaleControl;
    UISwitch *_hideControlsSwitch;
    UISwitch *_editLayoutSwitch;
    CGFloat _controlOpacity;
    CGFloat _controlScale;
    NSMutableDictionary<NSString *, NSNumber *> *_controlSizeScales;
    __weak UIView *_selectedControl;
    BOOL _manualControlsHidden;
    BOOL _controllerConnected;
    BOOL _editingLayout;
    BOOL _nativeTextActive;
    NSString *_loadedSettingsProfile;
    BPDocumentPickerMode _documentPickerMode;
    BOOL _documentPickerFinished;
    NSURL *_exportSnapshotURL;
    id _connectObserver;
    id _disconnectObserver;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _buttons = [NSMutableArray array];
        _editGestures = [NSMutableArray array];
        _controlSizeScales = [NSMutableDictionary dictionary];
        _controlOpacity = 0.76;
        _controlScale = 1.0;
        _moveStick = [self addStick:1 name:@"Move"];
        _cameraStick = [self addStick:2 name:@"Camera"];
        [self addButton:@"A" mask:BellpadButtonA color:[UIColor colorWithRed:0.20 green:0.72 blue:0.43 alpha:0.76]];
        [self addButton:@"B" mask:BellpadButtonB color:[UIColor colorWithRed:0.84 green:0.24 blue:0.30 alpha:0.76]];
        [self addButton:@"X" mask:BellpadButtonX color:[UIColor colorWithRed:0.30 green:0.53 blue:0.88 alpha:0.72]];
        [self addButton:@"Y" mask:BellpadButtonY color:[UIColor colorWithRed:0.88 green:0.64 blue:0.16 alpha:0.74]];
        [self addButton:@"Z" mask:BellpadButtonZ color:[UIColor colorWithWhite:0.46 alpha:0.72]];
        [self addButton:@"L" mask:BellpadButtonL color:[UIColor colorWithWhite:0.32 alpha:0.68]];
        [self addButton:@"R" mask:BellpadButtonR color:[UIColor colorWithWhite:0.32 alpha:0.68]];
        [self addButton:@"START" mask:BellpadButtonStart color:[UIColor colorWithWhite:0.28 alpha:0.68]];
        [self addButton:@"▲" mask:BellpadButtonDPadUp color:[UIColor colorWithWhite:0.26 alpha:0.64]];
        [self addButton:@"▼" mask:BellpadButtonDPadDown color:[UIColor colorWithWhite:0.26 alpha:0.64]];
        [self addButton:@"◀" mask:BellpadButtonDPadLeft color:[UIColor colorWithWhite:0.26 alpha:0.64]];
        [self addButton:@"▶" mask:BellpadButtonDPadRight color:[UIColor colorWithWhite:0.26 alpha:0.64]];
        [self buildSettingsPanel];

        sAudioAppActive.store(true, std::memory_order_release);
        sAudioInterrupted.store(false, std::memory_order_release);
        sAudioSessionReady.store(BellpadConfigureAudioSession(@"overlay installation"),
                                 std::memory_order_release);

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        __weak BPGameOverlay *weakSelf = self;
        _connectObserver = [center addObserverForName:GCControllerDidConnectNotification object:nil
                                               queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            [weakSelf refreshControllerVisibility];
        }];
        _disconnectObserver = [center addObserverForName:GCControllerDidDisconnectNotification object:nil
                                                  queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            BellpadClearInputState(BellpadInputSource::Controller);
            [weakSelf refreshControllerVisibility];
        }];
        [center addObserver:self selector:@selector(willResignActive:)
                       name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(clearInput)
                       name:UIApplicationWillTerminateNotification object:nil];
        [center addObserver:self selector:@selector(didBecomeActive:)
                       name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(hostClockChanged:)
                       name:UIApplicationSignificantTimeChangeNotification object:nil];
        [center addObserver:self selector:@selector(hostClockChanged:)
                       name:NSSystemTimeZoneDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(audioSessionInterrupted:)
                       name:AVAudioSessionInterruptionNotification
                     object:AVAudioSession.sharedInstance];
        [center addObserver:self selector:@selector(audioRouteChanged:)
                       name:AVAudioSessionRouteChangeNotification
                     object:AVAudioSession.sharedInstance];
        [center addObserver:self selector:@selector(audioMediaServicesLost:)
                       name:AVAudioSessionMediaServicesWereLostNotification
                     object:AVAudioSession.sharedInstance];
        [center addObserver:self selector:@selector(audioMediaServicesReset:)
                       name:AVAudioSessionMediaServicesWereResetNotification
                     object:AVAudioSession.sharedInstance];
#if TARGET_OS_SIMULATOR
        BellpadScheduleAudioSessionSelfTest();
#endif
        [self refreshControllerVisibility];
        _fpsLabel = [UILabel new];
        _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        _fpsLabel.textColor = UIColor.whiteColor;
        _fpsLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        _fpsLabel.textAlignment = NSTextAlignmentCenter;
        _fpsLabel.layer.cornerRadius = 8;
        _fpsLabel.clipsToBounds = YES;
        _fpsLabel.userInteractionEnabled = NO;
        [self addSubview:_fpsLabel];
        _feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        _diagnosticsTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            [weakSelf updateDiagnostics];
        }];
        [self updateDiagnostics];
    }
    return self;
}

- (void)dealloc {
    [_diagnosticsTimer invalidate];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    if (_connectObserver) [center removeObserver:_connectObserver];
    if (_disconnectObserver) [center removeObserver:_disconnectObserver];
    [center removeObserver:self];
    [self clearInput];
}

- (BPStickView *)addStick:(NSInteger)tag name:(NSString *)name {
    BPStickView *stick = [BPStickView new];
    stick.tag = tag;
    stick.delegate = self;
    stick.accessibilityLabel = name;
    [self addSubview:stick];
    [self addEditGestureToControl:stick];
    return stick;
}

- (void)addButton:(NSString *)title mask:(std::uint16_t)mask color:(UIColor *)color {
    BPGameButton *button = [BPGameButton buttonWithType:UIButtonTypeCustom];
    button.inputMask = mask;
    button.accessibilityLabel = title;
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = color;
    button.layer.borderWidth = 1.5;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.38].CGColor;
    [button addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside |
                                                                      UIControlEventTouchUpOutside |
                                                                      UIControlEventTouchCancel];
    [_buttons addObject:button];
    [self addSubview:button];
    [self addEditGestureToControl:button];
}

- (BPGameButton *)button:(NSString *)name {
    for (BPGameButton *button in _buttons) if ([button.currentTitle isEqualToString:name]) return button;
    return nil;
}

- (NSArray<UIView *> *)gameplayControls {
    NSMutableArray<UIView *> *controls = [NSMutableArray arrayWithArray:_buttons];
    if (_moveStick) [controls addObject:_moveStick];
    if (_cameraStick) [controls addObject:_cameraStick];
    return controls;
}

- (NSString *)settingsProfile {
    return self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"ipad" : @"iphone";
}

- (NSString *)settingsKey:(NSString *)name {
    return [NSString stringWithFormat:@"Bellpad.Touch.%@.%@", [self settingsProfile], name];
}

- (NSString *)graphicsSettingsKey:(NSString *)name {
    return [NSString stringWithFormat:@"Bellpad.Graphics.%@.%@", [self settingsProfile], name];
}

- (void)loadSettingsForCurrentProfile {
    NSString *profile = [self settingsProfile];
    if ([_loadedSettingsProfile isEqualToString:profile]) return;
    _loadedSettingsProfile = profile;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSNumber *opacity = [defaults objectForKey:[self settingsKey:@"opacity"]];
    NSNumber *scale = [defaults objectForKey:[self settingsKey:@"scale"]];
    NSNumber *hidden = [defaults objectForKey:[self settingsKey:@"hidden"]];
    NSNumber *autoHide = [defaults objectForKey:[self settingsKey:@"autoHide"]];
    _autoHideControls = autoHide ? autoHide.boolValue : YES;
    _hapticsEnabled = [defaults boolForKey:[self settingsKey:@"haptics"]];
    CGFloat deadzone = std::clamp<CGFloat>([defaults doubleForKey:[self settingsKey:@"deadzone"]], 0, 0.30);
    _moveStick.deadzone = _cameraStick.deadzone = deadzone;
    _deadzoneSlider.value = deadzone;
    NSDictionary *sizes = [defaults dictionaryForKey:[self settingsKey:@"sizes"]];
    NSNumber *renderScale = [defaults objectForKey:[self graphicsSettingsKey:@"renderScale"]];
    _controlOpacity = std::clamp<CGFloat>(opacity ? opacity.doubleValue : 0.76, 0.25, 1.0);
    _controlScale = std::clamp<CGFloat>(scale ? scale.doubleValue : 1.0, 0.70, 1.35);
    _manualControlsHidden = hidden ? hidden.boolValue : NO;
    _controlSizeScales = sizes ? [sizes mutableCopy] : [NSMutableDictionary dictionary];
    NSInteger renderScaleMode = std::clamp<NSInteger>(renderScale ? renderScale.integerValue : 0, 0, 4);
    _opacitySlider.value = _controlOpacity;
    _scaleSlider.value = _controlScale;
    _renderScaleControl.selectedSegmentIndex = renderScaleMode;
    sFrameBufferScaleMode.store(static_cast<int>(renderScaleMode), std::memory_order_relaxed);
    _hideControlsSwitch.on = _manualControlsHidden;
    [self updateControlAppearance];
    [self refreshMenu];
}

- (void)addEditGestureToControl:(UIView *)control {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(moveControl:)];
    pan.enabled = NO;
    pan.cancelsTouchesInView = YES;
    [control addGestureRecognizer:pan];
    [_editGestures addObject:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(selectControl:)];
    tap.enabled = NO;
    tap.cancelsTouchesInView = YES;
    [control addGestureRecognizer:tap];
    [_editGestures addObject:tap];
}

- (UIView *)settingsRowWithTitle:(NSString *)title control:(UIControl *)control {
    UIView *row = [UIView new];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.90];
    label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired
                                           forAxis:UILayoutConstraintAxisHorizontal];
    [row addSubview:label];

    control.translatesAutoresizingMaskIntoConstraints = NO;
    if ([control isKindOfClass:UISegmentedControl.class]) {
        [control setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                  forAxis:UILayoutConstraintAxisHorizontal];
    }
    [row addSubview:control];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12.0],
        [row.heightAnchor constraintEqualToConstant:34.0],
    ]];
    if ([control isKindOfClass:UISlider.class]) {
        [constraints addObject:[control.widthAnchor constraintEqualToConstant:148.0]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return row;
}

- (void)menuWillOpen {
    [self clearTouchInput];
    [self closeSettingsPanel];
    BellpadLog(@"menu opened");
}

- (void)refreshMenu {
    if (!_dataMenu) return;
    __weak BPGameOverlay *weakSelf = self;
    NSMutableArray *resolutions = [NSMutableArray array];
    NSArray *names = @[@"Device Native", @"1×", @"2×", @"3×", @"4×"];
    for (NSInteger i = 0; i < 5; ++i) {
        UIAction *action = [UIAction actionWithTitle:names[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            BPGameOverlay *owner = weakSelf;
            if (!owner) return;
            owner->_renderScaleControl.selectedSegmentIndex = i;
            [owner renderScaleChanged:owner->_renderScaleControl];
        }];
        action.state = sFrameBufferScaleMode.load() == i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [resolutions addObject:action];
    }
    UIAction *fps = [UIAction actionWithTitle:@"Show Frame Rate" image:[UIImage systemImageNamed:@"speedometer"] identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setBool:![defaults boolForKey:@"Bellpad.ShowFPS"] forKey:@"Bellpad.ShowFPS"];
        [weakSelf refreshMenu];
    }];
    fps.state = [NSUserDefaults.standardUserDefaults boolForKey:@"Bellpad.ShowFPS"] ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIMenu *display = [UIMenu menuWithTitle:@"Display" image:[UIImage systemImageNamed:@"display"] identifier:nil options:0 children:@[
        [UIMenu menuWithTitle:@"Render Resolution" children:resolutions], fps]];
    UIAction *touch = [UIAction actionWithTitle:@"Touch Control Settings…" image:[UIImage systemImageNamed:@"hand.draw"] identifier:nil handler:^(__kindof UIAction *a) {
        (void)a; [weakSelf toggleSettings];
    }];
    UIAction *autoHide = [UIAction actionWithTitle:@"Hide Touch Controls with Controller" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        BPGameOverlay *owner = weakSelf; if (!owner) return;
        owner->_autoHideControls = !owner->_autoHideControls;
        [NSUserDefaults.standardUserDefaults setBool:owner->_autoHideControls forKey:[owner settingsKey:@"autoHide"]];
        [owner updateControlAppearance]; [owner refreshMenu];
    }];
    autoHide.state = _autoHideControls ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *haptics = [UIAction actionWithTitle:@"Touch Button Haptics" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        BPGameOverlay *owner = weakSelf; if (!owner) return;
        owner->_hapticsEnabled = !owner->_hapticsEnabled;
        [NSUserDefaults.standardUserDefaults setBool:owner->_hapticsEnabled forKey:[owner settingsKey:@"haptics"]];
        [owner refreshMenu];
    }];
    haptics.state = _hapticsEnabled ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *help = [UIAction actionWithTitle:@"Controller & Keyboard Help" image:[UIImage systemImageNamed:@"keyboard"] identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        [weakSelf presentMessageWithTitle:@"Controls" message:[NSString stringWithFormat:@"%lu controller(s) connected. Controllers reconnect automatically. Touch controls can stay visible alongside a controller.\n\nKeyboard: WASD moves; arrow keys control the C-stick. Space = A, Shift = B, X/Y = X/Y, Return = Start, Z = Z, Q/E = L/R, I/J/K/L = D-pad.\n\nTouch layout and sizes are saved separately for iPhone and iPad. Editing a layout does not send game input. Haptics require supported hardware.", (unsigned long)GCController.controllers.count]];
    }];
    UIMenu *controls = [UIMenu menuWithTitle:@"Controls" image:[UIImage systemImageNamed:@"gamecontroller"] identifier:nil options:0 children:@[touch, autoHide, haptics, help]];
    UIAction *report = [UIAction actionWithTitle:@"Share Diagnostic Report…" image:[UIImage systemImageNamed:@"doc.text.magnifyingglass"] identifier:nil handler:^(__kindof UIAction *a) {
        (void)a; [weakSelf shareDiagnostics];
    }];
    UIAction *issues = [UIAction actionWithTitle:@"Bellpad Support on GitHub" image:[UIImage systemImageNamed:@"questionmark.circle"] identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/chrissotraidis/bellpad/issues"] options:@{} completionHandler:nil];
    }];
    UIAction *about = [UIAction actionWithTitle:@"About This Build" image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        NSBundle *bundle = NSBundle.mainBundle;
        [weakSelf presentMessageWithTitle:@"Bellpad" message:[NSString stringWithFormat:@"Version %@ (build %@)\n\nNative Apple integration of birabittoh/ACGC-PC-Port, ACreTeam/ac-decomp and encounter/aurora. Source and third-party notices are included with this build.\n\nDiagnostic logs stay on this device until you choose to share them. No game images, saves, text input or signing material are attached.", [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]]];
    }];
    _settingsButton.menu = [UIMenu menuWithTitle:@"Bellpad" children:@[display, controls, _dataMenu, report, issues, about]];
}

- (void)deadzoneChanged:(UISlider *)slider {
    _moveStick.deadzone = _cameraStick.deadzone = slider.value;
    slider.accessibilityValue = [NSString stringWithFormat:@"%.0f percent", slider.value * 100];
    [NSUserDefaults.standardUserDefaults setDouble:slider.value forKey:[self settingsKey:@"deadzone"]];
}

- (void)updateDiagnostics {
    double fps = bellpad_diagnostics_fps();
    _fpsLabel.hidden = ![NSUserDefaults.standardUserDefaults boolForKey:@"Bellpad.ShowFPS"] || _nativeTextActive;
    _fpsLabel.text = [NSString stringWithFormat:@"%.0f FPS", fps];
    if (++_diagnosticsTicks % 60 == 0)
        BellpadLog(@"health frame-loop=%.1fHz thermal=%ld active=%d controllers=%lu render=%d", fps, (long)NSProcessInfo.processInfo.thermalState, UIApplication.sharedApplication.applicationState == UIApplicationStateActive, (unsigned long)GCController.controllers.count, sFrameBufferScaleMode.load());
}

- (void)shareDiagnostics {
    [self clearTouchInput];
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:@"Share Diagnostic Report"
        message:@"Describe what happened and what you were doing. Bellpad adds build details and bounded recent logs. Game images, saves and typed game text are excluded. Review the report before sharing; GitHub attachments are public. Nothing uploads automatically."
        preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"What went wrong?"; }];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"Steps and how often it happens"; }];
    [prompt addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak BPGameOverlay *weakSelf = self;
    [prompt addAction:[UIAlertAction actionWithTitle:@"Create Report…" style:UIAlertActionStyleDefault handler:^(__kindof UIAlertAction *action) {
        (void)action;
        BPGameOverlay *owner = weakSelf; if (!owner) return;
        NSString *context = [NSString stringWithFormat:@"%@\nControllers=%lu renderScale=%d thermal=%ld layout=%@ autoHide=%d", prompt.textFields[1].text ?: @"", (unsigned long)GCController.controllers.count, sFrameBufferScaleMode.load(), (long)NSProcessInfo.processInfo.thermalState, [owner settingsProfile], owner->_autoHideControls];
        BellpadLog(@"diagnostic report requested");
        NSError *error = nil;
        NSURL *url = BellpadDiagnosticsReport(prompt.textFields[0].text ?: @"", context, &error);
        if (!url) { [owner presentMessageWithTitle:@"Report Unavailable" message:@"The report could not be written. Check available storage and try again."]; return; }
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        share.popoverPresentationController.sourceView = owner->_settingsButton;
        share.popoverPresentationController.sourceRect = owner->_settingsButton.bounds;
        [[owner presentationController] presentViewController:share animated:YES completion:nil];
    }]];
    [[self presentationController] presentViewController:prompt animated:YES completion:nil];
}

- (void)buildSettingsPanel {
    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_settingsButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    [_settingsButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _settingsButton.titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    _settingsButton.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.72];
    _settingsButton.layer.cornerRadius = 24.0;
    _settingsButton.layer.borderWidth = 1.0;
    _settingsButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    _settingsButton.accessibilityLabel = @"Bellpad menu";
    _settingsButton.accessibilityIdentifier = @"bellpad.menu";
    _settingsButton.tintColor = UIColor.whiteColor;
    _settingsButton.showsMenuAsPrimaryAction = YES;
    [_settingsButton addTarget:self action:@selector(menuWillOpen) forControlEvents:UIControlEventMenuActionTriggered];
    [self addSubview:_settingsButton];

    _settingsPanel = [UIView new];
    _settingsPanel.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.94];
    _settingsPanel.layer.cornerRadius = 16.0;
    _settingsPanel.layer.borderWidth = 1.0;
    _settingsPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    _settingsPanel.hidden = YES;
    [self addSubview:_settingsPanel];

    UILabel *title = [UILabel new];
    title.text = @"Touch Controls";
    title.accessibilityHint = @"Drag this title to move the panel away from controls.";
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.userInteractionEnabled = YES;
    [title addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveSettingsPanel:)]];
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];

    _opacitySlider = [UISlider new];
    _opacitySlider.minimumValue = 0.25;
    _opacitySlider.maximumValue = 1.0;
    _opacitySlider.accessibilityLabel = @"Control opacity";
    [_opacitySlider addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];

    _scaleSlider = [UISlider new];
    _scaleSlider.minimumValue = 0.70;
    _scaleSlider.maximumValue = 1.35;
    _scaleSlider.accessibilityLabel = @"Control size";
    [_scaleSlider addTarget:self action:@selector(scaleChanged:) forControlEvents:UIControlEventValueChanged];

    _selectedScaleSlider = [UISlider new];
    _selectedScaleSlider.minimumValue = 0.60;
    _selectedScaleSlider.maximumValue = 1.75;
    _selectedScaleSlider.value = 1.0;
    _selectedScaleSlider.enabled = NO;
    _selectedScaleSlider.accessibilityLabel = @"Selected control size";
    [_selectedScaleSlider addTarget:self action:@selector(selectedScaleChanged:)
                    forControlEvents:UIControlEventValueChanged];

    _renderScaleControl = [[UISegmentedControl alloc] initWithItems:@[@"Native", @"1×", @"2×", @"3×", @"4×"]];
    _renderScaleControl.selectedSegmentIndex = 0;
    _renderScaleControl.accessibilityLabel = @"Render resolution";
    [_renderScaleControl addTarget:self action:@selector(renderScaleChanged:)
                  forControlEvents:UIControlEventValueChanged];

    _hideControlsSwitch = [UISwitch new];
    _hideControlsSwitch.accessibilityLabel = @"Hide touch controls";
    [_hideControlsSwitch addTarget:self action:@selector(hiddenChanged:) forControlEvents:UIControlEventValueChanged];

    _editLayoutSwitch = [UISwitch new];
    _editLayoutSwitch.accessibilityLabel = @"Edit touch control positions";
    [_editLayoutSwitch addTarget:self action:@selector(editLayoutChanged:) forControlEvents:UIControlEventValueChanged];

    _deadzoneSlider = [UISlider new];
    _deadzoneSlider.minimumValue = 0;
    _deadzoneSlider.maximumValue = 0.30;
    _deadzoneSlider.accessibilityLabel = @"Touch stick dead zone";
    [_deadzoneSlider addTarget:self action:@selector(deadzoneChanged:) forControlEvents:UIControlEventValueChanged];
    _selectionLabel = [UILabel new];
    _selectionLabel.text = @"Enable Move Controls, then tap or drag a control to adjust it.";
    _selectionLabel.numberOfLines = 0;
    _selectionLabel.textColor = UIColor.lightGrayColor;
    _selectionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.accessibilityIdentifier = @"bellpad.controls.done";
    [done addTarget:self action:@selector(closeSettingsPanel) forControlEvents:UIControlEventTouchUpInside];
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"Reset This Device Layout" forState:UIControlStateNormal];
    [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    reset.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.88];
    reset.layer.cornerRadius = 10.0;
    reset.accessibilityLabel = @"Reset touch control layout";
    [reset addTarget:self action:@selector(confirmResetControlSettings)
        forControlEvents:UIControlEventTouchUpInside];

    UIButton *data = [UIButton buttonWithType:UIButtonTypeSystem];
    [data setTitle:@"Game Data & Saves…" forState:UIControlStateNormal];
    [data setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    data.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    data.backgroundColor = [UIColor colorWithRed:0.20 green:0.38 blue:0.58 alpha:0.92];
    data.layer.cornerRadius = 10.0;
    data.accessibilityLabel = @"Manage game data and saves";
    __weak BPGameOverlay *weakSelf = self;
    data.menu = [UIMenu menuWithTitle:@"Game Data & Saves" children:@[
        [UIAction actionWithTitle:@"Export Dolphin GCI Save"
                            image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf beginSaveExport];
        }],
        [UIAction actionWithTitle:@"Import Dolphin GCI Save"
                            image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf beginSaveImport];
        }],
        [UIAction actionWithTitle:@"Change or Reimport Game Data"
                            image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf scheduleGameDataChange];
        }],
        [UIAction actionWithTitle:@"Remove Stored Game Data"
                            image:[UIImage systemImageNamed:@"trash"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf confirmGameDataRemoval];
        }],
    ]];
    data.showsMenuAsPrimaryAction = YES;
    _dataMenu = data.menu;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self settingsRowWithTitle:@"Opacity" control:_opacitySlider],
        [self settingsRowWithTitle:@"All sizes" control:_scaleSlider],
        [self settingsRowWithTitle:@"Selected size" control:_selectedScaleSlider],
        [self settingsRowWithTitle:@"Stick dead zone" control:_deadzoneSlider],
        _selectionLabel,
        [self settingsRowWithTitle:@"Hide controls" control:_hideControlsSwitch],
        [self settingsRowWithTitle:@"Move controls" control:_editLayoutSwitch],
        reset,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4.0;

    _settingsScrollView = [UIScrollView new];
    _settingsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsScrollView.alwaysBounceVertical = NO;
    _settingsScrollView.showsVerticalScrollIndicator = YES;
    [_settingsPanel addSubview:title];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [_settingsPanel addSubview:done];
    [_settingsPanel addSubview:_settingsScrollView];
    [_settingsScrollView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [_settingsScrollView.leadingAnchor constraintEqualToAnchor:_settingsPanel.leadingAnchor],
        [_settingsScrollView.trailingAnchor constraintEqualToAnchor:_settingsPanel.trailingAnchor],
        [_settingsScrollView.topAnchor constraintEqualToAnchor:_settingsPanel.topAnchor constant:44.0],
        [_settingsScrollView.bottomAnchor constraintEqualToAnchor:_settingsPanel.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.topAnchor constant:8.0],
        [stack.bottomAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.bottomAnchor constant:-8.0],
        [stack.widthAnchor constraintEqualToAnchor:_settingsScrollView.frameLayoutGuide.widthAnchor constant:-32.0],
        [reset.heightAnchor constraintEqualToConstant:40.0],
        [title.leadingAnchor constraintEqualToAnchor:_settingsPanel.leadingAnchor constant:16.0],
        [title.centerYAnchor constraintEqualToAnchor:done.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:done.leadingAnchor constant:-8.0],
        [done.topAnchor constraintEqualToAnchor:_settingsPanel.topAnchor],
        [done.trailingAnchor constraintEqualToAnchor:_settingsPanel.trailingAnchor constant:-8.0],
        [done.widthAnchor constraintEqualToConstant:60.0],
        [done.heightAnchor constraintEqualToConstant:44.0],
    ]];
    [self refreshMenu];
}

- (void)moveSettingsPanel:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self];
    _settingsPanelOffset.x += delta.x;
    _settingsPanelOffset.y += delta.y;
    [gesture setTranslation:CGPointZero inView:self];
    [self setNeedsLayout];
}

- (void)toggleSettings {
    if (_settingsPanel.hidden) {
        [self clearTouchInput];
        _settingsPanel.hidden = NO;
        BellpadLog(@"touch settings opened");
        [self bringSubviewToFront:_settingsPanel];
        [self bringSubviewToFront:_settingsButton];
    } else {
        [self closeSettingsPanel];
    }
}

- (void)closeSettingsPanel {
    _settingsPanel.hidden = YES;
    if (_editingLayout) {
        _editLayoutSwitch.on = NO;
        [self editLayoutChanged:_editLayoutSwitch];
    }
}

- (UIViewController *)presentationController {
    UIViewController *controller = BellpadGameWindow().rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    return controller;
}

- (void)presentMessageWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[self presentationController] presentViewController:alert animated:YES completion:nil];
}

- (void)scheduleGameDataChange {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:BPChangeGameDataOnNextLaunchKey];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:BPRemoveGameDataOnNextLaunchKey];
    [self closeSettingsPanel];
    [self presentMessageWithTitle:@"Reimport on Next Launch"
                          message:@"Close and reopen Bellpad. Before the game starts, Files will ask for a supported ISO or GCM. Your current retained image remains available until a replacement passes validation."];
}

- (void)confirmGameDataRemoval {
    [self closeSettingsPanel];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove Stored Game Data?"
        message:@"The private retained ISO/GCM will be removed the next time Bellpad launches, then Files will request replacement game data. Your GCI save and backups are not removed."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove on Relaunch"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__kindof UIAlertAction *action) {
        (void)action;
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:BPRemoveGameDataOnNextLaunchKey];
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:BPChangeGameDataOnNextLaunchKey];
    }]];
    [[self presentationController] presentViewController:alert animated:YES completion:nil];
}

- (void)beginSaveImport {
    BellpadLog(@"save import requested");
    if (!BellpadResolvedApplicationSupportURL()) {
        [self presentMessageWithTitle:@"Save Import Unavailable"
                              message:@"Bellpad has not finished preparing Application Support yet."];
        return;
    }
    UTType *gciType = [UTType typeWithFilenameExtension:@"gci"] ?: UTTypeData;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ gciType ] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    _documentPickerMode = BPDocumentPickerModeImportSave;
    [self closeSettingsPanel];
    [self presentDocumentPickerWhileHoldingGameLoop:picker];
}

- (void)beginSaveExport {
    BellpadLog(@"save export requested");
    NSURL *source = BellpadCanonicalSaveURL();
    if (!source || ![NSFileManager.defaultManager fileExistsAtPath:source.path]) {
        [self presentMessageWithTitle:@"No Save to Export"
                              message:@"Create and save a town before exporting a Dolphin-compatible GCI file."];
        return;
    }

    NSData *data = nil;
    NSString *validationError = BellpadLoadValidatedGCI(source, &data);
    if (validationError) {
        [self presentMessageWithTitle:@"Save Export Failed" message:validationError];
        return;
    }

    NSURL *snapshot = [NSFileManager.defaultManager.temporaryDirectory
        URLByAppendingPathComponent:@"Bellpad-Dolphin-Save.gci"];
    [NSFileManager.defaultManager removeItemAtURL:snapshot error:nil];
    NSError *error = nil;
    [data writeToURL:snapshot options:NSDataWritingAtomic error:&error];
    if (error) {
        [self presentMessageWithTitle:@"Save Export Failed" message:error.localizedDescription];
        return;
    }

    _exportSnapshotURL = snapshot;
    _documentPickerMode = BPDocumentPickerModeExportSave;
    [self closeSettingsPanel];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForExportingURLs:@[ snapshot ] asCopy:YES];
    picker.delegate = self;
    [self presentDocumentPickerWhileHoldingGameLoop:picker];
}

- (void)presentDocumentPickerWhileHoldingGameLoop:(UIDocumentPickerViewController *)picker {
    UIViewController *presenter = [self presentationController];
    if (!presenter) {
        if (_documentPickerMode == BPDocumentPickerModeExportSave) [self clearExportSnapshot];
        _documentPickerMode = BPDocumentPickerModeNone;
        [self presentMessageWithTitle:@"Files Unavailable"
                              message:@"Bellpad could not present the system Files browser."];
        return;
    }

    // Aurora's SDL entry point runs on UIKit's main thread. Returning from this
    // action would let the Metal game loop keep submitting frames while the
    // system document picker temporarily owns the scene. Pumping UIKit here
    // keeps Files fully interactive while deliberately holding game rendering.
    _documentPickerFinished = NO;
    [presenter presentViewController:picker animated:YES completion:nil];
    while (!_documentPickerFinished) {
        @autoreleasepool {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
            CFRunLoopRunInMode((CFStringRef)UITrackingRunLoopMode, 0.01, true);
        }
    }

    // The delegate callback can arrive just before UIKit finishes the picker's
    // automatic dismissal. Do not resume Metal until its presentation surface
    // has actually left the window.
    while (picker.presentingViewController && picker.viewIfLoaded.window) {
        @autoreleasepool {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
            CFRunLoopRunInMode((CFStringRef)UITrackingRunLoopMode, 0.01, true);
        }
    }
}

- (void)clearExportSnapshot {
    if (_exportSnapshotURL) {
        [NSFileManager.defaultManager removeItemAtURL:_exportSnapshotURL error:nil];
        _exportSnapshotURL = nil;
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    if (_documentPickerMode == BPDocumentPickerModeExportSave) [self clearExportSnapshot];
    _documentPickerMode = BPDocumentPickerModeNone;
    _documentPickerFinished = YES;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    BPDocumentPickerMode mode = _documentPickerMode;
    _documentPickerMode = BPDocumentPickerModeNone;
    _documentPickerFinished = YES;
    if (mode == BPDocumentPickerModeExportSave) {
        [self clearExportSnapshot];
        return;
    }
    if (mode != BPDocumentPickerModeImportSave) return;

    NSURL *source = urls.firstObject;
    if (!source) return;
    __weak BPGameOverlay *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL accessed = [source startAccessingSecurityScopedResource];
        NSData *data = nil;
        NSString *message = BellpadLoadValidatedGCI(source, &data);
        if (accessed) [source stopAccessingSecurityScopedResource];

        NSURL *pending = BellpadPendingSaveURL();
        NSError *error = nil;
        if (!message && !pending) message = @"Bellpad could not resolve its save-import directory.";
        if (!message) {
            [NSFileManager.defaultManager createDirectoryAtURL:pending.URLByDeletingLastPathComponent
                                   withIntermediateDirectories:YES attributes:nil error:&error];
            if (!error) [data writeToURL:pending options:NSDataWritingAtomic error:&error];
            if (!error) BellpadSynchronizeFileAndDirectory(pending, &error);
            if (error) message = [NSString stringWithFormat:@"The GCI could not be staged: %@",
                                                            error.localizedDescription];
        }
        if (!message) message = BellpadLoadValidatedGCI(pending, nullptr);

        dispatch_async(dispatch_get_main_queue(), ^{
            BPGameOverlay *strongSelf = weakSelf;
            if (!strongSelf) return;
            if (message) {
                [strongSelf presentMessageWithTitle:@"Save Import Failed" message:message];
            } else {
                [strongSelf presentMessageWithTitle:@"Save Ready to Import"
                    message:@"The validated GCI will replace the active town before the next launch, and the current file will be retained as a pre-import backup. Close Bellpad without saving again, then reopen it now."];
            }
        });
    });
}

- (void)opacityChanged:(UISlider *)slider {
    _controlOpacity = slider.value;
    [NSUserDefaults.standardUserDefaults setDouble:_controlOpacity
                                            forKey:[self settingsKey:@"opacity"]];
    [self updateControlAppearance];
}

- (void)scaleChanged:(UISlider *)slider {
    _controlScale = slider.value;
    [NSUserDefaults.standardUserDefaults setDouble:_controlScale
                                            forKey:[self settingsKey:@"scale"]];
    [self setNeedsLayout];
}

- (void)renderScaleChanged:(UISegmentedControl *)control {
    NSInteger mode = std::clamp<NSInteger>(control.selectedSegmentIndex, 0, 4);
    [NSUserDefaults.standardUserDefaults setInteger:mode
                                             forKey:[self graphicsSettingsKey:@"renderScale"]];
    sFrameBufferScaleMode.store(static_cast<int>(mode), std::memory_order_relaxed);
    BellpadLog(@"render scale selected=%ld", (long)mode);
    [self refreshMenu];
}

- (void)hiddenChanged:(UISwitch *)toggle {
    _manualControlsHidden = toggle.on;
    [NSUserDefaults.standardUserDefaults setBool:_manualControlsHidden
                                          forKey:[self settingsKey:@"hidden"]];
    if (_manualControlsHidden && _editingLayout) {
        _editLayoutSwitch.on = NO;
        [self editLayoutChanged:_editLayoutSwitch];
    }
    [self updateControlAppearance];
}

- (void)editLayoutChanged:(UISwitch *)toggle {
    _editingLayout = toggle.on;
    if (_editingLayout && _manualControlsHidden) {
        _manualControlsHidden = NO;
        _hideControlsSwitch.on = NO;
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:[self settingsKey:@"hidden"]];
    }
    BellpadLog(@"touch layout editing=%@", _editingLayout ? @"on" : @"off");
    [self clearTouchInput];
    for (UIGestureRecognizer *gesture in _editGestures) gesture.enabled = _editingLayout;
    if (!_editingLayout) {
        _selectedControl = nil;
        _selectionLabel.text = @"Enable Move Controls, then tap or drag a control to adjust it.";
        _selectedScaleSlider.enabled = NO;
        _selectedScaleSlider.value = 1.0;
    }
    [self updateControlAppearance];
}

- (void)confirmResetControlSettings {
    NSString *device = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad
        ? @"iPad" : @"iPhone";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Reset %@ Touch Layout?", device]
                         message:@"This resets every saved control position and size on this device type."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel handler:nil]];
    __weak BPGameOverlay *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset Layout"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(__kindof UIAlertAction *action) {
        (void)action;
        [weakSelf resetControlSettings];
    }]];
    [[self presentationController] presentViewController:alert animated:YES completion:nil];
}

- (void)resetControlSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:[self settingsKey:@"centers"]];
    [defaults removeObjectForKey:[self settingsKey:@"opacity"]];
    [defaults removeObjectForKey:[self settingsKey:@"scale"]];
    [defaults removeObjectForKey:[self settingsKey:@"sizes"]];
    [defaults removeObjectForKey:[self settingsKey:@"hidden"]];
    _controlOpacity = 0.76;
    _controlScale = 1.0;
    _controlSizeScales = [NSMutableDictionary dictionary];
    _manualControlsHidden = NO;
    _opacitySlider.value = _controlOpacity;
    _scaleSlider.value = _controlScale;
    _selectedScaleSlider.value = 1.0;
    _selectedScaleSlider.enabled = NO;
    _selectedControl = nil;
    _hideControlsSwitch.on = NO;
    _editLayoutSwitch.on = NO;
    [self editLayoutChanged:_editLayoutSwitch];
    [self setNeedsLayout];
}

- (void)updateControlAppearance {
    BOOL hidden = _nativeTextActive || (!_editingLayout && (_manualControlsHidden || (_controllerConnected && _autoHideControls)));
    if (hidden) [self clearTouchInput];
    for (UIView *control in [self gameplayControls]) {
        control.hidden = hidden;
        control.alpha = _controlOpacity;
        control.userInteractionEnabled = !hidden;
        UIColor *border = [UIColor colorWithWhite:1.0 alpha:0.42];
        if (_editingLayout) {
            border = control == _selectedControl
                ? [UIColor colorWithRed:0.20 green:0.78 blue:1.0 alpha:1.0]
                : [UIColor colorWithRed:1.0 green:0.78 blue:0.20 alpha:0.95];
        }
        control.layer.borderColor = border.CGColor;
    }
}

- (void)setNativeTextActive:(BOOL)active {
    if (_nativeTextActive == active) return;
    _nativeTextActive = active;
    if (active) [self closeSettingsPanel];
    _settingsButton.hidden = active;
    [self updateControlAppearance];
}

- (void)selectControlForEditing:(UIView *)control {
    if (!_editingLayout || !control.accessibilityLabel) return;
    _selectedControl = control;
    _selectionLabel.text = [NSString stringWithFormat:@"Editing %@ — drag to move; use Selected Size to resize.", control.accessibilityLabel];
    NSNumber *saved = _controlSizeScales[control.accessibilityLabel];
    _selectedScaleSlider.value = std::clamp<CGFloat>(saved ? saved.doubleValue : 1.0,
                                                     0.60, 1.75);
    _selectedScaleSlider.enabled = YES;
    _selectedScaleSlider.accessibilityLabel = [NSString stringWithFormat:@"%@ size",
                                                control.accessibilityLabel];
    [self updateControlAppearance];
}

- (void)selectControl:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self selectControlForEditing:gesture.view];
    }
}

- (void)selectedScaleChanged:(UISlider *)slider {
    UIView *control = _selectedControl;
    NSString *identifier = control.accessibilityLabel;
    if (!_editingLayout || !control || !identifier) return;
    CGFloat scale = std::clamp<CGFloat>(slider.value, 0.60, 1.75);
    _controlSizeScales[identifier] = @(scale);
    [NSUserDefaults.standardUserDefaults setObject:_controlSizeScales
                                            forKey:[self settingsKey:@"sizes"]];
    [self setNeedsLayout];
}

- (void)moveControl:(UIPanGestureRecognizer *)gesture {
    if (!_editingLayout || !gesture.view) return;
    UIView *control = gesture.view;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self selectControlForEditing:control];
    }
    CGPoint translation = [gesture translationInView:self];
    CGPoint center = CGPointMake(control.center.x + translation.x, control.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self];

    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    CGFloat halfWidth = control.bounds.size.width * 0.5;
    CGFloat halfHeight = control.bounds.size.height * 0.5;
    center.x = std::clamp<CGFloat>(center.x, CGRectGetMinX(safe) + halfWidth,
                                  CGRectGetMaxX(safe) - halfWidth);
    center.y = std::clamp<CGFloat>(center.y, CGRectGetMinY(safe) + halfHeight,
                                  CGRectGetMaxY(safe) - halfHeight);
    control.center = center;

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled) {
        NSString *identifier = control.accessibilityLabel;
        if (!identifier || safe.size.width <= 0.0 || safe.size.height <= 0.0) return;
        CGPoint normalized = CGPointMake((center.x - CGRectGetMinX(safe)) / safe.size.width,
                                         (center.y - CGRectGetMinY(safe)) / safe.size.height);
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *existing = [defaults dictionaryForKey:[self settingsKey:@"centers"]];
        NSMutableDictionary *centers = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
        centers[identifier] = NSStringFromCGPoint(normalized);
        [defaults setObject:centers forKey:[self settingsKey:@"centers"]];
    }
}

- (void)applySavedControlSizes {
    for (UIView *control in [self gameplayControls]) {
        NSNumber *saved = _controlSizeScales[control.accessibilityLabel];
        CGFloat scale = std::clamp<CGFloat>(saved ? saved.doubleValue : 1.0, 0.60, 1.75);
        if (std::abs(scale - 1.0) < 0.001) continue;
        CGPoint center = control.center;
        CGSize size = control.bounds.size;
        control.bounds = CGRectMake(0.0, 0.0, size.width * scale, size.height * scale);
        control.center = center;
    }
}

- (void)applySavedControlCentersInSafeRect:(CGRect)safe {
    NSDictionary *centers = [NSUserDefaults.standardUserDefaults
        dictionaryForKey:[self settingsKey:@"centers"]];
    if (!centers || safe.size.width <= 0.0 || safe.size.height <= 0.0) return;
    for (UIView *control in [self gameplayControls]) {
        NSString *identifier = control.accessibilityLabel;
        if (!identifier) continue;
        NSString *value = centers[identifier];
        if (![value isKindOfClass:NSString.class]) continue;
        CGPoint normalized = CGPointFromString(value);
        CGPoint center = CGPointMake(CGRectGetMinX(safe) + normalized.x * safe.size.width,
                                     CGRectGetMinY(safe) + normalized.y * safe.size.height);
        CGFloat halfWidth = control.bounds.size.width * 0.5;
        CGFloat halfHeight = control.bounds.size.height * 0.5;
        center.x = std::clamp<CGFloat>(center.x, CGRectGetMinX(safe) + halfWidth,
                                      CGRectGetMaxX(safe) - halfWidth);
        center.y = std::clamp<CGFloat>(center.y, CGRectGetMinY(safe) + halfHeight,
                                      CGRectGetMaxY(safe) - halfHeight);
        control.center = center;
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) return nil;
    for (UIView *child in [self.subviews reverseObjectEnumerator]) {
        CGPoint local = [child convertPoint:point fromView:self];
        UIView *hit = [child hitTest:local withEvent:event];
        if (hit) return hit;
    }
    return nil;
}

- (void)buttonDown:(BPGameButton *)button {
    if (_editingLayout) return;
    if (_hapticsEnabled) [_feedback impactOccurred];
    _state.buttons |= button.inputMask;
    if (button.inputMask == BellpadButtonL) _state.triggerL = 255;
    if (button.inputMask == BellpadButtonR) _state.triggerR = 255;
    button.transform = CGAffineTransformMakeScale(0.92, 0.92);
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)buttonUp:(BPGameButton *)button {
    if (_editingLayout) return;
    _state.buttons &= ~button.inputMask;
    if (button.inputMask == BellpadButtonL) _state.triggerL = 0;
    if (button.inputMask == BellpadButtonR) _state.triggerR = 0;
    button.transform = CGAffineTransformIdentity;
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)stick:(NSInteger)tag changedX:(std::int8_t)x y:(std::int8_t)y {
    if (_editingLayout) return;
    if (tag == 1) { _state.stickX = x; _state.stickY = y; }
    else { _state.cStickX = x; _state.cStickY = y; }
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)clearTouchInput {
    _state = {};
    BellpadClearInputState(BellpadInputSource::Touch);
    for (BPGameButton *button in _buttons) button.transform = CGAffineTransformIdentity;
    [_moveStick reset];
    [_cameraStick reset];
}

- (void)clearInput {
    [self clearTouchInput];
    BellpadClearInputState(BellpadInputSource::Controller);
}

- (void)didBecomeActive:(NSNotification *)notification {
    (void)notification;
    sAudioAppActive.store(true, std::memory_order_release);
    BOOL ready = !sAudioInterrupted.load(std::memory_order_acquire) &&
        BellpadConfigureAudioSession(@"UIApplicationDidBecomeActive");
    sAudioSessionReady.store(ready, std::memory_order_release);
    if (sWasInactive.exchange(false, std::memory_order_acq_rel)) {
        sDidBecomeActive.store(true, std::memory_order_release);
    }
    BellpadClearInputState(BellpadInputSource::Controller);
    [self refreshControllerVisibility];
}

- (void)willResignActive:(NSNotification *)notification {
    BellpadLog(@"application resigning active; touch input cleared");
    (void)notification;
    [self clearInput];
    sAudioAppActive.store(false, std::memory_order_release);
    sAudioSessionReady.store(false, std::memory_order_release);
    sWasInactive.store(true, std::memory_order_release);
    sWillResignActive.store(true, std::memory_order_release);
}

- (void)hostClockChanged:(NSNotification *)notification {
    (void)notification;
    sHostClockChanged.store(true, std::memory_order_release);
}

- (void)audioSessionInterrupted:(NSNotification *)notification {
    AVAudioSessionInterruptionType type = (AVAudioSessionInterruptionType)
        [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        sAudioInterrupted.store(true, std::memory_order_release);
        sAudioSessionReady.store(false, std::memory_order_release);
        sAudioInterruptionBegan.store(true, std::memory_order_release);
        BellpadLog(@"[AudioSession] Interruption began");
        return;
    }

    AVAudioSessionInterruptionOptions options = (AVAudioSessionInterruptionOptions)
        [notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
    const BOOL shouldResume = (options & AVAudioSessionInterruptionOptionShouldResume) != 0;
    sAudioInterrupted.store(false, std::memory_order_release);
    BOOL ready = shouldResume && sAudioAppActive.load(std::memory_order_acquire) &&
        BellpadConfigureAudioSession(@"interruption end");
    sAudioSessionReady.store(ready, std::memory_order_release);
    sAudioInterruptionEnded.store(true, std::memory_order_release);
    BellpadLog(@"[AudioSession] Interruption ended (resume %@)", shouldResume ? @"allowed" : @"deferred");
}

- (void)audioRouteChanged:(NSNotification *)notification {
    AVAudioSessionRouteChangeReason reason = (AVAudioSessionRouteChangeReason)
        [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason == AVAudioSessionRouteChangeReasonCategoryChange) return;

    AVAudioSession *session = AVAudioSession.sharedInstance;
    const BOOL ready = sAudioAppActive.load(std::memory_order_acquire) &&
        !sAudioInterrupted.load(std::memory_order_acquire) && session.currentRoute.outputs.count > 0;
    sAudioSessionReady.store(ready, std::memory_order_release);
    sAudioRouteChanged.store(true, std::memory_order_release);
    BellpadLog(@"[AudioSession] Route changed (reason %lu, outputs %lu)",
          (unsigned long)reason, (unsigned long)session.currentRoute.outputs.count);
}

- (void)audioMediaServicesLost:(NSNotification *)notification {
    (void)notification;
    sAudioInterrupted.store(true, std::memory_order_release);
    sAudioSessionReady.store(false, std::memory_order_release);
    sAudioInterruptionBegan.store(true, std::memory_order_release);
    BellpadLog(@"[AudioSession] Media services lost");
}

- (void)audioMediaServicesReset:(NSNotification *)notification {
    (void)notification;
    sAudioInterrupted.store(false, std::memory_order_release);
    BOOL ready = sAudioAppActive.load(std::memory_order_acquire) &&
        BellpadConfigureAudioSession(@"media-services reset");
    sAudioSessionReady.store(ready, std::memory_order_release);
    sAudioInterruptionEnded.store(true, std::memory_order_release);
    sAudioRouteChanged.store(true, std::memory_order_release);
    BellpadLog(@"[AudioSession] Media services reset");
}

- (void)refreshControllerVisibility {
    BOOL connected = NO;
#if !TARGET_OS_SIMULATOR
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad) { connected = YES; break; }
    }
#endif
    if (connected) [self clearTouchInput];
    else BellpadClearInputState(BellpadInputSource::Controller);
    if (_controllerConnected != connected) BellpadLog(@"controller connection=%@ count=%lu", connected ? @"connected" : @"disconnected", (unsigned long)GCController.controllers.count);
    _controllerConnected = connected;
    [self refreshMenu];
    [self updateControlAppearance];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    [self loadSettingsForCurrentProfile];
    BOOL pad = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad && safe.size.width >= 1000.0;
    CGFloat baseScale = pad ? 1.0 : std::min<CGFloat>(1.0, std::min(safe.size.width / 800.0, safe.size.height / 380.0));
    CGFloat scale = baseScale * _controlScale;
    CGFloat margin = pad ? 34.0 : std::max<CGFloat>(8.0, 18.0 * baseScale);
    CGFloat stick = (pad ? 172.0 : 126.0 * baseScale) * _controlScale;
    CGFloat small = (pad ? 62.0 : 46.0 * baseScale) * _controlScale;
    CGFloat medium = (pad ? 76.0 : 58.0 * baseScale) * _controlScale;
    CGFloat large = (pad ? 104.0 : 78.0 * baseScale) * _controlScale;
    _moveStick.frame = CGRectMake(CGRectGetMinX(safe) + margin, CGRectGetMaxY(safe) - stick - margin, stick, stick);
    CGFloat camera = (pad ? 112.0 : 86.0 * baseScale) * _controlScale;
    _cameraStick.frame = CGRectMake(CGRectGetMaxX(safe) - margin - camera, CGRectGetMaxY(safe) - margin - camera, camera, camera);

    BPGameButton *a = [self button:@"A"], *b = [self button:@"B"], *x = [self button:@"X"], *y = [self button:@"Y"];
    a.frame = CGRectMake(CGRectGetMaxX(safe) - margin - large, CGRectGetMaxY(safe) - margin - camera - large - 18.0 * scale, large, large);
    b.frame = CGRectMake(CGRectGetMinX(a.frame) - medium - 12.0 * scale, CGRectGetMidY(a.frame) + 8.0, medium, medium);
    x.frame = CGRectMake(CGRectGetMidX(a.frame) - small * 0.5, CGRectGetMinY(a.frame) - small - 10.0 * scale, small, small);
    y.frame = CGRectMake(CGRectGetMinX(a.frame) - small - 8.0 * scale, CGRectGetMinY(a.frame) - small + 8.0, small, small);

    CGFloat shoulderWidth = (pad ? 132.0 : 94.0 * baseScale) * _controlScale;
    CGFloat shoulderY = CGRectGetMinY(safe) + (pad ? 92.0 : 68.0 * baseScale);
    [self button:@"L"].frame = CGRectMake(CGRectGetMinX(safe) + margin, shoulderY, shoulderWidth, small);
    [self button:@"R"].frame = CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth, shoulderY, shoulderWidth, small);
    [self button:@"Z"].frame = CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth - small - 12.0 * scale, shoulderY, small, small);
    CGFloat startWidth = (pad ? 116.0 : 92.0 * baseScale) * _controlScale;
    [self button:@"START"].frame = CGRectMake(CGRectGetMidX(safe) - startWidth * 0.5, CGRectGetMinY(safe) + margin, startWidth, small);

    CGFloat d = (pad ? 48.0 : 36.0 * baseScale) * _controlScale;
    CGFloat dx = CGRectGetMaxX(_moveStick.frame) + (pad ? 34.0 : 18.0 * scale);
    CGFloat dy = CGRectGetMidY(_moveStick.frame) - d * 0.5;
    [self button:@"▲"].frame = CGRectMake(dx + d, dy - d, d, d);
    [self button:@"▼"].frame = CGRectMake(dx + d, dy + d, d, d);
    [self button:@"◀"].frame = CGRectMake(dx, dy, d, d);
    [self button:@"▶"].frame = CGRectMake(dx + 2.0 * d, dy, d, d);
    [self applySavedControlSizes];
    for (BPGameButton *button in _buttons) {
        button.layer.cornerRadius = std::min(button.bounds.size.width, button.bounds.size.height) * 0.5;
    }
    [self applySavedControlCentersInSafeRect:safe];

    CGFloat settingsSide = 48.0;
    _settingsButton.frame = CGRectMake(CGRectGetMaxX(safe) - settingsSide,
                                       CGRectGetMinY(safe) + 8.0,
                                       settingsSide, settingsSide);
    CGFloat panelWidth = std::min<CGFloat>(360.0, std::max<CGFloat>(300.0, safe.size.width - 24.0));
    CGFloat panelHeight = std::min<CGFloat>(470.0, safe.size.height - 70.0);
    _fpsLabel.frame = CGRectMake(CGRectGetMinX(safe) + 8, CGRectGetMinY(safe) + 8, 96, 28);
    _settingsPanel.frame = CGRectMake(CGRectGetMaxX(safe) - panelWidth,
                                      CGRectGetMinY(safe) + 54.0,
                                      panelWidth, panelHeight);
    CGRect panelFrame = _settingsPanel.frame;
    CGFloat originX = panelFrame.origin.x, originY = panelFrame.origin.y;
    panelFrame.origin.x = std::clamp<CGFloat>(originX + _settingsPanelOffset.x, CGRectGetMinX(safe), CGRectGetMaxX(safe) - panelWidth);
    panelFrame.origin.y = std::clamp<CGFloat>(originY + _settingsPanelOffset.y, CGRectGetMinY(safe), CGRectGetMaxY(safe) - panelHeight);
    _settingsPanelOffset = CGPointMake(panelFrame.origin.x - originX, panelFrame.origin.y - originY);
    _settingsPanel.frame = panelFrame;
    [self updateControlAppearance];
    [self bringSubviewToFront:_settingsPanel];
    [self bringSubviewToFront:_settingsButton];
}

@end

static UIWindow *BellpadGameWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) if (window.isKeyWindow) return window;
        if (windowScene.windows.firstObject) return windowScene.windows.firstObject;
    }
    return nil;
}

static BPDiscImportViewController *sDiscImportController;
static BPNativeTextField *sNativeTextField;
static UIButton *sNativeTextDoneButton;
static id sNativeKeyboardDisconnectObserver;

static void BellpadApplyNativeTextState(BOOL active) {
    UIWindow *window = BellpadGameWindow();
    UIView *rootView = window.rootViewController.view;
    if (!rootView) return;

    if (!sNativeTextField) {
        BPNativeTextField *field = [BPNativeTextField new];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
        field.textColor = UIColor.whiteColor;
        field.tintColor = UIColor.whiteColor;
        field.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        field.textAlignment = NSTextAlignmentCenter;
        field.placeholder = @"Type with the native keyboard";
        field.attributedPlaceholder = [[NSAttributedString alloc]
            initWithString:field.placeholder
                attributes:@{NSForegroundColorAttributeName:
                                 [UIColor colorWithWhite:1.0 alpha:0.62]}];
        field.layer.cornerRadius = 12.0;
        field.layer.borderWidth = 1.0;
        field.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
        field.keyboardType = UIKeyboardTypeDefault;
        field.keyboardAppearance = UIKeyboardAppearanceDark;
        field.returnKeyType = UIReturnKeyDone;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
        field.smartQuotesType = UITextSmartQuotesTypeNo;
        field.smartDashesType = UITextSmartDashesTypeNo;
        field.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
        field.accessibilityLabel = @"Animal Crossing text input";
        [field addTarget:field action:@selector(submitText)
        forControlEvents:UIControlEventEditingDidEndOnExit];
        [rootView addSubview:field];

        UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
        done.translatesAutoresizingMaskIntoConstraints = NO;
        [done setTitle:@"Done" forState:UIControlStateNormal];
        [done setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        done.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
        done.backgroundColor = [UIColor colorWithRed:0.20 green:0.55 blue:0.37 alpha:0.96];
        done.layer.cornerRadius = 12.0;
        done.accessibilityLabel = @"Finish Animal Crossing text input";
        [done addTarget:field action:@selector(submitText) forControlEvents:UIControlEventTouchUpInside];
        [rootView addSubview:done];

        UILayoutGuide *safe = rootView.safeAreaLayoutGuide;
        NSLayoutConstraint *preferredWidth =
            [field.widthAnchor constraintEqualToConstant:340.0];
        preferredWidth.priority = UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [field.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12.0],
            [field.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor constant:-40.0],
            [field.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24.0],
            [field.widthAnchor constraintLessThanOrEqualToConstant:340.0],
            preferredWidth,
            [field.heightAnchor constraintEqualToConstant:44.0],
            [done.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:8.0],
            [done.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-24.0],
            [done.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
            [done.widthAnchor constraintEqualToConstant:72.0],
            [done.heightAnchor constraintEqualToConstant:44.0],
        ]];
        sNativeTextField = field;
        sNativeTextDoneButton = done;
        sNativeKeyboardDisconnectObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:GCKeyboardDidDisconnectNotification object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *notification) {
            (void)notification;
            if (!sNativeTextRequested.load(std::memory_order_acquire)) return;
            [sNativeTextField becomeFirstResponder];
            [sNativeTextField reloadInputViews];
        }];
    }

    BPGameOverlay *overlay = (BPGameOverlay *)[rootView viewWithTag:0x42454C4C];
    [overlay setNativeTextActive:active];
    sNativeTextField.hidden = !active;
    sNativeTextDoneButton.hidden = !active;
    if (active) {
        [sNativeTextField resetProxyText];
        [rootView bringSubviewToFront:sNativeTextField];
        [rootView bringSubviewToFront:sNativeTextDoneButton];
        [sNativeTextField becomeFirstResponder];
        [sNativeTextField reloadInputViews];
    } else {
        [sNativeTextField resignFirstResponder];
        [sNativeTextField resetProxyText];
    }
}

static BOOL BellpadCopyPath(NSString *path, char *outputPath, size_t outputCapacity) {
    const char *fileSystemPath = path.fileSystemRepresentation;
    if (!fileSystemPath) return NO;
    const size_t length = std::strlen(fileSystemPath);
    if (length >= outputCapacity) return NO;
    std::memcpy(outputPath, fileSystemPath, length + 1);
    return YES;
}

static void BellpadSDLLog(void *userdata, int category, SDL_LogPriority priority, const char *message) {
    (void)userdata;
    if (priority >= SDL_LOG_PRIORITY_WARN)
        bellpad_log_runtime((int)priority - 2, "SDL", message, message ? strlen(message) : 0);
    (void)category;
}

void bellpad_install_game_overlay(void) {
    bellpad_diagnostics_start();
    SDL_SetLogOutputFunction(BellpadSDLLog, nullptr);
    void (^install)(void) = ^{
        UIWindow *window = BellpadGameWindow();
        if (!window) return;
        UIView *host = window.rootViewController.view;
        if (!host || [host viewWithTag:0x42454C4C]) return;
        BPGameOverlay *overlay = [[BPGameOverlay alloc] initWithFrame:host.bounds];
        overlay.tag = 0x42454C4C;
        [host addSubview:overlay];
        NSDictionary *notice = [NSUserDefaults.standardUserDefaults dictionaryForKey:BPSaveRecoveryNoticeKey];
        if (notice) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:BPSaveRecoveryNoticeKey];
            dispatch_async(dispatch_get_main_queue(), ^{
                [overlay presentMessageWithTitle:notice[@"title"] ?: @"Save Notice"
                                          message:notice[@"message"] ?: @""];
            });
        }
    };
    if (NSThread.isMainThread) install();
    else dispatch_sync(dispatch_get_main_queue(), install);
}

int bellpad_prepare_game_data_path(const char* applicationSupportPath,
                                   char* outputPath,
                                   size_t outputCapacity) {
    if (!applicationSupportPath || !outputPath || outputCapacity == 0) return 0;
    outputPath[0] = '\0';

    NSString *supportPath = [NSString stringWithUTF8String:applicationSupportPath];
    if (!supportPath) return 0;
    NSURL *supportURL = [NSURL fileURLWithPath:supportPath isDirectory:YES];
    sApplicationSupportURL = supportURL;
    BellpadApplyPendingSaveImport();
    if (!BellpadRecoverCanonicalSaveIfNeeded()) { BellpadLog(@"save recovery blocked startup"); return 0; }
    BellpadLog(@"save preparation complete");

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL forcePicker = [defaults boolForKey:BPChangeGameDataOnNextLaunchKey];
    BOOL removeRetainedData = [defaults boolForKey:BPRemoveGameDataOnNextLaunchKey];

    NSURL *retainedURL = [[supportURL URLByAppendingPathComponent:@"Game Data" isDirectory:YES]
        URLByAppendingPathComponent:@"Animal Crossing.iso"];
    if (removeRetainedData && [NSFileManager.defaultManager fileExistsAtPath:retainedURL.path]) {
        NSError *error = nil;
        [NSFileManager.defaultManager removeItemAtURL:retainedURL error:&error];
        if (error) {
            BellpadLog(@"[Storage] Could not remove retained game data: %@", error.localizedDescription);
            return 0;
        }
        BellpadLog(@"[Storage] Removed retained game data at the user's request");
    }
    [defaults removeObjectForKey:BPChangeGameDataOnNextLaunchKey];
    [defaults removeObjectForKey:BPRemoveGameDataOnNextLaunchKey];
    if (!forcePicker && !removeRetainedData &&
        BellpadValidateDiscImage(retainedURL.fileSystemRepresentation).valid()) {
        BellpadLog(@"retained disc validated; startup continuing");
        return BellpadCopyPath(retainedURL.path, outputPath, outputCapacity) ? 1 : 0;
    }
    BellpadLog(@"game data setup required forcePicker=%d removeRequested=%d", forcePicker, removeRetainedData);
    dispatch_semaphore_t completionSemaphore = dispatch_semaphore_create(0);
    __block NSString *selectedPath = nil;
    __block BOOL finished = NO;
    void (^presentImport)(void) = ^{
        UIWindow *window = BellpadGameWindow();
        UIViewController *presenter = window.rootViewController;
        if (!presenter) {
            finished = YES;
            dispatch_semaphore_signal(completionSemaphore);
            return;
        }

        BPDiscImportViewController *controller = [BPDiscImportViewController new];
        controller.applicationSupportURL = supportURL;
        controller.modalPresentationStyle = UIModalPresentationFullScreen;
        __weak BPDiscImportViewController *weakController = controller;
        controller.completion = ^(NSURL *url) {
            selectedPath = url.path;
            BPDiscImportViewController *strongController = weakController;
            [strongController dismissViewControllerAnimated:YES completion:^{
                strongController.completion = nil;
                sDiscImportController = nil;
                finished = YES;
                dispatch_semaphore_signal(completionSemaphore);
            }];
        };
        sDiscImportController = controller;
        [presenter presentViewController:controller animated:NO completion:nil];
    };
    if (NSThread.isMainThread) {
        presentImport();
        while (!finished) {
            @autoreleasepool {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
                CFRunLoopRunInMode((CFStringRef)UITrackingRunLoopMode, 0.01, true);
            }
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), presentImport);
        dispatch_semaphore_wait(completionSemaphore, DISPATCH_TIME_FOREVER);
    }
    return selectedPath && BellpadCopyPath(selectedPath, outputPath, outputCapacity) ? 1 : 0;
}

void bellpad_set_native_text_active(int active) {
    const bool requested = active != 0;
    const bool previous = sNativeTextRequested.exchange(requested);
    if (previous == requested) return;

    {
        std::lock_guard<std::mutex> lock(sNativeTextMutex);
        sNativeTextEvents.clear();
    }
    void (^apply)(void) = ^{ BellpadApplyNativeTextState(requested); };
    if (NSThread.isMainThread) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
}

int bellpad_poll_native_text_event(char* utf8,
                                   size_t utf8Capacity,
                                   int* command) {
    if (!utf8 || utf8Capacity == 0 || !command) return 0;
    utf8[0] = '\0';
    *command = BELLPAD_NATIVE_TEXT_NONE;

    std::lock_guard<std::mutex> lock(sNativeTextMutex);
    if (sNativeTextEvents.empty()) return 0;
    BPNativeTextEvent event = std::move(sNativeTextEvents.front());
    sNativeTextEvents.pop_front();
    *command = event.command;
    if (!event.text.empty()) {
        const size_t length = std::min(event.text.size(), utf8Capacity - 1);
        std::memcpy(utf8, event.text.data(), length);
        utf8[length] = '\0';
    }
    return 1;
}

float bellpad_get_framebuffer_scale(void) {
    const int mode = sFrameBufferScaleMode.load(std::memory_order_relaxed);
    return mode >= 1 && mode <= 4 ? static_cast<float>(mode) : 0.0f;
}

int bellpad_consume_did_become_active(void) {
    return sDidBecomeActive.exchange(false, std::memory_order_acq_rel) ? 1 : 0;
}

int bellpad_consume_will_resign_active(void) {
    return sWillResignActive.exchange(false, std::memory_order_acq_rel) ? 1 : 0;
}

int bellpad_consume_host_clock_changed(void) {
    return sHostClockChanged.exchange(false, std::memory_order_acq_rel) ? 1 : 0;
}

int bellpad_consume_audio_interruption_began(void) {
    return sAudioInterruptionBegan.exchange(false, std::memory_order_acq_rel) ? 1 : 0;
}

int bellpad_consume_audio_interruption_ended(void) {
    return sAudioInterruptionEnded.exchange(false, std::memory_order_acq_rel) ? 1 : 0;
}

int bellpad_consume_audio_route_changed(void) {
    return sAudioRouteChanged.exchange(false, std::memory_order_acq_rel) ? 1 : 0;
}

int bellpad_audio_session_ready(void) {
    return sAudioSessionReady.load(std::memory_order_acquire) ? 1 : 0;
}
