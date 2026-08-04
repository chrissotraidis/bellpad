#import "BellpadGameOverlay.h"

#import <GameController/GameController.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "BellpadDiscValidator.h"
#include "BellpadInput.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
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

@interface BPGameOverlay : UIView <BPStickDelegate>
@end

@implementation BPGameOverlay {
    BellpadPadState _state;
    BPStickView *_moveStick;
    BPStickView *_cameraStick;
    NSMutableArray<BPGameButton *> *_buttons;
    id _connectObserver;
    id _disconnectObserver;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _buttons = [NSMutableArray array];
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
        [center addObserver:self selector:@selector(clearInput)
                       name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(clearInput)
                       name:UIApplicationWillTerminateNotification object:nil];
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
}

- (BPGameButton *)button:(NSString *)name {
    for (BPGameButton *button in _buttons) if ([button.currentTitle isEqualToString:name]) return button;
    return nil;
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
    _state.buttons |= button.inputMask;
    if (button.inputMask == BellpadButtonL) _state.triggerL = 255;
    if (button.inputMask == BellpadButtonR) _state.triggerR = 255;
    button.transform = CGAffineTransformMakeScale(0.92, 0.92);
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)buttonUp:(BPGameButton *)button {
    _state.buttons &= ~button.inputMask;
    if (button.inputMask == BellpadButtonL) _state.triggerL = 0;
    if (button.inputMask == BellpadButtonR) _state.triggerR = 0;
    button.transform = CGAffineTransformIdentity;
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)stick:(NSInteger)tag changedX:(std::int8_t)x y:(std::int8_t)y {
    if (tag == 1) { _state.stickX = x; _state.stickY = y; }
    else { _state.cStickX = x; _state.cStickY = y; }
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)clearInput {
    _state = {};
    BellpadClearInputState(BellpadInputSource::Touch);
    BellpadClearInputState(BellpadInputSource::Controller);
    for (BPGameButton *button in _buttons) button.transform = CGAffineTransformIdentity;
    [_moveStick reset];
    [_cameraStick reset];
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
    if (connected) [self clearInput];
    self.hidden = connected;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    BOOL pad = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad && safe.size.width >= 1000.0;
    CGFloat scale = pad ? 1.0 : std::min<CGFloat>(1.0, std::min(safe.size.width / 800.0, safe.size.height / 380.0));
    CGFloat margin = pad ? 34.0 : std::max<CGFloat>(8.0, 18.0 * scale);
    CGFloat stick = pad ? 172.0 : 126.0 * scale;
    CGFloat small = pad ? 62.0 : 46.0 * scale;
    CGFloat medium = pad ? 76.0 : 58.0 * scale;
    CGFloat large = pad ? 104.0 : 78.0 * scale;
    _moveStick.frame = CGRectMake(CGRectGetMinX(safe) + margin, CGRectGetMaxY(safe) - stick - margin, stick, stick);
    CGFloat camera = pad ? 112.0 : 86.0 * scale;
    _cameraStick.frame = CGRectMake(CGRectGetMaxX(safe) - margin - camera, CGRectGetMaxY(safe) - margin - camera, camera, camera);

    BPGameButton *a = [self button:@"A"], *b = [self button:@"B"], *x = [self button:@"X"], *y = [self button:@"Y"];
    a.frame = CGRectMake(CGRectGetMaxX(safe) - margin - large, CGRectGetMaxY(safe) - margin - camera - large - 18.0 * scale, large, large);
    b.frame = CGRectMake(CGRectGetMinX(a.frame) - medium - 12.0 * scale, CGRectGetMidY(a.frame) + 8.0, medium, medium);
    x.frame = CGRectMake(CGRectGetMidX(a.frame) - small * 0.5, CGRectGetMinY(a.frame) - small - 10.0 * scale, small, small);
    y.frame = CGRectMake(CGRectGetMinX(a.frame) - small - 8.0 * scale, CGRectGetMinY(a.frame) - small + 8.0, small, small);

    CGFloat shoulderWidth = pad ? 132.0 : 94.0 * scale;
    CGFloat shoulderY = CGRectGetMinY(safe) + (pad ? 92.0 : 68.0 * scale);
    [self button:@"L"].frame = CGRectMake(CGRectGetMinX(safe) + margin, shoulderY, shoulderWidth, small);
    [self button:@"R"].frame = CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth, shoulderY, shoulderWidth, small);
    [self button:@"Z"].frame = CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth - small - 12.0 * scale, shoulderY, small, small);
    CGFloat startWidth = pad ? 116.0 : 92.0 * scale;
    [self button:@"START"].frame = CGRectMake(CGRectGetMidX(safe) - startWidth * 0.5, CGRectGetMinY(safe) + margin, startWidth, small);

    CGFloat d = pad ? 48.0 : 36.0 * scale;
    CGFloat dx = CGRectGetMaxX(_moveStick.frame) + (pad ? 34.0 : 18.0 * scale);
    CGFloat dy = CGRectGetMidY(_moveStick.frame) - d * 0.5;
    [self button:@"▲"].frame = CGRectMake(dx + d, dy - d, d, d);
    [self button:@"▼"].frame = CGRectMake(dx + d, dy + d, d, d);
    [self button:@"◀"].frame = CGRectMake(dx, dy, d, d);
    [self button:@"▶"].frame = CGRectMake(dx + 2.0 * d, dy, d, d);
    for (BPGameButton *button in _buttons) {
        button.layer.cornerRadius = std::min(button.bounds.size.width, button.bounds.size.height) * 0.5;
    }
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
    NSURL *retainedURL = [[supportURL URLByAppendingPathComponent:@"Game Data" isDirectory:YES]
        URLByAppendingPathComponent:@"Animal Crossing.iso"];
    if (BellpadValidateDiscImage(retainedURL.fileSystemRepresentation).valid()) {
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
