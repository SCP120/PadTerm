#import <UIKit/UIKit.h>
#include "pt_keys.h"
#include "pt_term.h"
#include "pt_render.h"

@protocol PTTerminalViewDelegate <NSObject>
- (void)terminalViewDidType:(NSString *)text;   /* keyboard text */
- (void)terminalViewDidTypeControl:(char)byte;  /* key-bar Ctrl + key: the C0 byte, sent as is */
- (void)terminalViewHardwareKey:(pt_key)key;    /* a Bluetooth or Smart Keyboard: arrows, Esc (iOS 7) */
- (void)terminalViewDidBackspace;
- (void)terminalViewTapAtRow:(int)row col:(int)col;
- (void)terminalViewWheelAtRow:(int)row col:(int)col lines:(int)linesUp;
- (void)terminalViewPaste:(NSString *)text;
@end

/* Draws a pt_term with the renderer; takes keyboard text (UIKeyInput), taps and swipes. */
@interface PTTerminalView : UIView <UIKeyInput, UITextInputTraits>
@property (nonatomic, weak) id<PTTerminalViewDelegate> delegate;
@property (nonatomic, assign) pt_term *term;     /* owned by the controller */
@property (nonatomic, assign) pt_render *render; /* owned by the controller */
@property (nonatomic, assign) uint8_t *themeBackground; /* 3 bytes, owned by the controller */
@property (nonatomic, assign) BOOL ctrlArmed;    /* one-shot Ctrl from the key bar */
@property (nonatomic, copy) void (^ctrlConsumed)(void);
- (void)gridRows:(int *)rows cols:(int *)cols;   /* rows/cols that fit the current bounds */
@end
