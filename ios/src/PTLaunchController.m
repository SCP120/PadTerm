#import "PTLaunchController.h"
#import "PTSplitController.h"

/* The server page: Settings' grouped "New Session" rows, then the sessions in the layout of Mail's list. One table. */
@implementation PTLaunchController {
    PTProfile *_profile;
}

- (instancetype)initWithProfile:(PTProfile *)profile {
    if ((self = [super init])) { _profile = profile; self.title = profile.name; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Edit" style:UIBarButtonItemStyleBordered
                                                                              target:self action:@selector(edit)];
    __weak PTLaunchController *weakSelf = self;
    _sessionList = [[PTSessionListController alloc] initWithProfile:_profile];
    _sessionList.showsNewSession = YES;
    _sessionList.startFooter = [NSString stringWithFormat:@"%@@%@:%ld in %@\nClaude and Codex start and resume in auto mode: they can edit files and run commands in this directory without asking each time.", _profile.user, _profile.host, (long)_profile.port, _profile.directory];
    _sessionList.onNewSession = ^(pt_agent agent) { [weakSelf startAgent:agent]; };
    _sessionList.selected = ^(PTSession *session) {
        PTLaunchController *me = weakSelf;
        [(PTSplitController *)me.splitViewController openTerminalForProfile:me->_profile session:session];
    };
    [self addChildViewController:_sessionList];
    _sessionList.view.frame = self.view.bounds;
    _sessionList.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_sessionList.view];
    [_sessionList didMoveToParentViewController:self];
}

- (void)startAgent:(pt_agent)agent {
    [(PTSplitController *)self.splitViewController openTerminalForProfile:_profile agent:agent];
}

- (void)edit { [(PTSplitController *)self.splitViewController editProfile:_profile isNew:NO]; }

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end
