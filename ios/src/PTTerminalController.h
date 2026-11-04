#import <UIKit/UIKit.h>
#import "PTProfile.h"
#import "PTSession.h"
#include "pt_launch.h"

/* One agent session: owns pt_conn + pt_term, the host-key question, reconnects and resizes.
 * Presented full screen over the home split view. */
@interface PTTerminalController : UIViewController
- (instancetype)initWithProfile:(PTProfile *)profile session:(PTSession *)session; /* Claude or Codex: new or continued */
- (instancetype)initWithProfile:(PTProfile *)profile agent:(pt_agent)agent;        /* the Shell */
/* Stops the connection and reconnects, releases the screen lock. Safe to call twice. */
- (void)endSession;
@end
