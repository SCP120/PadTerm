#import <UIKit/UIKit.h>
#import "PTSplitController.h"

/* Test-only (SELFTEST=1 builds): lets the Mac drive the app over USB. Never in a release build. */
@interface PTSelfTest : NSObject
+ (void)startWithHome:(PTSplitController *)home;
@end
