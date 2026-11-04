#import <UIKit/UIKit.h>

/* Posted on the main thread after the appearance changed; every screen that is open restyles itself. */
extern NSString *const PTAppearanceDidChangeNotification;

/* Terminal colour themes, chosen by name, and the app appearance (light or dark). */
@interface PTTheme : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) const uint8_t *fg; /* 3 bytes */
@property (nonatomic, readonly) const uint8_t *bg;
+ (NSArray *)all; /* classic dark (default), light, amber, green phosphor */
+ (PTTheme *)current;
+ (void)select:(PTTheme *)theme;
- (UIColor *)fgColor;
- (UIColor *)bgColor;

/* App appearance, kept in NSUserDefaults. Light is the default. Setting it also picks the matching terminal theme
 * (classic for dark, light for light), applies to every open screen at once and posts the notification. */
+ (void)setDarkAppearance:(BOOL)dark;
+ (BOOL)isDarkAppearance;
/* Launch: the window style. The stock controls need nothing else in light mode. */
+ (void)applyAppearance;
+ (void)applyToWindow:(UIWindow *)window;
+ (void)styleNavigationBar:(UINavigationBar *)bar; /* UIBarStyleBlack in dark, stock silver in light */

/* Colours of the current appearance for views that draw their own text. */
+ (UIColor *)textColor;
+ (UIColor *)secondaryColor;
+ (UIColor *)valueColor;   /* slate blue in light, a lighter blue in dark */
+ (UIColor *)timeColor;    /* Mail's blue time stamp */
+ (UIColor *)surfaceColor; /* behind a detail screen */

/* Tables. In light mode these leave the stock look alone. Build a cell, call styleCell, return it. */
+ (NSString *)reuseId:(NSString *)base; /* one queue per appearance, so a dark cell is never reused in light mode */
+ (void)styleTable:(UITableView *)table;
+ (void)styleCell:(UITableViewCell *)cell in:(UITableView *)table at:(NSIndexPath *)indexPath;
+ (void)styleHeaderFooter:(UIView *)view; /* from willDisplayHeaderView / willDisplayFooterView */

/* Popovers: black glass in dark mode, nil (stock) in light mode. */
+ (Class)popoverBackgroundClass;
+ (UIKeyboardAppearance)keyboardAppearance;
/* Grey caption in the style of Mail's "No Mail". */
+ (UILabel *)emptyLabel:(NSString *)text size:(CGFloat)size;
/* A one-button message: UIAlertController from iOS 8, UIAlertView before. */
+ (void)showMessage:(NSString *)text title:(NSString *)title from:(UIViewController *)vc;
#ifdef PT_SELFTEST
+ (UIAlertView *)testLastAlert;
#endif
@end
