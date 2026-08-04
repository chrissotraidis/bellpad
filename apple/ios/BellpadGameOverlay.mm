#import "BellpadGameOverlay.h"

#import <GameController/GameController.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>

#include "BellpadInput.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

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
