#import <UIKit/UIKit.h>
#import "PTProfile.h"
#import "PTSession.h"
#import "PTTerminalController.h"
#include "pt_launch.h"

/* iOS 6 asks the top view controller of a navigation controller about rotation through the nav controller. */
@interface PTNavigationController : UINavigationController
@end

/* Home (design 4.1): servers on the left, agent chooser on the right, master always visible.
 * The terminal and the server form are presented over it, so the terminal is full screen. */
@interface PTSplitController : UISplitViewController
@property (nonatomic, readonly) UINavigationController *detailNav;
- (void)showProfile:(PTProfile *)profile; /* nil: the empty state */
- (void)reloadList;
- (void)editProfile:(PTProfile *)profile isNew:(BOOL)isNew;
/* Replaces the terminal that is already open, if any. Claude and Codex: a new session; Shell: the one shell session. */
- (void)openTerminalForProfile:(PTProfile *)profile agent:(pt_agent)agent;
/* AC-SESSION-5: continue a session from the list. */
- (void)openTerminalForProfile:(PTProfile *)profile session:(PTSession *)session;
- (PTTerminalController *)terminal; /* the open terminal or nil */
- (void)dismissModals;              /* ends the terminal session first */
@end
