#import <UIKit/UIKit.h>
#import "PTProfile.h"

/* AC-PROFILE-1 / AC-PROFILE-2: edit one profile and its key, in a form sheet. */
@interface PTProfileEditController : UITableViewController
/* Called after a successful save; the controller dismisses itself either way. */
@property (nonatomic, copy) void (^saved)(PTProfile *profile);
- (instancetype)initWithProfile:(PTProfile *)profile isNew:(BOOL)isNew;
@end
