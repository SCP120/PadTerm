#import <UIKit/UIKit.h>
#import "PTProfile.h"
#import "PTSession.h"
#include "pt_launch.h"

/* The list of UC-SESSION: a grouped table, Settings style. On the server page it also has the "New Session" group
 * (Claude, Codex, Shell); in the terminal's Sessions popover it has the sessions only. */
@interface PTSessionListController : UITableViewController
- (instancetype)initWithProfile:(PTProfile *)profile;
@property (nonatomic, copy) void (^selected)(PTSession *session);
@property (nonatomic, copy) NSString *currentKey; /* the session of the open terminal: it has a check mark */
@property (nonatomic, readonly) NSArray *sessions;
@property (nonatomic, readonly) NSString *footerMessage; /* the footer of the sessions group */
@property (nonatomic) BOOL showsNewSession;               /* the "New Session" group above the sessions */
@property (nonatomic, copy) void (^onNewSession)(pt_agent agent);
@property (nonatomic, copy) NSString *startFooter; /* the footer under the New Session group */
- (void)refresh;
#ifdef PT_SELFTEST
- (void)testSwipeDeleteRow:(NSInteger)row;
- (void)testSelectRow:(NSInteger)row; /* row among the sessions */
#endif
@end
