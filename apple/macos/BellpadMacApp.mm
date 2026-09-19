#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#import <MetalKit/MetalKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "BellpadDiscValidator.h"
#include "BellpadInput.h"

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
    if (pass == nil || drawable == nil) {
        return;
    }
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.035, 0.055, 0.095, 1.0);
    id<MTLCommandBuffer> buffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];
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
    state.stickX = static_cast<std::int8_t>(gamepad.leftThumbstick.xAxis.value * 127.0f);
    state.stickY = static_cast<std::int8_t>(gamepad.leftThumbstick.yAxis.value * 127.0f);
    state.cStickX = static_cast<std::int8_t>(gamepad.rightThumbstick.xAxis.value * 127.0f);
    state.cStickY = static_cast<std::int8_t>(gamepad.rightThumbstick.yAxis.value * 127.0f);
    state.triggerL = static_cast<std::uint8_t>(gamepad.leftTrigger.value * 255.0f);
    state.triggerR = static_cast<std::uint8_t>(gamepad.rightTrigger.value * 255.0f);
    if (state.triggerL > 30) state.buttons |= BellpadButtonL;
    if (state.triggerR > 30) state.buttons |= BellpadButtonR;
    return state;
}

@interface BellpadMacDelegate : NSObject <NSApplicationDelegate>
@end

@implementation BellpadMacDelegate {
    NSWindow *_window;
    BellpadMetalRenderer *_renderer;
    NSTextField *_status;
    id _connectObserver;
    id _disconnectObserver;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSRect frame = NSMakeRect(0, 0, 1100, 700);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _window.title = @"BellPad — Native Apple shell";
    [_window center];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MTKView *metalView = [[MTKView alloc] initWithFrame:frame device:device];
    metalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    metalView.preferredFramesPerSecond = 60;
    metalView.enableSetNeedsDisplay = NO;
    metalView.paused = NO;
    _renderer = [[BellpadMetalRenderer alloc] initWithDevice:device];
    metalView.delegate = _renderer;

    NSTextField *title = [NSTextField labelWithString:@"BellPad native macOS shell"];
    title.font = [NSFont systemFontOfSize:26 weight:NSFontWeightSemibold];
    title.textColor = NSColor.whiteColor;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [metalView addSubview:title];

    _status = [NSTextField labelWithString:
        @"Metal • fixed 60 Hz presentation • GameController input ready\nGame core and user-data import are the next integration boundary."];
    _status.font = [NSFont systemFontOfSize:15];
    _status.textColor = [NSColor colorWithWhite:1.0 alpha:0.72];
    _status.maximumNumberOfLines = 2;
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [metalView addSubview:_status];

    NSButton *chooseData = [NSButton buttonWithTitle:@"Choose Game Data…"
                                              target:self
                                              action:@selector(chooseGameData:)];
    chooseData.bezelStyle = NSBezelStyleRounded;
    chooseData.translatesAutoresizingMaskIntoConstraints = NO;
    [metalView addSubview:chooseData];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:metalView.leadingAnchor constant:36],
        [title.topAnchor constraintEqualToAnchor:metalView.topAnchor constant:36],
        [_status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_status.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [chooseData.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [chooseData.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:18],
    ]];

    _window.contentView = metalView;
    [_window makeKeyAndOrderFront:nil];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    __weak BellpadMacDelegate *weakSelf = self;
    _connectObserver = [center addObserverForName:GCControllerDidConnectNotification
                                           object:nil
                                            queue:NSOperationQueue.mainQueue
                                       usingBlock:^(NSNotification *note) {
        [weakSelf configureController:note.object];
    }];
    _disconnectObserver = [center addObserverForName:GCControllerDidDisconnectNotification
                                              object:nil
                                               queue:NSOperationQueue.mainQueue
                                          usingBlock:^(NSNotification *note) {
        (void)note;
        BellpadClearInputState(BellpadInputSource::Controller);
    }];
    for (GCController *controller in GCController.controllers) {
        [self configureController:controller];
    }
}

- (void)chooseGameData:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[
        [UTType typeWithFilenameExtension:@"iso"],
        [UTType typeWithFilenameExtension:@"gcm"],
    ];
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || panel.URL == nil) return;
        const auto result = BellpadValidateDiscImage(panel.URL.fileSystemRepresentation);
        const std::string message = BellpadDiscValidationMessage(result);
        self->_status.stringValue = [NSString stringWithUTF8String:message.c_str()];
        self->_status.textColor = result.valid()
            ? [NSColor colorWithRed:0.45 green:0.90 blue:0.68 alpha:1.0]
            : [NSColor colorWithRed:1.0 green:0.55 blue:0.55 alpha:1.0];
    }];
}

- (void)configureController:(GCController *)controller {
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (gamepad == nil) return;
    gamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
        (void)element;
        BellpadSetInputState(BellpadInputSource::Controller, BellpadStateFromGamepad(pad));
    };
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    BellpadClearInputState(BellpadInputSource::Controller);
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        BellpadMacDelegate *delegate = [BellpadMacDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
