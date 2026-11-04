#import "PTSplitController.h"
#import "PTEmptyController.h"
#import "PTLaunchController.h"
#import "PTProfileEditController.h"
#import "PTProfileListController.h"
#import "PTProfileStore.h"
#import "PTTheme.h"

/* The stock bar, in the style of the chosen appearance. */
@implementation PTNavigationController
- (void)viewDidLoad {
    [super viewDidLoad];
    [PTTheme styleNavigationBar:self.navigationBar];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged) name:PTAppearanceDidChangeNotification object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)appearanceChanged { [PTTheme styleNavigationBar:self.navigationBar]; }
- (BOOL)shouldAutorotate { return self.topViewController.shouldAutorotate; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return self.topViewController.supportedInterfaceOrientations; }
@end

@interface PTSplitController () <UISplitViewControllerDelegate>
@end

@implementation PTSplitController {
    PTProfileListController *_list;
    BOOL _warnedLeftover;
}

- (instancetype)init {
    if ((self = [super init])) {
        _list = [[PTProfileListController alloc] init];
        _detailNav = [[PTNavigationController alloc] init];
        self.viewControllers = @[[[PTNavigationController alloc] initWithRootViewController:_list], _detailNav];
        self.delegate = self;
        [self showProfile:[[PTProfileStore shared] profiles].firstObject];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [PTTheme surfaceColor];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged) name:PTAppearanceDidChangeNotification object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [PTTheme applyToWindow:self.view.window];
}

/* A private key copied for import stays readable through File Sharing until it is imported or deleted. */
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSArray *left = [[PTProfileStore shared] leftoverKeyFiles];
    if (_warnedLeftover || !left.count) return;
    _warnedLeftover = YES;
    [PTTheme showMessage:[NSString stringWithFormat:@"%@ is still in this app's Documents folder. Import it with a server of that name, or delete it in File Sharing.", [left componentsJoinedByString:@", "]]
                   title:@"Private key file found" from:self];
}

- (void)appearanceChanged {
    self.view.backgroundColor = [PTTheme surfaceColor];
    [PTTheme applyToWindow:self.view.window];
}

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

/* The server list stays on screen in portrait too. */
- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)o {
    return NO;
}

- (void)showProfile:(PTProfile *)profile {
    UIViewController *vc = profile ? [[PTLaunchController alloc] initWithProfile:profile] : [[PTEmptyController alloc] init];
    [_detailNav setViewControllers:@[vc] animated:NO];
    _list.selectedUID = profile.uid;
    [_list reload];
}

- (void)reloadList { [_list reload]; }

- (void)editProfile:(PTProfile *)profile isNew:(BOOL)isNew {
    PTProfileEditController *edit = [[PTProfileEditController alloc] initWithProfile:profile isNew:isNew];
    __weak PTSplitController *weakSelf = self;
    edit.saved = ^(PTProfile *p) { [weakSelf showProfile:p]; };
    PTNavigationController *nav = [[PTNavigationController alloc] initWithRootViewController:edit];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    /* iOS 13: a swipe would close the sheet past Cancel and Save, and the key clean-up in them. */
    if ([nav respondsToSelector:NSSelectorFromString(@"setModalInPresentation:")]) [nav setValue:@YES forKey:@"modalInPresentation"];
    [self dismissModals];
    [self presentViewController:nav animated:YES completion:nil];
}

- (PTTerminalController *)terminal {
    UIViewController *shown = self.presentedViewController; /* it can also be an alert */
    UIViewController *top = [shown isKindOfClass:[UINavigationController class]] ? [(UINavigationController *)shown topViewController] : nil;
    return [top isKindOfClass:[PTTerminalController class]] ? (PTTerminalController *)top : nil;
}

- (void)openTerminalForProfile:(PTProfile *)profile agent:(pt_agent)agent {
    if (agent == PT_AGENT_SHELL) [self presentTerminal:[[PTTerminalController alloc] initWithProfile:profile agent:agent]];
    else [self openTerminalForProfile:profile session:[PTSession newSessionWithAgent:agent directory:profile.directory]];
}

- (void)openTerminalForProfile:(PTProfile *)profile session:(PTSession *)session {
    [self presentTerminal:[[PTTerminalController alloc] initWithProfile:profile session:session]];
}

- (void)presentTerminal:(PTTerminalController *)term {
    PTTerminalController *old = [self terminal];
    if (old) {
        [old endSession];
        [(UINavigationController *)self.presentedViewController setViewControllers:@[term] animated:NO];
        return;
    }
    [self dismissModals];
    PTNavigationController *nav = [[PTNavigationController alloc] initWithRootViewController:term];
    nav.modalPresentationStyle = UIModalPresentationFullScreen; /* iOS 13: the default became a small sheet that a swipe closes */
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)dismissModals {
    if (!self.presentedViewController) return;
    [[self terminal] endSession];
    [self dismissViewControllerAnimated:NO completion:nil];
}
@end
