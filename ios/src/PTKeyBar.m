#import "PTKeyBar.h"
#import "PTArt.h"
#import "PTSettings.h"
#import "PTTheme.h"
#import <QuartzCore/QuartzCore.h>

enum { PT_KEY_CTRL_TAG = 1000, PT_KEY_HIDE_TAG = 1001 };
/* Design 4.5: 44 pt keys (HIG minimum touch target) with 3 pt above and below. */
enum { BAR_H = 50, KEY_H = 44, KEY_Y = 3, SIDE = 6, GAP_IN = 4, GAP_BETWEEN = 14, DOT = 6 };

@implementation PTKeyBar {
    UIButton *_ctrl;
    UIView *_dot;
    BOOL _armed;
}

static const struct { const char *title; int tag; } KEYS[] = {
    {"Esc", PT_KEY_ESC}, {"Tab", PT_KEY_TAB}, {"\xE2\x87\xA7Tab", PT_KEY_BACKTAB},
    {"Ctrl", PT_KEY_CTRL_TAG}, {"^C", PT_KEY_CTRL_C},
    {"\xE2\x86\x90", PT_KEY_LEFT}, {"\xE2\x86\x91", PT_KEY_UP}, {"\xE2\x86\x93", PT_KEY_DOWN}, {"\xE2\x86\x92", PT_KEY_RIGHT},
    {"PgUp", PT_KEY_PAGEUP}, {"PgDn", PT_KEY_PAGEDOWN},
    {"\xE2\x8F\x8E", PT_KEY_ENTER}, {"\xE2\x8C\xA8\xE2\x86\x93", PT_KEY_HIDE_TAG},
};
static const int GROUPS[] = {3, 2, 4, 2, 2};

- (instancetype)initWithFrame:(CGRect)frame {
    frame.size.height = BAR_H;
    if ((self = [super initWithFrame:frame])) {
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        for (size_t i = 0; i < sizeof KEYS / sizeof *KEYS; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            [b setTitle:[NSString stringWithUTF8String:KEYS[i].title] forState:UIControlStateNormal];
            b.titleLabel.font = [PTArt regular:16];
            b.titleLabel.shadowOffset = CGSizeMake(0, 1);
            b.tag = KEYS[i].tag;
            [b addTarget:self action:@selector(press:) forControlEvents:UIControlEventTouchUpInside];
            if (b.tag == PT_KEY_CTRL_TAG) {
                _ctrl = b;
                _dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, DOT, DOT)];
                _dot.backgroundColor = [UIColor whiteColor];
                _dot.layer.cornerRadius = DOT / 2.0; /* 6 pt, hidden unless armed; not over the terminal */
                _dot.hidden = YES;
                _dot.userInteractionEnabled = NO;
                [b addSubview:_dot];
            }
            [self addSubview:b];
        }
        [self restyle];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(restyle) name:PTAppearanceDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

/* Keys and bar follow the keyboard below: light for the default keyboard, dark for UIKeyboardAppearanceAlert. */
- (void)restyle {
    BOOL dark = [PTTheme isDarkAppearance];
    for (UIButton *b in self.subviews) {
        if (![b isKindOfClass:[UIButton class]]) continue;
        [b setBackgroundImage:[PTArt key:PTKeyNormal dark:dark] forState:UIControlStateNormal];
        [b setBackgroundImage:[PTArt key:PTKeyPressed dark:dark] forState:UIControlStateHighlighted];
        [b setTitleColor:dark ? [PTArt hex:PT_DK_TEXT] : [UIColor blackColor] forState:UIControlStateNormal]; /* claude.png: light key labels are black */
        [b setTitleShadowColor:dark ? [PTArt hex:0 alpha:0.8] : [PTArt hex:0xFFFFFF alpha:0.7] forState:UIControlStateNormal];
        b.titleLabel.shadowOffset = CGSizeMake(0, dark ? -1 : 1);
    }
    [self setCtrlArmed:_armed];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)r { [[PTArt keyBarBackgroundDark:[PTTheme isDarkAppearance]] drawInRect:self.bounds]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger n = self.subviews.count, groups = sizeof GROUPS / sizeof *GROUPS;
    CGFloat w = floor((self.bounds.size.width - 2 * SIDE - (groups - 1) * GAP_BETWEEN - (n - groups) * GAP_IN) / n), x = SIDE;
    NSUInteger i = 0;
    for (size_t g = 0; g < groups; g++)
        for (int k = 0; k < GROUPS[g]; k++, i++) {
            UIView *v = self.subviews[i];
            v.frame = CGRectMake(x, KEY_Y, w, KEY_H);
            x += w + (k + 1 < GROUPS[g] ? GAP_IN : GAP_BETWEEN);
        }
    _dot.frame = CGRectMake(_ctrl.bounds.size.width - DOT - 5, 5, DOT, DOT);
}

- (BOOL)enableInputClicksWhenVisible { return YES; }

- (void)setCtrlArmed:(BOOL)armed {
    _armed = armed;
    BOOL dark = [PTTheme isDarkAppearance];
    [_ctrl setBackgroundImage:[PTArt key:armed ? PTKeyArmed : PTKeyNormal dark:dark] forState:UIControlStateNormal];
    UIColor *label = armed ? [UIColor whiteColor] : dark ? [PTArt hex:PT_DK_TEXT] : [UIColor blackColor];
    [_ctrl setTitleColor:label forState:UIControlStateNormal];
    [_ctrl setTitleShadowColor:armed || dark ? [PTArt hex:0 alpha:0.6] : [PTArt hex:0xFFFFFF alpha:0.7] forState:UIControlStateNormal];
    _dot.hidden = !armed;
}

- (void)press:(UIButton *)b {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:PTKeyClickKey]) [[UIDevice currentDevice] playInputClick];
    if (b.tag == PT_KEY_CTRL_TAG) { [self setCtrlArmed:!_armed]; [self.delegate keyBarCtrlChanged:_armed]; return; }
    if (b.tag == PT_KEY_HIDE_TAG) { [self.delegate keyBarHideKeyboard]; return; }
    [self.delegate keyBarKey:(pt_key)b.tag];
}
@end
