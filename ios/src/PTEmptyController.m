#import "PTEmptyController.h"
#import "PTArt.h"
#import "PTSplitController.h"
#import "PTTheme.h"
#import <QuartzCore/QuartzCore.h>

enum { COL_W = 420 };

/* No server yet: the detail pane says what to do, as Mail does for an empty mailbox. */
@implementation PTEmptyController {
    NSArray *_stack;        /* views laid out top to bottom, each centred */
    NSArray *_naturalSizes; /* their sizes before the pane's width narrows them */
}

static UILabel *label(NSString *text, UIFont *font, UIColor *color, CGFloat width, CGFloat height) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    l.text = text;
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    return l;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PadTerm";
    [self buildContent];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(buildContent) name:PTAppearanceDidChangeNotification object:nil];
}

- (void)buildContent {
    for (UIView *v in _stack) [v removeFromSuperview];
    BOOL dark = [PTTheme isDarkAppearance];
    self.view.backgroundColor = [PTTheme surfaceColor];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[PTArt emptyIcon]];
    UILabel *title = [PTTheme emptyLabel:@"No Servers" size:26];
    title.frame = CGRectMake(0, 0, COL_W, 32);
    UIColor *head = [PTArt hex:dark ? PT_DK_HEAD : PT_SLATE_HEAD];
    UILabel *text = label(@"Add the Mac or Linux machine that runs Claude Code and Codex.", [PTArt regular:15], head, COL_W, 40);
    NSMutableArray *views = [NSMutableArray arrayWithObjects:icon, title, text, nil];
    static NSString *const steps[] = {@"Install tmux and log in to the agents", @"Make an SSH key for the iPad", @"Tap Add Server"};
    for (int i = 0; i < 3; i++) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 360, 26)];
        UILabel *n = label([NSString stringWithFormat:@"%d", i + 1], [PTArt bold:13], [UIColor whiteColor], 22, 22);
        n.frame = CGRectMake(0, 2, 22, 22);
        n.backgroundColor = [PTArt hex:PT_DOT_BLUE];
        n.layer.cornerRadius = 11; /* three static badges on an empty page */
        n.clipsToBounds = YES;     /* iOS 7.1+: a label's background ignores the radius without it */
        UILabel *t = label(steps[i], [PTArt regular:14], head, 320, 26);
        t.frame = CGRectMake(32, 0, 328, 26);
        t.textAlignment = NSTextAlignmentLeft;
        t.lineBreakMode = NSLineBreakByTruncatingTail;
        t.numberOfLines = 1;
        [row addSubview:n];
        [row addSubview:t];
        [views addObject:row];
    }
    UIButton *add;
    if (dark) { /* the stock rounded-rect button is a light one: the dark style is a single dark row */
        add = [UIButton buttonWithType:UIButtonTypeCustom];
        [add setBackgroundImage:[PTArt rowBackground:PTRowSingle] forState:UIControlStateNormal];
        [add setBackgroundImage:[PTArt selectedRow:PTRowSingle] forState:UIControlStateHighlighted];
        [add setTitleColor:[PTArt hex:PT_DK_TEXT] forState:UIControlStateNormal];
        add.titleLabel.font = [PTArt bold:17];
    } else {
        add = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        add.titleLabel.font = [PTArt bold:17];
    }
    add.frame = CGRectMake(0, 0, 220, 44);
    [add setTitle:@"Add Server" forState:UIControlStateNormal];
    [add addTarget:self action:@selector(add) forControlEvents:UIControlEventTouchUpInside];
    [views addObject:add];
    for (UIView *v in views) [self.view addSubview:v];
    _stack = views;
    NSMutableArray *sizes = [NSMutableArray array];
    for (UIView *v in views) [sizes addObject:[NSValue valueWithCGSize:v.bounds.size]];
    _naturalSizes = sizes;
    [self.view setNeedsLayout];
}

/* Space after each view: icon, title, text, three steps, then the button. */
static CGFloat gapAfter(NSUInteger i) {
    static const CGFloat gaps[] = {10, 4, 22, 6, 6, 24, 0};
    return gaps[i];
}

/* The stack is centred as a block, so portrait, landscape and any pane width give the same page. */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat total = 0;
    for (NSUInteger i = 0; i < _stack.count; i++) total += [_naturalSizes[i] CGSizeValue].height + gapAfter(i);
    CGFloat y = MAX(20, floor((self.view.bounds.size.height - total) / 2) - 30), mid = CGRectGetMidX(self.view.bounds);
    for (NSUInteger i = 0; i < _stack.count; i++) {
        CGSize n = [_naturalSizes[i] CGSizeValue];
        CGFloat w = MIN(n.width, self.view.bounds.size.width - 40);
        [(UIView *)_stack[i] setFrame:CGRectMake(floor(mid - w / 2), y, w, n.height)];
        y += n.height + gapAfter(i);
    }
}

- (void)add { [(PTSplitController *)self.splitViewController editProfile:[PTProfile newProfile] isNew:YES]; }

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end
