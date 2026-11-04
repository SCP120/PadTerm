#import "PTTerminalView.h"
#import "PTTheme.h"
#ifdef PT_SELFTEST
#include "pt_metrics.h"
#endif

@implementation PTTerminalView {
    CGFloat _panRest; /* pan distance not yet sent as wheel lines */
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)]];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
        [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
    }
    return self;
}

- (void)cellW:(double *)w h:(double *)h { pt_render_cell_size(self.render, w, h); }

- (void)gridRows:(int *)rows cols:(int *)cols {
    double w, h;
    [self cellW:&w h:&h];
    *cols = MAX(1, (int)floor(self.bounds.size.width / w));
    *rows = MAX(1, (int)floor(self.bounds.size.height / h));
}

- (void)drawRect:(CGRect)rect {
#ifdef PT_SELFTEST
    double t0 = ptm_now_ms();
#endif
    CGContextRef ctx = UIGraphicsGetCurrentContext(); /* UIKit context: origin top-left, as the renderer wants */
    const uint8_t *bg = self.themeBackground;
    CGContextSetRGBFillColor(ctx, bg[0] / 255.0, bg[1] / 255.0, bg[2] / 255.0, 1);
    CGContextFillRect(ctx, rect); /* rect = the changed rows; the renderer draws only those */
    if (self.term && self.render) pt_render_draw(self.render, ctx, self.term, bg);
#ifdef PT_SELFTEST
    double drawn = ptm_now_ms() - t0;
    ptm_draw(drawn, rect.size.height);
    if (drawn > 300) { /* the 2.4 s freeze of the first Wi-Fi run: name what was on screen at that moment */
        int rows, cols;
        pt_term_size(self.term, &rows, &cols);
        NSMutableString *seen = [NSMutableString string];
        NSMutableSet *done = [NSMutableSet set];
        for (int r = 0; r < rows; r++)
            for (int k = 0; k < cols; k++) {
                pt_cell cell;
                if (pt_term_cell(self.term, r, k, &cell) != 0 || cell.chars[0] < 0x80 || [done containsObject:@(cell.chars[0])]) continue;
                [done addObject:@(cell.chars[0])];
                [seen appendFormat:@"U+%04X ", cell.chars[0]];
            }
        NSLog(@"PTSELFTEST slow draw %.0f ms, height %.0f, characters: %@", drawn, rect.size.height, seen);
    }
#endif
}

- (void)cellAt:(CGPoint)p row:(int *)row col:(int *)col {
    double w, h;
    [self cellW:&w h:&h];
    *row = (int)(p.y / h);
    *col = (int)(p.x / w);
}

- (void)tap:(UITapGestureRecognizer *)g {
    if (self.term && pt_term_mouse_mode(self.term)) {
        int r, c;
        [self cellAt:[g locationInView:self] row:&r col:&c];
        [self.delegate terminalViewTapAtRow:r col:c];
    }
    if (![self isFirstResponder]) [self becomeFirstResponder];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) _panRest = 0;
    double w, h;
    [self cellW:&w h:&h];
    _panRest += [g translationInView:self].y;
    [g setTranslation:CGPointZero inView:self];
    int lines = (int)(_panRest / h);
    if (lines) {
        _panRest -= lines * h;
        int r, c;
        [self cellAt:[g locationInView:self] row:&r col:&c];
        [self.delegate terminalViewWheelAtRow:r col:c lines:lines]; /* finger down = content down = wheel up */
    }
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self becomeFirstResponder];
    CGPoint p = [g locationInView:self];
    [[UIMenuController sharedMenuController] setTargetRect:CGRectMake(p.x, p.y, 1, 1) inView:self];
    [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action != @selector(paste:)) return NO;
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    /* iOS 10: hasStrings does not read the content, so no paste banner each time the menu is checked. */
    if ([pb respondsToSelector:NSSelectorFromString(@"hasStrings")]) return [[pb valueForKey:@"hasStrings"] boolValue];
    return pb.string.length > 0;
}

/* A hardware keyboard on iOS 7+: UIKeyInput gets no arrows, Esc or Ctrl chords. */
- (NSArray *)keyCommands {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability" /* iOS 6 never calls keyCommands */
    if (!NSClassFromString(@"UIKeyCommand")) return nil;
    static NSArray *all;
    if (!all) {
        NSMutableArray *a = [NSMutableArray array];
        for (NSString *in in @[UIKeyInputUpArrow, UIKeyInputDownArrow, UIKeyInputLeftArrow, UIKeyInputRightArrow, UIKeyInputEscape])
            [a addObject:[UIKeyCommand keyCommandWithInput:in modifierFlags:0 action:@selector(hardwareKey:)]];
        for (char c = 'a'; c <= 'z'; c++)
            [a addObject:[UIKeyCommand keyCommandWithInput:[NSString stringWithFormat:@"%c", c] modifierFlags:UIKeyModifierControl action:@selector(hardwareControl:)]];
        all = a;
    }
    return all;
}

- (void)hardwareKey:(UIKeyCommand *)cmd {
    NSString *in = cmd.input;
    pt_key k = [in isEqualToString:UIKeyInputUpArrow] ? PT_KEY_UP : [in isEqualToString:UIKeyInputDownArrow] ? PT_KEY_DOWN
             : [in isEqualToString:UIKeyInputLeftArrow] ? PT_KEY_LEFT : [in isEqualToString:UIKeyInputRightArrow] ? PT_KEY_RIGHT : PT_KEY_ESC;
    [self.delegate terminalViewHardwareKey:k];
}

- (void)hardwareControl:(UIKeyCommand *)cmd {
    [self.delegate terminalViewDidTypeControl:(char)([cmd.input characterAtIndex:0] & 0x1f)];
}
#pragma clang diagnostic pop

- (void)paste:(id)sender {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (s.length) [self.delegate terminalViewPaste:s];
}

/* ---- UIKeyInput ---- */
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)hasText { return YES; }

- (void)insertText:(NSString *)text {
    if (self.ctrlArmed && text.length == 1) {
        unichar c = [text characterAtIndex:0];
        if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
        self.ctrlArmed = NO;
        if (self.ctrlConsumed) self.ctrlConsumed();
        if ((c >= 'a' && c <= 'z') || (c >= '@' && c <= '_')) {
            [self.delegate terminalViewDidTypeControl:(char)(c & 0x1f)];
            return;
        }
    }
    [self.delegate terminalViewDidType:text];
}

- (void)deleteBackward { [self.delegate terminalViewDidBackspace]; }

- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
- (UITextSpellCheckingType)spellCheckingType { return UITextSpellCheckingTypeNo; }
- (UIKeyboardAppearance)keyboardAppearance { return [PTTheme keyboardAppearance]; } /* the dark keyboard goes with the dark key bar */
- (UIKeyboardType)keyboardType { return UIKeyboardTypeASCIICapable; }
@end
