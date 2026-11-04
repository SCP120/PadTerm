#import <UIKit/UIKit.h>

extern NSString *const PTFontKey, *const PTThemeKey, *const PTKeyClickKey, *const PTKeepAwakeKey;
/* Font sizes the stepper offers; 13 pt gives 128 columns in landscape on the 1024-pt iPad screen. */
enum { PT_FONT_MIN = 9, PT_FONT_DEFAULT = 13, PT_FONT_MAX = 24 };

@protocol PTSettingsDelegate <NSObject>
- (void)settingsChanged; /* font, theme or keep-awake changed in NSUserDefaults */
@end

/* The popover behind the gear (design 4.6). Every change is written to NSUserDefaults at once. */
@interface PTSettingsController : UITableViewController
@property (nonatomic, weak) id<PTSettingsDelegate> delegate;
+ (void)registerDefaults; /* key click and keep-awake default to on */
@end
