#import <UIKit/UIKit.h>
#import "PTSettings.h"
#import "PTSplitController.h"
#import "PTTheme.h"
#include "pt_ssh.h"
#ifdef PT_SELFTEST
#import "PTSelfTest.h"
#endif

@interface PTAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
- (void)showHomeInWindow:(UIWindow *)window;
@end

@implementation PTAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    if (pt_ssh_global_init() != 0) { NSLog(@"PadTerm: libssh2 init failed"); abort(); } /* fail at start, not on first connect */
    [PTSettingsController registerDefaults];
    /* iOS 13: Info.plist declares a scene, so PTSceneDelegate gets the window. Below iOS 13 the manifest means nothing. */
    if (!NSClassFromString(@"UIWindowScene")) [self showHomeInWindow:[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds]];
    return YES;
}

- (void)showHomeInWindow:(UIWindow *)window {
    self.window = window;
    [PTTheme applyAppearance]; /* after the window exists: it takes the chosen mode's colour */
    PTSplitController *home = [[PTSplitController alloc] init];
    window.rootViewController = home;
    [window makeKeyAndVisible];
#ifdef PT_SELFTEST
    [PTSelfTest startWithHome:home];
#endif
}
@end

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
/* TN3187: an app linked with the SDK after iOS 26 must use scenes or it will not launch. Only iOS 13 and later load this class. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
@interface PTSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation PTSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    [(PTAppDelegate *)[UIApplication sharedApplication].delegate showHomeInWindow:self.window];
}
@end
#pragma clang diagnostic pop
#endif

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([PTAppDelegate class]));
    }
}
