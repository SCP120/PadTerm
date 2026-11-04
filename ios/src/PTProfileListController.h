#import <UIKit/UIKit.h>

/* The server list (master pane): leather bar, dark rows with an LED. */
@interface PTProfileListController : UITableViewController
@property (nonatomic, copy) NSString *selectedUID; /* the profile the detail pane shows */
- (void)reload; /* reload and keep the selected row highlighted */
@end
