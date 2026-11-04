#import <UIKit/UIKit.h>
#import "PTProfile.h"
#import "PTSessionListController.h"

/* AC-LAUNCH-1, AC-SESSION-2: the server page in the detail pane: plates that start a session, and the session list. */
@interface PTLaunchController : UIViewController
- (instancetype)initWithProfile:(PTProfile *)profile;
@property (nonatomic, readonly) PTSessionListController *sessionList;
- (void)startAgent:(pt_agent)agent; /* Claude and Codex: a new session; Shell: the one shell */
@end
