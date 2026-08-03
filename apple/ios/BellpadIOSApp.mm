#import <GameController/GameController.h>
#import <MetalKit/MetalKit.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>

#include "BellpadInput.h"

#include <algorithm>
#include <cmath>

@interface BellpadMetalRenderer : NSObject <MTKViewDelegate>
@end

@implementation BellpadMetalRenderer {
    id<MTLCommandQueue> _commandQueue;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _commandQueue = [device newCommandQueue];
    }
    return self;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView *)view {
    MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (pass == nil || drawable == nil) return;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.035, 0.055, 0.095, 1.0);
    id<MTLCommandBuffer> buffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];
}

@end

@protocol BellpadStickDelegate <NSObject>
- (void)stickWithTag:(NSInteger)tag changedX:(std::int8_t)x y:(std::int8_t)y;
@end

@interface BellpadStickView : UIView
@property(nonatomic, weak) id<BellpadStickDelegate> stickDelegate;
@end

@implementation BellpadStickView {
    UIView *_thumb;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.34].CGColor;
        self.layer.borderWidth = 2.0;
        _thumb = [[UIView alloc] initWithFrame:CGRectZero];
        _thumb.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.32];
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat minimumSide = std::min(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = minimumSide * 0.5;
    CGFloat diameter = minimumSide * 0.42;
    if (CGRectEqualToRect(_thumb.frame, CGRectZero)) {
        _thumb.bounds = CGRectMake(0, 0, diameter, diameter);
        _thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    }
    _thumb.layer.cornerRadius = diameter * 0.5;
}

- (void)updateWithTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = std::max<CGFloat>(1.0, std::min(self.bounds.size.width, self.bounds.size.height) * 0.5);
    CGFloat dx = (point.x - center.x) / radius;
    CGFloat dy = (point.y - center.y) / radius;
    CGFloat length = hypot(dx, dy);
    if (length > 1.0) {
        dx /= length;
        dy /= length;
    }
    CGFloat thumbRadius = _thumb.bounds.size.width * 0.5;
    CGFloat travel = std::max<CGFloat>(0.0, radius - thumbRadius - 4.0);
    _thumb.center = CGPointMake(center.x + dx * travel, center.y + dy * travel);
    [self.stickDelegate stickWithTag:self.tag
                            changedX:static_cast<std::int8_t>(std::lround(dx * 127.0))
                                   y:static_cast<std::int8_t>(std::lround(-dy * 127.0))];
}

- (void)reset {
    _thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self.stickDelegate stickWithTag:self.tag changedX:0 y:0];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    [self updateWithTouch:touches.anyObject];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    [self updateWithTouch:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches;
    (void)event;
    [self reset];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

@end

@interface BellpadControlButton : UIButton
@property(nonatomic) std::uint16_t inputMask;
@end

@implementation BellpadControlButton
@end

@interface BellpadTouchOverlay : UIView <BellpadStickDelegate>
@property(nonatomic, readonly) BellpadPadState state;
- (void)clearState;
@end

@implementation BellpadTouchOverlay {
    BellpadPadState _state;
    BellpadStickView *_leftStick;
    BellpadStickView *_cStick;
    NSMutableArray<BellpadControlButton *> *_buttons;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;
        _buttons = [NSMutableArray array];
        _leftStick = [self makeStickWithTag:1 label:@"MOVE"];
        _cStick = [self makeStickWithTag:2 label:@"CAM"];

        [self addButton:@"A" mask:BellpadButtonA accent:[UIColor colorWithRed:0.28 green:0.78 blue:0.55 alpha:0.88]];
        [self addButton:@"B" mask:BellpadButtonB accent:[UIColor colorWithRed:0.90 green:0.35 blue:0.40 alpha:0.88]];
        [self addButton:@"X" mask:BellpadButtonX accent:[UIColor colorWithRed:0.40 green:0.62 blue:0.95 alpha:0.82]];
        [self addButton:@"Y" mask:BellpadButtonY accent:[UIColor colorWithRed:0.92 green:0.72 blue:0.30 alpha:0.86]];
        [self addButton:@"Z" mask:BellpadButtonZ accent:[UIColor colorWithWhite:0.65 alpha:0.82]];
        [self addButton:@"L" mask:BellpadButtonL accent:[UIColor colorWithWhite:0.45 alpha:0.76]];
        [self addButton:@"R" mask:BellpadButtonR accent:[UIColor colorWithWhite:0.45 alpha:0.76]];
        [self addButton:@"START" mask:BellpadButtonStart accent:[UIColor colorWithWhite:0.42 alpha:0.76]];
        [self addButton:@"▲" mask:BellpadButtonDPadUp accent:[UIColor colorWithWhite:0.38 alpha:0.72]];
        [self addButton:@"▼" mask:BellpadButtonDPadDown accent:[UIColor colorWithWhite:0.38 alpha:0.72]];
        [self addButton:@"◀" mask:BellpadButtonDPadLeft accent:[UIColor colorWithWhite:0.38 alpha:0.72]];
        [self addButton:@"▶" mask:BellpadButtonDPadRight accent:[UIColor colorWithWhite:0.38 alpha:0.72]];
    }
    return self;
}

- (BellpadStickView *)makeStickWithTag:(NSInteger)tag label:(NSString *)label {
    BellpadStickView *stick = [[BellpadStickView alloc] initWithFrame:CGRectZero];
    stick.tag = tag;
    stick.stickDelegate = self;
    stick.accessibilityLabel = label;
    [self addSubview:stick];
    return stick;
}

- (void)addButton:(NSString *)title mask:(std::uint16_t)mask accent:(UIColor *)accent {
    BellpadControlButton *button = [BellpadControlButton buttonWithType:UIButtonTypeCustom];
    button.inputMask = mask;
    button.accessibilityLabel = title;
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = accent;
    button.layer.borderWidth = 1.5;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.38].CGColor;
    [button addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside |
                                                                      UIControlEventTouchUpOutside |
                                                                      UIControlEventTouchCancel];
    [self addSubview:button];
    [_buttons addObject:button];
}

- (BellpadControlButton *)buttonNamed:(NSString *)name {
    for (BellpadControlButton *button in _buttons) {
        if ([button.currentTitle isEqualToString:name]) return button;
    }
    return nil;
}

- (void)buttonDown:(BellpadControlButton *)button {
    _state.buttons |= button.inputMask;
    if (button.inputMask == BellpadButtonL) _state.triggerL = 255;
    if (button.inputMask == BellpadButtonR) _state.triggerR = 255;
    button.transform = CGAffineTransformMakeScale(0.92, 0.92);
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)buttonUp:(BellpadControlButton *)button {
    _state.buttons &= ~button.inputMask;
    if (button.inputMask == BellpadButtonL) _state.triggerL = 0;
    if (button.inputMask == BellpadButtonR) _state.triggerR = 0;
    button.transform = CGAffineTransformIdentity;
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)stickWithTag:(NSInteger)tag changedX:(std::int8_t)x y:(std::int8_t)y {
    if (tag == 1) {
        _state.stickX = x;
        _state.stickY = y;
    } else {
        _state.cStickX = x;
        _state.cStickY = y;
    }
    BellpadSetInputState(BellpadInputSource::Touch, _state);
}

- (void)clearState {
    _state = {};
    BellpadClearInputState(BellpadInputSource::Touch);
    for (BellpadControlButton *button in _buttons) button.transform = CGAffineTransformIdentity;
    [_leftStick reset];
    [_cStick reset];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    BOOL pad = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
               safe.size.width >= 1100.0 && safe.size.height >= 700.0;
    CGFloat scale = pad ? 1.0 : std::min<CGFloat>(1.0, std::min(safe.size.width / 800.0, safe.size.height / 380.0));
    CGFloat margin = pad ? 34.0 : std::max<CGFloat>(8.0, 18.0 * scale);
    CGFloat stickSize = pad ? 172.0 : 126.0 * scale;
    CGFloat small = pad ? 62.0 : 46.0 * scale;
    CGFloat medium = pad ? 76.0 : 58.0 * scale;
    CGFloat large = pad ? 104.0 : 78.0 * scale;

    _leftStick.frame = CGRectMake(CGRectGetMinX(safe) + margin,
                                  CGRectGetMaxY(safe) - stickSize - margin,
                                  stickSize, stickSize);
    CGFloat cSize = pad ? 112.0 : 86.0 * scale;
    _cStick.frame = CGRectMake(CGRectGetMaxX(safe) - margin - cSize,
                               CGRectGetMaxY(safe) - margin - cSize,
                               cSize, cSize);

    BellpadControlButton *a = [self buttonNamed:@"A"];
    BellpadControlButton *b = [self buttonNamed:@"B"];
    BellpadControlButton *x = [self buttonNamed:@"X"];
    BellpadControlButton *y = [self buttonNamed:@"Y"];
    a.frame = CGRectMake(CGRectGetMaxX(safe) - margin - large,
                         CGRectGetMaxY(safe) - margin - cSize - large - (pad ? 34.0 : 18.0 * scale), large, large);
    b.frame = CGRectMake(CGRectGetMinX(a.frame) - medium - 12.0 * scale,
                         CGRectGetMidY(a.frame) + 8.0, medium, medium);
    x.frame = CGRectMake(CGRectGetMidX(a.frame) - small * 0.5,
                         CGRectGetMinY(a.frame) - small - 10.0 * scale, small, small);
    y.frame = CGRectMake(CGRectGetMinX(a.frame) - small - 8.0 * scale,
                         CGRectGetMinY(a.frame) - small + 8.0, small, small);

    BellpadControlButton *l = [self buttonNamed:@"L"];
    BellpadControlButton *r = [self buttonNamed:@"R"];
    BellpadControlButton *z = [self buttonNamed:@"Z"];
    BellpadControlButton *start = [self buttonNamed:@"START"];
    CGFloat shoulderWidth = pad ? 132.0 : 94.0 * scale;
    CGFloat shoulderY = CGRectGetMinY(safe) + (pad ? 96.0 : 76.0 * scale);
    l.frame = CGRectMake(CGRectGetMinX(safe) + margin, shoulderY, shoulderWidth, small);
    r.frame = CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth, shoulderY, shoulderWidth, small);
    z.frame = CGRectMake(CGRectGetMinX(r.frame) - small - 12.0 * scale, CGRectGetMinY(r.frame), small, small);
    CGFloat startWidth = pad ? 116.0 : 92.0 * scale;
    start.frame = CGRectMake(CGRectGetMidX(safe) - startWidth * 0.5, CGRectGetMinY(safe) + margin,
                             startWidth, small);

    CGFloat d = pad ? 48.0 : 36.0 * scale;
    CGFloat dx = CGRectGetMaxX(_leftStick.frame) + (pad ? 34.0 : 18.0 * scale);
    CGFloat dy = CGRectGetMidY(_leftStick.frame) - d * 0.5;
    [self buttonNamed:@"▲"].frame = CGRectMake(dx + d, dy - d, d, d);
    [self buttonNamed:@"▼"].frame = CGRectMake(dx + d, dy + d, d, d);
    [self buttonNamed:@"◀"].frame = CGRectMake(dx, dy, d, d);
    [self buttonNamed:@"▶"].frame = CGRectMake(dx + d * 2.0, dy, d, d);

    for (BellpadControlButton *button in _buttons) {
        button.titleLabel.font = [UIFont systemFontOfSize:(pad ? 19.0 : std::max<CGFloat>(10.0, 17.0 * scale))
                                                   weight:UIFontWeightBold];
        button.layer.cornerRadius = std::min(button.bounds.size.width, button.bounds.size.height) * 0.5;
    }
}

@end

static BellpadPadState BellpadStateFromGamepad(GCExtendedGamepad *gamepad) {
    BellpadPadState state;
    if (gamepad.buttonA.isPressed) state.buttons |= BellpadButtonA;
    if (gamepad.buttonB.isPressed) state.buttons |= BellpadButtonB;
    if (gamepad.buttonX.isPressed) state.buttons |= BellpadButtonX;
    if (gamepad.buttonY.isPressed) state.buttons |= BellpadButtonY;
    if (gamepad.leftShoulder.isPressed) state.buttons |= BellpadButtonL;
    if (gamepad.rightShoulder.isPressed) state.buttons |= BellpadButtonZ;
    if (gamepad.buttonMenu.isPressed) state.buttons |= BellpadButtonStart;
    if (gamepad.dpad.up.isPressed) state.buttons |= BellpadButtonDPadUp;
    if (gamepad.dpad.down.isPressed) state.buttons |= BellpadButtonDPadDown;
    if (gamepad.dpad.left.isPressed) state.buttons |= BellpadButtonDPadLeft;
    if (gamepad.dpad.right.isPressed) state.buttons |= BellpadButtonDPadRight;
    state.stickX = static_cast<std::int8_t>(std::lround(gamepad.leftThumbstick.xAxis.value * 127.0f));
    state.stickY = static_cast<std::int8_t>(std::lround(gamepad.leftThumbstick.yAxis.value * 127.0f));
    state.cStickX = static_cast<std::int8_t>(std::lround(gamepad.rightThumbstick.xAxis.value * 127.0f));
    state.cStickY = static_cast<std::int8_t>(std::lround(gamepad.rightThumbstick.yAxis.value * 127.0f));
    state.triggerL = static_cast<std::uint8_t>(std::lround(gamepad.leftTrigger.value * 255.0f));
    state.triggerR = static_cast<std::uint8_t>(std::lround(gamepad.rightTrigger.value * 255.0f));
    if (state.triggerL > 30) state.buttons |= BellpadButtonL;
    if (state.triggerR > 30) state.buttons |= BellpadButtonR;
    return state;
}

@interface BellpadViewController : UIViewController
@end

@implementation BellpadViewController {
    MTKView *_metalView;
    BellpadMetalRenderer *_renderer;
    BellpadTouchOverlay *_touchOverlay;
    UILabel *_titleLabel;
    UILabel *_statusLabel;
    UIButton *_touchToggle;
    BOOL _controllerConnected;
    id _connectObserver;
    id _disconnectObserver;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _metalView = [[MTKView alloc] initWithFrame:self.view.bounds device:device];
    _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _metalView.preferredFramesPerSecond = 60;
    _metalView.enableSetNeedsDisplay = NO;
    _metalView.paused = NO;
    _renderer = [[BellpadMetalRenderer alloc] initWithDevice:device];
    _metalView.delegate = _renderer;
    [self.view addSubview:_metalView];

    _titleLabel = [UILabel new];
    _titleLabel.text = @"Bellpad native Apple shell";
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    [self.view addSubview:_titleLabel];

    _statusLabel = [UILabel new];
    _statusLabel.text = @"Metal • fixed 60 Hz • touch + controller input\nGame core and user-data import connect next.";
    _statusLabel.numberOfLines = 2;
    _statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.70];
    _statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    [self.view addSubview:_statusLabel];

    _touchOverlay = [[BellpadTouchOverlay alloc] initWithFrame:self.view.bounds];
    _touchOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_touchOverlay];

    _touchToggle = [UIButton buttonWithType:UIButtonTypeSystem];
    [_touchToggle setTitle:@"Hide controls" forState:UIControlStateNormal];
    [_touchToggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _touchToggle.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _touchToggle.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.78];
    _touchToggle.layer.cornerRadius = 14.0;
    [_touchToggle addTarget:self action:@selector(toggleTouchControls) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_touchToggle];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    __weak BellpadViewController *weakSelf = self;
    _connectObserver = [center addObserverForName:GCControllerDidConnectNotification
                                           object:nil queue:NSOperationQueue.mainQueue
                                       usingBlock:^(NSNotification *note) {
        [weakSelf configureController:note.object];
        [weakSelf refreshControllerVisibility];
    }];
    _disconnectObserver = [center addObserverForName:GCControllerDidDisconnectNotification
                                              object:nil queue:NSOperationQueue.mainQueue
                                          usingBlock:^(NSNotification *note) {
        (void)note;
        BellpadClearInputState(BellpadInputSource::Controller);
        [weakSelf refreshControllerVisibility];
    }];
    for (GCController *controller in GCController.controllers) {
        [self configureController:controller];
    }
    [self refreshControllerVisibility];

    [center addObserver:self selector:@selector(appWillResignActive)
                   name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(appDidBecomeActive)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat chromeScale = std::min<CGFloat>(1.0, std::max<CGFloat>(0.62, self.view.bounds.size.width / 800.0));
    CGFloat left = insets.left + 22.0 * chromeScale;
    CGFloat top = insets.top + 16.0 * chromeScale;
    CGFloat available = std::max<CGFloat>(240.0, self.view.bounds.size.width - left - insets.right - 170.0);
    _titleLabel.text = self.view.bounds.size.width < 700.0 ? @"Bellpad" : @"Bellpad native Apple shell";
    _statusLabel.text = self.view.bounds.size.width < 700.0
        ? @"Metal • fixed 60 Hz • touch + controller\nGame core integration is next."
        : @"Metal • fixed 60 Hz • touch + controller input\nGame core and user-data import connect next.";
    _titleLabel.font = [UIFont systemFontOfSize:std::max<CGFloat>(15.0, 22.0 * chromeScale)
                                         weight:UIFontWeightSemibold];
    _statusLabel.font = [UIFont systemFontOfSize:std::max<CGFloat>(10.0, 13.0 * chromeScale)
                                          weight:UIFontWeightRegular];
    _touchToggle.titleLabel.font = [UIFont systemFontOfSize:std::max<CGFloat>(10.0, 13.0 * chromeScale)
                                                   weight:UIFontWeightSemibold];
    _titleLabel.frame = CGRectMake(left, top, available, 28.0 * chromeScale);
    BOOL pad = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
               self.view.bounds.size.width >= 1100.0 && self.view.bounds.size.height >= 700.0;
    if (pad) {
        _statusLabel.frame = CGRectMake(left, CGRectGetMaxY(_titleLabel.frame) + 4.0, available, 40.0);
    } else {
        CGFloat statusWidth = std::min<CGFloat>(390.0 * chromeScale, self.view.bounds.size.width * 0.46);
        _statusLabel.frame = CGRectMake(CGRectGetMidX(self.view.bounds) - statusWidth * 0.5,
                                        CGRectGetMidY(self.view.bounds) - 24.0, statusWidth, 48.0);
        _statusLabel.textAlignment = NSTextAlignmentCenter;
    }
    CGFloat toggleWidth = 112.0 * chromeScale;
    CGFloat toggleHeight = 30.0 * chromeScale;
    _touchToggle.frame = CGRectMake(self.view.bounds.size.width - insets.right - toggleWidth - 16.0 * chromeScale,
                                    top, toggleWidth, toggleHeight);
}

- (void)configureController:(GCController *)controller {
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (gamepad == nil) return;
    gamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
        (void)element;
        BellpadSetInputState(BellpadInputSource::Controller, BellpadStateFromGamepad(pad));
    };
}

- (void)refreshControllerVisibility {
    _controllerConnected = NO;
#if !TARGET_OS_SIMULATOR
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) {
            _controllerConnected = YES;
            break;
        }
    }
#endif
    if (_controllerConnected) {
        [_touchOverlay clearState];
        _touchOverlay.hidden = YES;
        [_touchToggle setTitle:@"Show controls" forState:UIControlStateNormal];
        _statusLabel.text = @"Metal • fixed 60 Hz • physical controller connected\nTouch controls auto-hidden; tap Show controls to override.";
    } else {
        _touchOverlay.hidden = NO;
        [_touchToggle setTitle:@"Hide controls" forState:UIControlStateNormal];
        _statusLabel.text = self.view.bounds.size.width < 700.0
            ? @"Metal • fixed 60 Hz • touch + controller\nGame core integration is next."
            : @"Metal • fixed 60 Hz • touch + controller input\nGame core and user-data import connect next.";
    }
}

- (void)toggleTouchControls {
    _touchOverlay.hidden = !_touchOverlay.hidden;
    if (_touchOverlay.hidden) [_touchOverlay clearState];
    [_touchToggle setTitle:_touchOverlay.hidden ? @"Show controls" : @"Hide controls"
                   forState:UIControlStateNormal];
}

- (void)appWillResignActive {
    [_touchOverlay clearState];
    BellpadClearInputState(BellpadInputSource::Controller);
    _metalView.paused = YES;
}

- (void)appDidBecomeActive {
    _metalView.paused = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _metalView.paused = NO;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

@end

@interface BellpadAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end


@implementation BellpadAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [BellpadViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    BellpadClearInputState(BellpadInputSource::Touch);
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    BellpadClearInputState(BellpadInputSource::Touch);
    BellpadClearInputState(BellpadInputSource::Controller);
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(BellpadAppDelegate.class));
    }
}
