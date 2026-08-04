#import "BellpadGameOverlay.h"

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
static NSURL *sApplicationSupportURL;

static NSString *const BPChangeGameDataOnNextLaunchKey = @"BellpadChangeGameDataOnNextLaunch";
static NSString *const BPRemoveGameDataOnNextLaunchKey = @"BellpadRemoveGameDataOnNextLaunch";

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
        NSLog(@"[Save] Discarding invalid pending GCI: %@", validationError);
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
        NSLog(@"[Save] Pending GCI import failed and was retained: %@", error.localizedDescription);
        return;
    }
    NSError *syncError = nil;
    if (!BellpadSynchronizeFileAndDirectory(destination, &syncError)) {
        NSLog(@"[Save] Imported GCI is visible but metadata synchronization failed: %@",
              syncError.localizedDescription);
    }
    [files removeItemAtURL:pending error:nil];
    NSLog(@"[Save] Installed validated pending GCI before game startup");
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
@end

@implementation BPNativeTextField

- (BOOL)hasText {
    // Keep delete enabled while the game, rather than this proxy field, owns
    // the canonical editor contents.
    return YES;
}

- (void)setText:(NSString *)text {
    // Accessibility and dictation may replace the proxy value instead of
    // calling insertText:. Route those replacements through the same queue.
    if (text.length > 0) {
        BellpadQueueNativeText(text);
    }
    [super setText:@""];
}

- (void)setAccessibilityValue:(NSString *)value {
    // UI automation and Switch Control use the accessibility value setter.
    // Treat it like dictation/replacement text while keeping the proxy empty.
    BellpadQueueNativeText(value);
}

- (void)insertText:(NSString *)text {
    if ([text isEqualToString:@"\n"] || [text isEqualToString:@"\r"]) {
        BellpadQueueNativeTextCommand(BELLPAD_NATIVE_TEXT_ENTER);
    } else {
        BellpadQueueNativeText(text);
    }
}

- (void)deleteBackward {
    BellpadQueueNativeTextCommand(BELLPAD_NATIVE_TEXT_BACKSPACE);
}

- (void)paste:(id)sender {
    (void)sender;
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (text.length > 0) BellpadQueueNativeText(text);
    [super setText:@""];
}

- (void)submitText {
    BellpadQueueNativeTextCommand(BELLPAD_NATIVE_TEXT_ENTER);
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
        [_activityIndicator.topAnchor constraintEqualToAnchor:_chooseButton.bottomAnchor constant:16.0],
    ]];
}

- (void)chooseGameData {
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
    [self setBusy:NO status:message];
    _statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.58 blue:0.58 alpha:1.0];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *sourceURL = urls.firstObject;
    if (!sourceURL) return;

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
@end

@implementation BPGameOverlay {
    BellpadPadState _state;
    BPStickView *_moveStick;
    BPStickView *_cameraStick;
    NSMutableArray<BPGameButton *> *_buttons;
    NSMutableArray<UIPanGestureRecognizer *> *_editGestures;
    UIButton *_settingsButton;
    UIView *_settingsPanel;
    UIScrollView *_settingsScrollView;
    UISlider *_opacitySlider;
    UISlider *_scaleSlider;
    UISegmentedControl *_renderScaleControl;
    UISwitch *_hideControlsSwitch;
    UISwitch *_editLayoutSwitch;
    CGFloat _controlOpacity;
    CGFloat _controlScale;
    BOOL _manualControlsHidden;
    BOOL _controllerConnected;
    BOOL _editingLayout;
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

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        __weak BPGameOverlay *weakSelf = self;
        _connectObserver = [center addObserverForName:GCControllerDidConnectNotification object:nil
                                               queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weakSelf configureController:note.object];
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
        for (GCController *controller in GCController.controllers) [self configureController:controller];
        [self refreshControllerVisibility];
    }
    return self;
}

- (void)dealloc {
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
    NSNumber *renderScale = [defaults objectForKey:[self graphicsSettingsKey:@"renderScale"]];
    _controlOpacity = std::clamp<CGFloat>(opacity ? opacity.doubleValue : 0.76, 0.25, 1.0);
    _controlScale = std::clamp<CGFloat>(scale ? scale.doubleValue : 1.0, 0.70, 1.35);
    _manualControlsHidden = hidden ? hidden.boolValue : NO;
    NSInteger renderScaleMode = std::clamp<NSInteger>(renderScale ? renderScale.integerValue : 0, 0, 4);
    _opacitySlider.value = _controlOpacity;
    _scaleSlider.value = _controlScale;
    _renderScaleControl.selectedSegmentIndex = renderScaleMode;
    sFrameBufferScaleMode.store(static_cast<int>(renderScaleMode), std::memory_order_relaxed);
    _hideControlsSwitch.on = _manualControlsHidden;
    [self updateControlAppearance];
}

- (void)addEditGestureToControl:(UIView *)control {
    UIPanGestureRecognizer *gesture = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(moveControl:)];
    gesture.enabled = NO;
    gesture.cancelsTouchesInView = YES;
    [control addGestureRecognizer:gesture];
    [_editGestures addObject:gesture];
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
        [row.heightAnchor constraintEqualToConstant:38.0],
    ]];
    if ([control isKindOfClass:UISlider.class]) {
        [constraints addObject:[control.widthAnchor constraintEqualToConstant:148.0]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return row;
}

- (void)buildSettingsPanel {
    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_settingsButton setTitle:@"⚙︎" forState:UIControlStateNormal];
    [_settingsButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _settingsButton.titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    _settingsButton.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.72];
    _settingsButton.layer.cornerRadius = 20.0;
    _settingsButton.layer.borderWidth = 1.0;
    _settingsButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    _settingsButton.accessibilityLabel = @"Touch control settings";
    [_settingsButton addTarget:self action:@selector(toggleSettings) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_settingsButton];

    _settingsPanel = [UIView new];
    _settingsPanel.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.94];
    _settingsPanel.layer.cornerRadius = 16.0;
    _settingsPanel.layer.borderWidth = 1.0;
    _settingsPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    _settingsPanel.hidden = YES;
    [self addSubview:_settingsPanel];

    UILabel *title = [UILabel new];
    title.text = @"Bellpad Settings";
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

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"Reset This Device Layout" forState:UIControlStateNormal];
    [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    reset.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.88];
    reset.layer.cornerRadius = 10.0;
    reset.accessibilityLabel = @"Reset touch control layout";
    [reset addTarget:self action:@selector(resetControlSettings) forControlEvents:UIControlEventTouchUpInside];

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

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title,
        [self settingsRowWithTitle:@"Render" control:_renderScaleControl],
        [self settingsRowWithTitle:@"Opacity" control:_opacitySlider],
        [self settingsRowWithTitle:@"Size" control:_scaleSlider],
        [self settingsRowWithTitle:@"Hide controls" control:_hideControlsSwitch],
        [self settingsRowWithTitle:@"Move controls" control:_editLayoutSwitch],
        reset,
        data,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 7.0;

    _settingsScrollView = [UIScrollView new];
    _settingsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsScrollView.alwaysBounceVertical = NO;
    _settingsScrollView.showsVerticalScrollIndicator = YES;
    [_settingsPanel addSubview:_settingsScrollView];
    [_settingsScrollView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [_settingsScrollView.leadingAnchor constraintEqualToAnchor:_settingsPanel.leadingAnchor],
        [_settingsScrollView.trailingAnchor constraintEqualToAnchor:_settingsPanel.trailingAnchor],
        [_settingsScrollView.topAnchor constraintEqualToAnchor:_settingsPanel.topAnchor],
        [_settingsScrollView.bottomAnchor constraintEqualToAnchor:_settingsPanel.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.topAnchor constant:14.0],
        [stack.bottomAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.bottomAnchor constant:-14.0],
        [stack.widthAnchor constraintEqualToAnchor:_settingsScrollView.frameLayoutGuide.widthAnchor constant:-32.0],
        [reset.heightAnchor constraintEqualToConstant:40.0],
        [data.heightAnchor constraintEqualToConstant:40.0],
    ]];
}

- (void)toggleSettings {
    _settingsPanel.hidden = !_settingsPanel.hidden;
    if (!_settingsPanel.hidden) {
        [self bringSubviewToFront:_settingsPanel];
        [self bringSubviewToFront:_settingsButton];
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
    _settingsPanel.hidden = YES;
    [self presentMessageWithTitle:@"Reimport on Next Launch"
                          message:@"Close and reopen Bellpad. Before the game starts, Files will ask for a supported ISO or GCM. Your current retained image remains available until a replacement passes validation."];
}

- (void)confirmGameDataRemoval {
    _settingsPanel.hidden = YES;
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
    _settingsPanel.hidden = YES;
    [self presentDocumentPickerWhileHoldingGameLoop:picker];
}

- (void)beginSaveExport {
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
    _settingsPanel.hidden = YES;
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
    [self clearTouchInput];
    for (UIPanGestureRecognizer *gesture in _editGestures) gesture.enabled = _editingLayout;
    for (UIView *control in [self gameplayControls]) {
        control.layer.borderColor = (_editingLayout
            ? [UIColor colorWithRed:1.0 green:0.78 blue:0.20 alpha:0.95]
            : [UIColor colorWithWhite:1.0 alpha:0.42]).CGColor;
    }
    [self updateControlAppearance];
}

- (void)resetControlSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:[self settingsKey:@"centers"]];
    [defaults removeObjectForKey:[self settingsKey:@"opacity"]];
    [defaults removeObjectForKey:[self settingsKey:@"scale"]];
    [defaults removeObjectForKey:[self settingsKey:@"hidden"]];
    _controlOpacity = 0.76;
    _controlScale = 1.0;
    _manualControlsHidden = NO;
    _opacitySlider.value = _controlOpacity;
    _scaleSlider.value = _controlScale;
    _hideControlsSwitch.on = NO;
    _editLayoutSwitch.on = NO;
    [self editLayoutChanged:_editLayoutSwitch];
    [self setNeedsLayout];
}

- (void)updateControlAppearance {
    BOOL hidden = _manualControlsHidden || _controllerConnected;
    if (hidden) [self clearTouchInput];
    for (UIView *control in [self gameplayControls]) {
        control.hidden = hidden;
        control.alpha = _controlOpacity;
        control.userInteractionEnabled = !hidden;
    }
}

- (void)moveControl:(UIPanGestureRecognizer *)gesture {
    if (!_editingLayout || !gesture.view) return;
    UIView *control = gesture.view;
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
    if (sWasInactive.exchange(false, std::memory_order_acq_rel)) {
        sDidBecomeActive.store(true, std::memory_order_release);
    }
}

- (void)willResignActive:(NSNotification *)notification {
    (void)notification;
    [self clearInput];
    sWasInactive.store(true, std::memory_order_release);
    sWillResignActive.store(true, std::memory_order_release);
}

- (void)hostClockChanged:(NSNotification *)notification {
    (void)notification;
    sHostClockChanged.store(true, std::memory_order_release);
}

- (void)configureController:(GCController *)controller {
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (!gamepad) return;
    gamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
        (void)element;
        BellpadPadState state;
        if (pad.buttonA.isPressed) state.buttons |= BellpadButtonA;
        if (pad.buttonB.isPressed) state.buttons |= BellpadButtonB;
        if (pad.buttonX.isPressed) state.buttons |= BellpadButtonX;
        if (pad.buttonY.isPressed) state.buttons |= BellpadButtonY;
        if (pad.leftShoulder.isPressed) state.buttons |= BellpadButtonL;
        if (pad.rightShoulder.isPressed) state.buttons |= BellpadButtonZ;
        if (pad.buttonMenu.isPressed) state.buttons |= BellpadButtonStart;
        if (pad.dpad.up.isPressed) state.buttons |= BellpadButtonDPadUp;
        if (pad.dpad.down.isPressed) state.buttons |= BellpadButtonDPadDown;
        if (pad.dpad.left.isPressed) state.buttons |= BellpadButtonDPadLeft;
        if (pad.dpad.right.isPressed) state.buttons |= BellpadButtonDPadRight;
        state.stickX = static_cast<std::int8_t>(std::lround(pad.leftThumbstick.xAxis.value * 127.0f));
        state.stickY = static_cast<std::int8_t>(std::lround(pad.leftThumbstick.yAxis.value * 127.0f));
        state.cStickX = static_cast<std::int8_t>(std::lround(pad.rightThumbstick.xAxis.value * 127.0f));
        state.cStickY = static_cast<std::int8_t>(std::lround(pad.rightThumbstick.yAxis.value * 127.0f));
        state.triggerL = static_cast<std::uint8_t>(std::lround(pad.leftTrigger.value * 255.0f));
        state.triggerR = static_cast<std::uint8_t>(std::lround(pad.rightTrigger.value * 255.0f));
        if (state.triggerL > 30) state.buttons |= BellpadButtonL;
        if (state.triggerR > 30) state.buttons |= BellpadButtonR;
        BellpadSetInputState(BellpadInputSource::Controller, state);
    };
}

- (void)refreshControllerVisibility {
    BOOL connected = NO;
#if !TARGET_OS_SIMULATOR
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad) { connected = YES; break; }
    }
#endif
    if (connected) [self clearTouchInput];
    _controllerConnected = connected;
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
    for (BPGameButton *button in _buttons) {
        button.layer.cornerRadius = std::min(button.bounds.size.width, button.bounds.size.height) * 0.5;
    }
    [self applySavedControlCentersInSafeRect:safe];

    CGFloat settingsSide = 40.0;
    _settingsButton.frame = CGRectMake(CGRectGetMaxX(safe) - settingsSide,
                                       CGRectGetMinY(safe) + 8.0,
                                       settingsSide, settingsSide);
    CGFloat panelWidth = std::min<CGFloat>(360.0, std::max<CGFloat>(300.0, safe.size.width - 24.0));
    CGFloat panelHeight = std::min<CGFloat>(390.0, safe.size.height - 62.0);
    _settingsPanel.frame = CGRectMake(CGRectGetMaxX(safe) - panelWidth,
                                      CGRectGetMinY(safe) + 54.0,
                                      panelWidth, panelHeight);
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
    }

    sNativeTextField.hidden = !active;
    sNativeTextDoneButton.hidden = !active;
    if (active) {
        [rootView bringSubviewToFront:sNativeTextField];
        [rootView bringSubviewToFront:sNativeTextDoneButton];
        [sNativeTextField becomeFirstResponder];
    } else {
        [sNativeTextField resignFirstResponder];
        sNativeTextField.text = @"";
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

void bellpad_install_game_overlay(void) {
    void (^install)(void) = ^{
        UIWindow *window = BellpadGameWindow();
        if (!window) return;
        UIView *host = window.rootViewController.view;
        if (!host || [host viewWithTag:0x42454C4C]) return;
        BPGameOverlay *overlay = [[BPGameOverlay alloc] initWithFrame:host.bounds];
        overlay.tag = 0x42454C4C;
        [host addSubview:overlay];
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

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL forcePicker = [defaults boolForKey:BPChangeGameDataOnNextLaunchKey];
    BOOL removeRetainedData = [defaults boolForKey:BPRemoveGameDataOnNextLaunchKey];

    NSURL *retainedURL = [[supportURL URLByAppendingPathComponent:@"Game Data" isDirectory:YES]
        URLByAppendingPathComponent:@"Animal Crossing.iso"];
    if (removeRetainedData && [NSFileManager.defaultManager fileExistsAtPath:retainedURL.path]) {
        NSError *error = nil;
        [NSFileManager.defaultManager removeItemAtURL:retainedURL error:&error];
        if (error) {
            NSLog(@"[Storage] Could not remove retained game data: %@", error.localizedDescription);
            return 0;
        }
        NSLog(@"[Storage] Removed retained game data at the user's request");
    }
    [defaults removeObjectForKey:BPChangeGameDataOnNextLaunchKey];
    [defaults removeObjectForKey:BPRemoveGameDataOnNextLaunchKey];
    if (!forcePicker && !removeRetainedData &&
        BellpadValidateDiscImage(retainedURL.fileSystemRepresentation).valid()) {
        return BellpadCopyPath(retainedURL.path, outputPath, outputCapacity) ? 1 : 0;
    }
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
