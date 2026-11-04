#import <UIKit/UIKit.h>
#include "pt_keys.h"

@protocol PTKeyBarDelegate <NSObject>
- (void)keyBarKey:(pt_key)key;
- (void)keyBarCtrlChanged:(BOOL)armed;
- (void)keyBarHideKeyboard;
@end

/* The key bar above the keyboard (AC-INPUT-1): five groups of keys. */
@interface PTKeyBar : UIView <UIInputViewAudioFeedback>
@property (nonatomic, weak) id<PTKeyBarDelegate> delegate;
- (void)setCtrlArmed:(BOOL)armed;
@end
