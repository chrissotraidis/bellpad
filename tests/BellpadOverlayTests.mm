// Isolated Simulator host: exercises the real UIKit overlay, never retail data.
#import "../apple/ios/BellpadGameOverlay.mm"
#include <cassert>
extern "C" void SDL_SetLogOutputFunction(SDL_LogOutputFunction callback, void *userdata) { (void)callback; (void)userdata; }
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
                assert(CGRectContainsRect(overlay.bounds, menu.frame));
                assert(CGRectContainsRect(overlay.bounds, panel.frame));
            }
            NSDictionary *result = @{ @"passed": @YES, @"checks": @"unified reporting prompt; menu/data actions; held-input release; layout editing; controller auto-hide override; native text; lifecycle; iPhone/iPad bounds" };
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
