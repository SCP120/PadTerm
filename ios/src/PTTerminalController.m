#import "PTTerminalController.h"
#import <objc/runtime.h>
#import "PTArt.h"
#import "PTKeyBar.h"
#import "PTSettings.h"
#import "PTTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "PTProfileStore.h"
#import "PTSessionListController.h"
#import "PTSplitController.h"
#import "PTTerminalView.h"
#include "pt_backoff.h"
#include "pt_conn.h"
#include "pt_error.h"
#include "pt_keys.h"
#include "pt_render.h"
#include "pt_session.h"
#include "pt_term.h"
#ifdef PT_SELFTEST
#include "pt_metrics.h"
#endif

/* Connect timeout: covers TCP + SSH handshake on a slow mobile link; libssh2's own examples and OpenSSH's
 * ConnectTimeout guidance use tens of seconds, 15 s keeps the UI responsive (user can cancel any time). */
enum { PT_CONNECT_TIMEOUT_MS = 15000 };
/* AC-RECONNECT-1: keep-alive interval. */
enum { PT_KEEPALIVE_S = 30 };
/* Redraw at most 30 times a second, and only after a change: a timer that runs when nothing changes keeps
 * the CPU awake and costs battery. 33 ms = 1/30 s. */
enum { PT_REDRAW_DELAY_MS = 33 };

/* 6 pt of dark leather frame around the terminal on the left, right and bottom. */
enum { BEZEL = 6 };

typedef enum { PTStateConnecting, PTStateConnected, PTStateReconnecting, PTStateStopped } PTConnState;

@interface PTTerminalController () <UIPopoverControllerDelegate, PTTerminalViewDelegate, PTKeyBarDelegate, UIAlertViewDelegate, PTSettingsDelegate>
- (void)connEvent:(pt_conn_event)ev status:(int)status data:(NSData *)data generation:(NSUInteger)gen;
@end

/* Bridge object passed to the IO thread; keeps a weak link to the controller. */
@interface PTConnBridge : NSObject
@property (nonatomic, weak) PTTerminalController *controller;
@property (nonatomic, assign) NSUInteger generation;
/* Host-key answer: the IO thread waits on sem; the alert or closeConnection signals it. */
@property (nonatomic, strong) dispatch_semaphore_t sem;
@property (atomic, assign) BOOL accepted;
@end
@interface PTTerminalController ()
- (void)showHostKey:(NSString *)fingerprint bridge:(PTConnBridge *)bridge;
@end
@implementation PTConnBridge
@end

static int conn_event(pt_conn_event ev, int status, const char *data, size_t len, void *user) {
    /* The IO thread is a plain pthread: iOS 6 makes no autorelease pool for it, so without this every
     * autoreleased object (the NSData of each read) would leak. */
    @autoreleasepool {
        PTConnBridge *b = (__bridge PTConnBridge *)user;
        PTTerminalController *c = b.controller;
        NSUInteger gen = b.generation;
        if (ev == PT_CONN_EV_HOSTKEY) { /* BR-CONNECT-1: the IO thread waits for the user's answer */
            NSString *fp = [[NSString alloc] initWithBytes:data length:len encoding:NSUTF8StringEncoding];
            dispatch_async(dispatch_get_main_queue(), ^{ [c showHostKey:fp bridge:b]; });
            dispatch_semaphore_wait(b.sem, DISPATCH_TIME_FOREVER);
            return b.accepted;
        }
        NSData *d = data ? [NSData dataWithBytes:data length:len] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ [c connEvent:ev status:status data:d generation:gen]; });
        return 0;
    }
}

static void term_output(const char *bytes, size_t len, void *user) {
    pt_conn *conn = *(pt_conn **)user;
    if (conn) pt_conn_write(conn, bytes, len);
}

/* The two-line title of Apple's own bars (Music's now-playing title): the name, then the state with its LED, both centred. */
@interface PTTitleView : UIView
@property (nonatomic, strong) UIImageView *led;
@property (nonatomic, strong) UILabel *name, *state;
@end
@implementation PTTitleView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, textW = MIN(w - 16, ceil([_state.text sizeWithFont:_state.font].width));
    CGFloat x = floor((w - 14 - textW) / 2);
    _name.frame = CGRectMake(0, 2, w, 19);
    _led.frame = CGRectMake(x - 6, 16, 24, 24); /* the 10 pt disc is centred in its 24 pt image, level with the state line */
    _state.frame = CGRectMake(x + 14, 21, textW + 2, 15);
}
@end

@implementation PTTerminalController {
    PTProfile *_profile;
    pt_agent _agent;
    PTTerminalView *_view;
    PTKeyBar *_keyBar;
    UIView *_overlay;                /* dims a frozen terminal; shown only while not connected */
    UILabel *_overlayText;
    UIImageView *_hud;
    UIActivityIndicatorView *_spinner;
    UIImageView *_led;
    UILabel *_titleName, *_titleState;
    UIBarButtonItem *_sessionsItem;
    PTSession *_session; /* nil for the Shell */
    UIBarButtonItem *_gearItem;
    UIPopoverController *_popover;
    PTConnState _state;
    NSString *_stateText;
    BOOL _gotData;                   /* first output byte seen: the connect HUD goes away */
    NSInteger _fontSize;
    pt_term *_term;
    pt_render *_render;
    pt_conn *_conn;
    void *_bridge;            /* CFBridgingRetain'd PTConnBridge of _conn */
    NSUInteger _generation;   /* events of an older connection are ignored */
    pt_backoff _backoff;
    NSTimer *_retry;
    BOOL _connected, _userClosed, _dirty, _redrawPending;
    uint8_t _bg[3];
    CGFloat _keyboardHeight;
#ifdef PT_SELFTEST
    UIAlertView *_testAlert;
#endif
}

- (instancetype)initWithProfile:(PTProfile *)profile agent:(pt_agent)agent {
    if ((self = [super init])) {
        _profile = profile;
        _agent = agent;
        pt_backoff_reset(&_backoff);
    }
    return self;
}

- (instancetype)initWithProfile:(PTProfile *)profile session:(PTSession *)session {
    if ((self = [self initWithProfile:profile agent:session.agent])) _session = session;
    return self;
}

- (void)dealloc {
    [self closeConnection];
    [_retry invalidate];
    pt_term_free(_term);
    pt_render_free(_render);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* ---------------- view ---------------- */

- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    root.backgroundColor = [PTTheme current].bgColor; /* the 6 pt margin around the terminal view is the theme's own colour */
    _view = [[PTTerminalView alloc] initWithFrame:root.bounds];
    _view.delegate = self;
    __weak PTTerminalController *weakSelf = self;
    _view.ctrlConsumed = ^{ [weakSelf keyBarSetCtrl:NO]; };
    [root addSubview:_view];
    _overlay = [[UIView alloc] init];
    _overlay.backgroundColor = [PTArt hex:0 alpha:0.35];
    _overlay.userInteractionEnabled = NO;
    _overlay.hidden = YES;
    _overlayText = [[UILabel alloc] init];
    _overlayText.backgroundColor = [UIColor clearColor];
    _overlayText.textColor = [UIColor whiteColor];
    _overlayText.font = [PTArt bold:17];
    _overlayText.textAlignment = NSTextAlignmentCenter;
    _overlayText.numberOfLines = 0;
    [_overlay addSubview:_overlayText];
    [root addSubview:_overlay];
    _hud = [[UIImageView alloc] initWithImage:[PTArt hud]];
    _hud.frame = CGRectMake(0, 0, 160, 160);
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.center = CGPointMake(80, 60);
    UILabel *hudText = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, 160, 20)];
    hudText.text = @"Connecting\xE2\x80\xA6";
    hudText.font = [PTArt bold:15];
    hudText.textColor = [UIColor whiteColor];
    hudText.backgroundColor = [UIColor clearColor];
    hudText.textAlignment = NSTextAlignmentCenter;
    [_hud addSubview:_spinner];
    [_hud addSubview:hudText];
    _hud.hidden = YES;
    [root addSubview:_hud];
    _keyBar = [[PTKeyBar alloc] initWithFrame:CGRectMake(0, 0, root.bounds.size.width, 50)];
    _keyBar.delegate = self;
    self.view = root;
}

- (UIView *)inputAccessoryView { return _keyBar; }

/* The bar itself is stock (PTNavigationController); this sets the colours of the two title lines to match it. */
- (void)styleTitle {
    BOOL dark = [PTTheme isDarkAppearance];
    _titleName.textColor = [PTArt hex:dark ? PT_DK_TEXT : PT_SLATE_HEAD];
    _titleState.textColor = [PTArt hex:dark ? PT_DK_TEXT2 : 0x636B7C]; /* not measured: PT_SLATE_HEAD lightened, still 4:1 on the bar */
    for (UILabel *l in @[_titleName, _titleState]) {
        l.shadowColor = dark ? [PTArt hex:0 alpha:0.8] : [PTArt hex:0xFFFFFF alpha:0.8];
        l.shadowOffset = CGSizeMake(0, dark ? -1 : 1);
    }
}

/* Servers, the two-line title, Sessions and the gear: stock bar buttons. */
- (void)buildNavigationItems {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Servers" style:UIBarButtonItemStyleBordered
                                                                             target:self action:@selector(goBack)];
    PTTitleView *title = [[PTTitleView alloc] initWithFrame:CGRectMake(0, 0, 420, 40)];
    _led = title.led = [[UIImageView alloc] init];
    _titleName = title.name = [[UILabel alloc] init];
    _titleState = title.state = [[UILabel alloc] init];
    for (UILabel *l in @[_titleName, _titleState]) {
        l.backgroundColor = [UIColor clearColor];
        l.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    _titleName.textAlignment = NSTextAlignmentCenter;
    _titleName.font = [PTArt bold:15];
    _titleName.text = _session ? _session.displayTitle : @"Shell";
    _titleState.font = [PTArt regular:11];
    for (UIView *v in @[_led, _titleName, _titleState]) [title addSubview:v];
    [self styleTitle];
    self.navigationItem.titleView = title;
    _sessionsItem = [[UIBarButtonItem alloc] initWithTitle:@"Sessions" style:UIBarButtonItemStyleBordered target:self action:@selector(showSessions:)];
    _gearItem = [[UIBarButtonItem alloc] initWithImage:[PTArt gear] style:UIBarButtonItemStyleBordered target:self action:@selector(showSettings)];
    _gearItem.width = 44; /* touch target */
    self.navigationItem.rightBarButtonItems = @[_gearItem, _sessionsItem];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:NSSelectorFromString(@"setEdgesForExtendedLayout:")]) /* iOS 7: row 0 stays below the bar */
        [self setValue:@0 forKey:@"edgesForExtendedLayout"];
    [self buildNavigationItems];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(appearanceChanged) name:PTAppearanceDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(foreground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [self loadRenderer];
    [self applyTheme];
    [self setState:PTStateConnecting text:@"connecting\xE2\x80\xA6"];
    int rows, cols;
    [_view gridRows:&rows cols:&cols];
    _term = pt_term_new(rows, cols, term_output, &_conn);
    [self applyTheme];
    _view.term = _term;
    [self scheduleRedraw];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _userClosed = NO;
    [UIApplication sharedApplication].idleTimerDisabled = [[NSUserDefaults standardUserDefaults] boolForKey:PTKeepAwakeKey];
    if (!_conn) [self connect];
    [_view becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) [self endSession];
}

- (void)endSession {
    _userClosed = YES;
    [_retry invalidate];
    [_popover dismissPopoverAnimated:NO];
    _popover = nil;
    [self closeConnection];
#ifndef PT_SELFTEST
    [UIApplication sharedApplication].idleTimerDisabled = NO; /* the test build keeps the iPad awake for the whole run */
#endif
}

- (void)goBack {
    [self endSession];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

/* Frames are whole points: the grid is pixel-exact only when the view origin and size are integral. */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat bottomInset = 0;
    /* The home indicator on newer iPads (iOS 11). KVC: this one source also builds with the iOS 9.3 SDK. */
    if ([self.view respondsToSelector:NSSelectorFromString(@"safeAreaInsets")])
        bottomInset = [[self.view valueForKey:@"safeAreaInsets"] UIEdgeInsetsValue].bottom;
    b.size.height -= MAX(_keyboardHeight, bottomInset);
    CGRect t = CGRectMake(BEZEL, 0, b.size.width - 2 * BEZEL, b.size.height - BEZEL);
    _view.frame = t;
    _overlay.frame = t;
    _overlayText.frame = CGRectMake(40, 0, t.size.width - 80, t.size.height);
    _hud.center = CGPointMake(floor(CGRectGetMidX(t)), floor(CGRectGetMidY(t)));
    [self syncSize];
}

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)o duration:(NSTimeInterval)d {
    [_popover dismissPopoverAnimated:NO];
    _popover = nil;
}

/* Release the list now: it keeps an SSH connection and reads every 15 s while it lives. */
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)p { if (p == _popover) _popover = nil; }

- (void)keyboardChanged:(NSNotification *)n {
    CGRect kb = [self.view convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    /* A floating or split keyboard (iPad, later iOS) does not touch the bottom edge: it takes no terminal rows. */
    BOOL docked = CGRectGetMaxY(kb) >= CGRectGetMaxY(self.view.bounds) - 1;
    _keyboardHeight = [n.name isEqualToString:UIKeyboardWillHideNotification] || !docked ? 0
                    : MAX(0, CGRectGetMaxY(self.view.bounds) - kb.origin.y);
    [self.view setNeedsLayout];
}

/* AC-SCREEN-7: new size to the terminal and the server. */
- (void)syncSize {
    if (!_term || !_render) return;
    int rows, cols, r0, c0;
    [_view gridRows:&rows cols:&cols];
    pt_term_size(_term, &r0, &c0);
    if (rows == r0 && cols == c0) return;
    pt_term_resize(_term, rows, cols);
    if (_conn) pt_conn_resize(_conn, cols, rows);
    _dirty = YES;
    [self scheduleRedraw];
}

- (void)loadRenderer {
    NSInteger size = [[NSUserDefaults standardUserDefaults] integerForKey:PTFontKey] ?: PT_FONT_DEFAULT;
    size = MAX(PT_FONT_MIN, MIN(PT_FONT_MAX, size));
    NSData *reg = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"DejaVuSansMono" ofType:@"ttf"]];
    NSData *bold = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"DejaVuSansMono-Bold" ofType:@"ttf"]];
    pt_render *r = pt_render_new(reg.bytes, reg.length, bold.bytes, bold.length, size);
    if (!r) { NSLog(@"PadTerm: bundled fonts missing"); abort(); } /* a build without the fonts must fail at once */
    pt_render_free(_render);
    _render = r;
    pt_render_prewarm_font_search(r);
    _fontSize = size;
    _view.render = r;
}

- (void)adjustFont:(NSInteger)delta {
    NSInteger size = [[NSUserDefaults standardUserDefaults] integerForKey:PTFontKey] ?: PT_FONT_DEFAULT;
    [[NSUserDefaults standardUserDefaults] setInteger:MAX(PT_FONT_MIN, MIN(PT_FONT_MAX, size + delta)) forKey:PTFontKey];
    [self settingsChanged];
}
- (void)fontUp { [self adjustFont:1]; }
- (void)fontDown { [self adjustFont:-1]; }

/* Font, theme and keep-awake are re-read from NSUserDefaults; key click is read by the key bar. */
- (void)settingsChanged {
    NSInteger size = [[NSUserDefaults standardUserDefaults] integerForKey:PTFontKey] ?: PT_FONT_DEFAULT;
    if (size != _fontSize) {
        [self loadRenderer];
        [self syncSize];
        _dirty = YES;
        [self scheduleRedraw];
    }
    [self applyTheme];
    [UIApplication sharedApplication].idleTimerDisabled = [[NSUserDefaults standardUserDefaults] boolForKey:PTKeepAwakeKey];
}

- (void)applyTheme {
    PTTheme *t = [PTTheme current];
    memcpy(_bg, t.bg, 3);
    _view.themeBackground = _bg;
    if ([self isViewLoaded]) self.view.backgroundColor = t.bgColor;
    if (_term) pt_term_set_colors(_term, t.fg, t.bg, NULL);
    _dirty = YES;
    if (_view) [self scheduleRedraw];
}

- (void)showSettings {
    if (_popover.popoverVisible) { [_popover dismissPopoverAnimated:NO]; _popover = nil; return; }
    PTSettingsController *sc = [[PTSettingsController alloc] init];
    sc.delegate = self;
    _popover = [[UIPopoverController alloc] initWithContentViewController:sc];
    _popover.popoverBackgroundViewClass = [PTTheme popoverBackgroundClass];
    _popover.popoverContentSize = CGSizeMake(320, 420); /* five groups: 4 rows of 44 pt, one swatch row of 76 pt, the gaps and one header */
    [_popover presentPopoverFromBarButtonItem:_gearItem permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

/* Colours, bar, keyboard and the terminal theme that goes with the appearance. UIKit restyles nothing that is already
 * open, so each piece is told here; the connection stays as it is. */
- (void)appearanceChanged {
    [self styleTitle];
    [self applyTheme];
    [_view reloadInputViews]; /* the keyboard reads its appearance again */
    if (_popover.popoverVisible && [_popover.contentViewController isKindOfClass:[PTSettingsController class]]) {
        [_popover dismissPopoverAnimated:NO]; /* the popover's glass is fixed when it is shown */
        dispatch_async(dispatch_get_main_queue(), ^{ [self showSettings]; });
    }
}

/* AC-SESSION-4: the agent shows its session name in the terminal title, and a spinner frame changes it often. */
- (void)takeTerminalTitle {
    const char *raw = _session ? pt_term_take_title(_term) : NULL;
    char name[256];
    if (!raw || !pt_session_clean_title(_session.agent, raw, name, sizeof name)) return;
    NSString *t = [NSString stringWithUTF8String:name];
    if (!t || [t isEqualToString:_session.title]) return;
    _session.title = t;
    _titleName.text = t;
}

/* AC-SESSION-6: the rows of the server page; a tap changes to that session (tmux keeps this one running). */
- (void)showSessions:(id)sender {
    if (_popover.popoverVisible) { [_popover dismissPopoverAnimated:NO]; _popover = nil; return; }
    PTSessionListController *list = [[PTSessionListController alloc] initWithProfile:_profile];
    list.currentKey = _session.key;
    __weak PTTerminalController *weakSelf = self;
    list.selected = ^(PTSession *s) { [weakSelf changeToSession:s]; };
    _popover = [[UIPopoverController alloc] initWithContentViewController:list];
    _popover.delegate = self;
    _popover.popoverBackgroundViewClass = [PTTheme popoverBackgroundClass];
    _popover.popoverContentSize = CGSizeMake(460, 520);
    [_popover presentPopoverFromBarButtonItem:_sessionsItem permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

- (void)changeToSession:(PTSession *)session {
    [_popover dismissPopoverAnimated:NO];
    _popover = nil;
    if ([session.key isEqualToString:_session.key]) return;
    [(PTSplitController *)self.navigationController.presentingViewController openTerminalForProfile:_profile session:session];
}

/* LED, second title line, dim overlay and connect HUD all follow the one state (design 4.7). */
- (void)setState:(PTConnState)state text:(NSString *)text {
    _state = state;
    _stateText = text;
    _titleState.text = text;
    [self.navigationItem.titleView setNeedsLayout]; /* the LED sits beside the state text */
    _led.image = [PTArt led:state == PTStateConnected ? PTLedGreen : state == PTStateStopped ? PTLedRed : PTLedAmber];
    [_led.layer removeAllAnimations];
    _led.alpha = 1;
    if (state == PTStateConnecting || state == PTStateReconnecting) { /* the only animation, and only while the link is down */
        [UIView animateWithDuration:0.8 delay:0 options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ _led.alpha = 0.35; } completion:nil];
    }
    _overlay.hidden = state == PTStateConnecting || state == PTStateConnected;
    _overlayText.text = state == PTStateStopped ? text : nil;
    BOOL hud = state == PTStateConnecting && !_gotData;
    _hud.hidden = !hud;
    if (hud) [_spinner startAnimating]; else [_spinner stopAnimating];
}

- (void)scheduleRedraw {
    if (_redrawPending) return;
    _redrawPending = YES;
    __weak PTTerminalController *weakSelf = self; /* a closed screen must not stay alive for one frame */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, PT_REDRAW_DELAY_MS * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [weakSelf redrawNow];
    });
}

- (void)redrawNow {
    _redrawPending = NO;
    int top, bottom;
    if (_dirty) { /* theme, font or size change: everything */
        _dirty = NO;
        if (_term) pt_term_take_damage(_term, NULL, NULL);
        [_view setNeedsDisplay];
    } else if (_term && pt_term_take_damage(_term, &top, &bottom)) {
        double w, h;
        pt_render_cell_size(_render, &w, &h);
        [_view setNeedsDisplayInRect:CGRectMake(0, top * h, _view.bounds.size.width, (bottom - top) * h)];
    }
}

/* ---------------- connection ---------------- */

- (void)connect {
    NSData *key = [[PTProfileStore shared] keyForProfile:_profile];
    if (!key) { [self setState:PTStateStopped text:@"No private key in this profile. Edit the profile and add one."]; return; }
#ifdef PT_SELFTEST
    ptm_connect();
#endif
    char cmd[16384];
    int built = _session ? pt_session_launch_command(_session.agent, _session.key.UTF8String, _profile.directory.UTF8String, cmd, sizeof cmd)
                         : pt_launch_command(_agent, _profile.directory.UTF8String, cmd, sizeof cmd);
    if (built < 0) {
        [self setState:PTStateStopped text:@"The directory in this profile is not valid."];
        return;
    }
    int rows, cols;
    pt_term_size(_term, &rows, &cols);
    PTConnBridge *b = [[PTConnBridge alloc] init];
    b.controller = self;
    b.generation = ++_generation;
    b.sem = dispatch_semaphore_create(0);
    pt_conn_params p = {
        .host = _profile.host.UTF8String, .port = (int)_profile.port, .user = _profile.user.UTF8String,
        .private_key = key.bytes, .private_key_len = key.length,
        .pinned_fingerprint = _profile.pinnedFingerprint.UTF8String, .command = cmd,
        .cols = cols, .rows = rows, .connect_timeout_ms = PT_CONNECT_TIMEOUT_MS, .keepalive_s = PT_KEEPALIVE_S};
    _bridge = (void *)CFBridgingRetain(b);
    if (_state == PTStateReconnecting) [self setState:PTStateReconnecting text:@"reconnecting\xE2\x80\xA6"];
    else [self setState:PTStateConnecting text:@"connecting\xE2\x80\xA6"];
    if (pt_conn_start(&p, conn_event, _bridge, &_conn) != PT_OK) {
        CFBridgingRelease(_bridge);
        _bridge = NULL;
        [self setState:PTStateStopped text:@"Could not start the connection."];
    }
}

- (void)closeConnection {
    if (_bridge) { /* free an IO thread that waits for a host-key answer, before the join */
        PTConnBridge *b = (__bridge PTConnBridge *)_bridge;
        b.accepted = NO;
        dispatch_semaphore_signal(b.sem);
    }
    if (_conn) {
        pt_conn *c = _conn;
        _conn = NULL; /* term_output stops writing first */
        pt_conn_close(c); /* joins the IO thread; its last events are ignored by generation */
    }
    if (_bridge) { CFBridgingRelease(_bridge); _bridge = NULL; }
    _generation++;
    _connected = NO;
}

- (void)connEvent:(pt_conn_event)ev status:(int)status data:(NSData *)data generation:(NSUInteger)gen {
    if (gen != _generation) return;
    switch (ev) {
    case PT_CONN_EV_CONNECTED:
        _connected = YES;
        pt_backoff_reset(&_backoff);
        [self setState:PTStateConnected text:[NSString stringWithFormat:@"%@ \xC2\xB7 %s \xC2\xB7 connected", _profile.name, pt_agent_session(_agent)]];
        break;
    case PT_CONN_EV_DATA:
        if (!_gotData) { _gotData = YES; [self setState:_state text:_stateText]; }
#ifdef PT_SELFTEST
        { double t0 = ptm_now_ms(); pt_term_feed(_term, data.bytes, data.length); ptm_data(data.length, ptm_now_ms() - t0); }
#else
        pt_term_feed(_term, data.bytes, data.length);
#endif
        if (_conn) pt_conn_ack(_conn, data.length); /* backpressure: the IO thread reads on */
        [self takeTerminalTitle];
        [self scheduleRedraw];
        break;
    case PT_CONN_EV_CLOSED:
        [self connectionClosed:status];
        break;
    case PT_CONN_EV_HOSTKEY:
        break;
    }
}

- (void)connectionClosed:(int)status {
    pt_conn *c = _conn;
    _conn = NULL;
    _connected = NO;
    if (c) pt_conn_close(c); /* thread already ended; this joins and frees */
    if (_bridge) { CFBridgingRelease(_bridge); _bridge = NULL; }
    if (_userClosed) return;
    NSString *why = [NSString stringWithUTF8String:pt_status_text(status)];
    if (!pt_should_reconnect(status)) { /* BR-RECONNECT-1 */
        [self setState:PTStateStopped text:status == PT_OK || status == PT_ERR_CLOSED ? @"Session ended. Go back to start it again." : why];
        return;
    }
    int ms = pt_backoff_next(&_backoff);
    [self setState:PTStateReconnecting text:[NSString stringWithFormat:@"reconnecting in %d s", ms / 1000]];
    [_retry invalidate];
    _retry = [NSTimer scheduledTimerWithTimeInterval:ms / 1000.0 target:self selector:@selector(retryNow) userInfo:nil repeats:NO];
}

- (void)retryNow { if (!_conn && !_userClosed) [self connect]; }

- (void)foreground {
    if (_state == PTStateStopped) return; /* the session ended: a wake must not start the agent again */
    if (!_conn && !_userClosed) { [_retry invalidate]; pt_backoff_reset(&_backoff); [self connect]; }
}

/* BR-CONNECT-1: show the fingerprint; the answer goes back to the waiting IO thread. */
- (void)showHostKey:(NSString *)fingerprint bridge:(PTConnBridge *)bridge {
    if (bridge.generation != _generation) { bridge.accepted = NO; dispatch_semaphore_signal(bridge.sem); return; }
    NSString *msg = [NSString stringWithFormat:@"First connection to %@.\nCompare this fingerprint with "
                     "`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the server:\n\n%@", _profile.host, fingerprint];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability" /* guarded by the class check; @available does not link on armv7 */
    if (NSClassFromString(@"UIAlertController")) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Unknown host key" message:msg preferredStyle:UIAlertControllerStyleAlert];
        __weak PTTerminalController *weakSelf = self;
        [a addAction:[UIAlertAction actionWithTitle:@"Refuse" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
            bridge.accepted = NO; dispatch_semaphore_signal(bridge.sem); }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Trust" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [weakSelf answerHostKey:YES fingerprint:fingerprint bridge:bridge]; }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
#pragma clang diagnostic pop
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Unknown host key" message:msg delegate:self
                                      cancelButtonTitle:@"Refuse" otherButtonTitles:@"Trust", nil];
    objc_setAssociatedObject(a, "fp", fingerprint, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(a, "bridge", bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#ifdef PT_SELFTEST
    _testAlert = a;
#endif
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)i {
    PTConnBridge *b = objc_getAssociatedObject(alertView, "bridge");
    if (b) [self answerHostKey:i != alertView.cancelButtonIndex fingerprint:objc_getAssociatedObject(alertView, "fp") bridge:b];
}

- (void)answerHostKey:(BOOL)trust fingerprint:(NSString *)fingerprint bridge:(PTConnBridge *)b {
    BOOL ok = trust && b.generation == _generation;
    if (ok) {
        _profile.pinnedFingerprint = fingerprint;
        [[PTProfileStore shared] saveProfile:_profile];
    }
    b.accepted = ok;
    dispatch_semaphore_signal(b.sem);
}

#ifdef PT_SELFTEST
- (pt_term *)testTerm { return _term; }
- (PTTerminalView *)testView { return _view; }
- (PTKeyBar *)testKeyBar { return _keyBar; }
- (pt_render *)testRender { return _render; }
- (NSString *)testStatus { return _stateText ?: @""; }
- (NSString *)testTitle { return _titleName.text; }
- (void)testForeground { [self foreground]; }
- (void)testShowSessions { [self showSessions:_sessionsItem]; }
- (NSString *)testPopoverSelectRow:(NSInteger)row {
    PTSessionListController *l = (PTSessionListController *)_popover.contentViewController;
    if (![l isKindOfClass:[PTSessionListController class]] || (NSUInteger)row >= l.sessions.count) return @"ERR row";
    [l testSelectRow:row];
    return @"ok";
}
- (void)testGear { [self showSettings]; }
/* nil: toggle classic / light, as the old Theme button did. */
- (void)testTheme:(NSString *)name {
    NSString *want = name.length ? name : [[PTTheme current].name isEqualToString:@"classic"] ? @"light" : @"classic";
    for (PTTheme *t in [PTTheme all]) if ([t.name isEqualToString:want]) [PTTheme select:t];
    [self settingsChanged];
}
- (BOOL)testConnected { return _connected; }
- (BOOL)testHasAlert { return _testAlert != nil; }
- (BOOL)testAnswerAlert:(BOOL)accept {
    UIAlertView *a = _testAlert;
    if (!a) return NO;
    _testAlert = nil;
    NSInteger i = accept ? a.firstOtherButtonIndex : a.cancelButtonIndex;
    [a dismissWithClickedButtonIndex:i animated:NO];
    [self alertView:a clickedButtonAtIndex:i];
    return YES;
}
#endif

/* ---------------- input ---------------- */

- (void)terminalViewDidType:(NSString *)text {
#ifdef PT_SELFTEST
    ptm_key();
#endif
    /* Every code point, so emoji with modifiers, flags and combining marks arrive whole. */
    NSData *u = [text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    const uint32_t *cp = u.bytes;
    for (NSUInteger i = 0; i < u.length / 4; i++) {
        if (cp[i] == 0xFEFF) continue; /* byte-order mark */
        pt_keys_send_char(_term, cp[i], 0); /* '\n' from the Return key becomes Enter */
    }
}

- (void)terminalViewHardwareKey:(pt_key)key { [self keyBarKey:key]; }

- (void)terminalViewDidTypeControl:(char)byte { pt_term_send_bytes(_term, &byte, 1); } /* Ctrl+J stays 0x0A */

- (void)terminalViewDidBackspace { pt_term_send_bytes(_term, "\x7f", 1); }
- (void)terminalViewTapAtRow:(int)row col:(int)col { pt_term_mouse_click(_term, row, col); }
- (void)terminalViewWheelAtRow:(int)row col:(int)col lines:(int)linesUp { pt_term_mouse_wheel(_term, row, col, linesUp); }
- (void)terminalViewPaste:(NSString *)text {
    NSData *d = [text dataUsingEncoding:NSUTF8StringEncoding];
    pt_term_paste(_term, d.bytes, d.length);
}

- (void)keyBarKey:(pt_key)key {
#ifdef PT_SELFTEST
    ptm_key();
#endif
    pt_keys_send(_term, key);
}
- (void)keyBarSetCtrl:(BOOL)armed { [_keyBar setCtrlArmed:armed]; _view.ctrlArmed = armed; }
- (void)keyBarCtrlChanged:(BOOL)armed { _view.ctrlArmed = armed; }
- (void)keyBarHideKeyboard { [_view resignFirstResponder]; }
@end
