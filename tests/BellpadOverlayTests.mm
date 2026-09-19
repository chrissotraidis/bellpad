// Isolated Simulator host: exercises the real UIKit overlay, never retail data.
#import "../apple/ios/BellpadGameOverlay.mm"
#include <cassert>
extern "C" void SDL_SetLogOutputFunction(SDL_LogOutputFunction callback, void *userdata) { (void)callback; (void)userdata; }
// Deterministic touch identities/coordinates exercise the real event handlers.
// This is not device touch injection or a physical gesture acceptance test.
@interface BPTestTouch : UITouch
@property(nonatomic, weak) UIView *coordinateView;
@property(nonatomic) CGPoint point;
@end
@implementation BPTestTouch
- (CGPoint)locationInView:(UIView *)view {
    return [self.coordinateView convertPoint:self.point toView:view];
}
@end

static BPTestTouch *BPTouch(UIView *view, CGPoint point) {
    BPTestTouch *touch = [BPTestTouch new];
    touch.coordinateView = view; touch.point = point;
    return touch;
}

static void BPTestFloatingMovement(BPGameOverlay *overlay) {
    [overlay closeSettingsPanel];
    [overlay setValue:@NO forKey:@"controllerConnected"];
    [overlay setValue:@NO forKey:@"manualControlsHidden"];
    [overlay setValue:@YES forKey:@"autoHideControls"];
    [overlay layoutSubviews];
    BPStickView *move = [overlay valueForKey:@"moveStick"];
    BPStickView *camera = [overlay valueForKey:@"cameraStick"];
    assert(move.hidden && !camera.hidden);
    CGRect resting = move.frame;
    CGRect region = [overlay floatingMoveRegion];
    CGPoint origin = CGPointMake(CGRectGetMinX(region) + 8, CGRectGetMidY(region));
    assert([overlay hitTest:origin withEvent:nil] == overlay);
    BPTestTouch *thumb = BPTouch(overlay, origin);
    BPTestTouch *other = BPTouch(overlay, CGPointMake(origin.x + 24, origin.y));
    NSDictionary *preferences = [NSUserDefaults.standardUserDefaults dictionaryRepresentation];
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    assert(!move.hidden && !move.userInteractionEnabled && CGPointEqualToPoint(move.center, origin));
    assert(BellpadGetMergedInputState().stickX == 0 && BellpadGetMergedInputState().stickY == 0);
    [overlay touchesBegan:[NSSet setWithObject:other] withEvent:nil];
    [overlay touchesMoved:[NSSet setWithObject:other] withEvent:nil];
    [overlay touchesEnded:[NSSet setWithObject:other] withEvent:nil];
    assert(!move.hidden && CGPointEqualToPoint(move.center, origin));
    move.deadzone = 0.2;
    thumb.point = CGPointMake(origin.x + move.bounds.size.width * 0.05, origin.y);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    assert(BellpadGetMergedInputState().stickX == 0);
    thumb.point = CGPointMake(origin.x + move.bounds.size.width, origin.y);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    assert(BellpadGetMergedInputState().stickX == 127);
    [overlay layoutSubviews]; // Ordinary layout must not recenter an active gesture.
    assert(CGPointEqualToPoint(move.center, origin) && BellpadGetMergedInputState().stickX == 127);
    // A second finger still reaches real buttons, including any in the region.
    for (UIView *control in [overlay gameplayControls]) {
        if (control == move) continue;
        assert([overlay hitTest:control.center withEvent:nil] != overlay);
    }
    BPGameButton *a = [overlay button:@"A"];
    [overlay buttonDown:a];
    thumb.point = CGPointMake(CGRectGetMaxX(region) + 80, CGRectGetMinY(region) - 80);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    assert(BellpadGetMergedInputState().stickX > 0 && BellpadGetMergedInputState().stickY > 0);
    [overlay touchesEnded:[NSSet setWithObject:thumb] withEvent:nil];
    assert(move.hidden && CGRectEqualToRect(move.frame, resting));
    assert(BellpadGetMergedInputState().stickX == 0 && BellpadGetMergedInputState().stickY == 0);
    assert(BellpadGetMergedInputState().buttons & BellpadButtonA);
    [overlay buttonUp:a];
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    assert(move.hidden && BellpadGetMergedInputState().stickX == 0);
    assert([preferences isEqual:[NSUserDefaults.standardUserDefaults dictionaryRepresentation]]);
    // Outside the region cannot start; each new valid contact picks a new origin.
    thumb.point = CGPointMake(CGRectGetMidX(overlay.bounds), CGRectGetMidY(overlay.bounds));
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil]; assert(move.hidden);
    thumb.point = CGPointMake(origin.x + 16, origin.y - 8);
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    assert(CGPointEqualToPoint(move.center, thumb.point));
    [overlay touchesCancelled:[NSSet setWithObject:thumb] withEvent:nil]; assert(move.hidden);
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil]; [overlay menuWillOpen];
    assert(move.hidden && BellpadGetMergedInputState().stickX == 0);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil]; assert(move.hidden);
    [overlay toggleSettings];
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil]; assert(move.hidden);
    [overlay closeSettingsPanel];
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    [overlay setNativeTextActive:YES]; assert(move.hidden);
    [overlay setNativeTextActive:NO];
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    [overlay setValue:@YES forKey:@"controllerConnected"]; [overlay updateControlAppearance];
    assert(move.hidden);
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil]; assert(move.hidden);
    [overlay setValue:@NO forKey:@"controllerConnected"]; [overlay updateControlAppearance];
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    [overlay willResignActive:nil]; assert(move.hidden);
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    CGRect bounds = overlay.bounds; overlay.bounds = CGRectInset(bounds, 0, 4);
    [overlay layoutSubviews]; assert(move.hidden && BellpadGetMergedInputState().stickX == 0);
    overlay.bounds = bounds; [overlay layoutSubviews];
    [overlay setValue:@YES forKey:@"manualControlsHidden"]; [overlay updateControlAppearance];
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil]; assert(move.hidden);
    [overlay setValue:@NO forKey:@"manualControlsHidden"]; [overlay updateControlAppearance];
}

@interface BPOverlayTestApp : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation BPOverlayTestApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            BPGameOverlay *overlay = [[BPGameOverlay alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
            [self.window.rootViewController.view addSubview:overlay];
            [overlay layoutSubviews];
            BPTestFloatingMovement(overlay);
            UIButton *menu = [overlay valueForKey:@"settingsButton"];
            assert(menu.showsMenuAsPrimaryAction && menu.bounds.size.width >= 44);
            assert(menu.menu.children.count == 5);
            assert([menu.menu.children[0].title isEqualToString:@"Display"]);
            assert([menu.menu.children[1].title isEqualToString:@"Controls"]);
            assert([menu.menu.title isEqualToString:@"BellPad"]);
            assert([menu.menu.children[3].title isEqualToString:@"Report a Problem…"]);
            UIAlertController *report = BPProblemReportPrompt(self.window.rootViewController, menu, @"Fixture");
            assert([report.title isEqualToString:@"Report a Problem"] && report.textFields.count == 3);
            assert(report.actions.count == 3);
            assert([report.actions[1].title isEqualToString:@"Share Report…"]);
            assert([report.actions[2].title isEqualToString:@"Report on GitHub"]);
            assert(report.preferredAction == report.actions[2]);
            UIMenu *data = (UIMenu *)menu.menu.children[2];
            assert(data.children.count == 4); // export/import/change/remove all retained
            BPGameButton *a = [overlay button:@"A"];
            [overlay buttonDown:a];
            assert(BellpadGetMergedInputState().buttons & BellpadButtonA);
            [overlay menuWillOpen];
            assert(BellpadGetMergedInputState().buttons == 0);
            [overlay toggleSettings];
            UIView *panel = [overlay valueForKey:@"settingsPanel"];
            assert(!panel.hidden);
            UISwitch *editing = [overlay valueForKey:@"editLayoutSwitch"];
            editing.on = YES; [editing sendActionsForControlEvents:UIControlEventValueChanged];
            [overlay buttonDown:a];
            assert(BellpadGetMergedInputState().buttons == 0);
            [overlay setValue:@YES forKey:@"controllerConnected"];
            [overlay updateControlAppearance];
            assert(!a.hidden); // layout stays editable with a controller attached
            assert(![[overlay valueForKey:@"moveStick"] isHidden]);
            [overlay selectControlForEditing:a];
            UISlider *size = [overlay valueForKey:@"selectedScaleSlider"];
            assert(size.enabled);
            [overlay closeSettingsPanel];
            assert(panel.hidden && !editing.on && !size.enabled);
            assert(a.hidden); // normal auto-hide restored
            [overlay setValue:@NO forKey:@"autoHideControls"];
            [overlay updateControlAppearance];
            assert(!a.hidden);
            [overlay setNativeTextActive:YES]; assert(a.hidden && menu.hidden);
            [overlay setNativeTextActive:NO]; assert(!a.hidden && !menu.hidden);
            [overlay buttonDown:a]; [overlay willResignActive:nil];
            assert(BellpadGetMergedInputState().buttons == 0);
            for (NSValue *sizeValue in @[[NSValue valueWithCGSize:CGSizeMake(844,390)], [NSValue valueWithCGSize:CGSizeMake(1194,834)]]) {
                overlay.frame = (CGRect){CGPointZero, sizeValue.CGSizeValue};
                [overlay layoutSubviews];
                BPTestFloatingMovement(overlay);
                assert(CGRectContainsRect(overlay.bounds, menu.frame));
                assert(CGRectContainsRect(overlay.bounds, panel.frame));
            }
            NSDictionary *result = @{ @"passed": @YES, @"checks": @"floating-stick ownership/region/deadzone/multitouch/cancel/layout/state preservation; unified reporting prompt; menu/data actions; held-input release; layout editing; controller auto-hide override; native text; lifecycle; iPhone/iPad bounds" };
            NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
            [json writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/overlay-tests.json"] atomically:YES];
            overlay.frame = self.window.rootViewController.view.bounds;
            [overlay layoutSubviews];
            [overlay toggleSettings];
        } @catch (NSException *error) {
            NSLog(@"Overlay test failure: %@", error); abort();
        }
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(BPOverlayTestApp.class)); }
}
