#import "PTSelfTest.h"
#import <QuartzCore/QuartzCore.h>
#import "PTSplitController.h"
#import "PTLaunchController.h"
#import "PTSession.h"
#import "PTTheme.h"
#import "PTProfileStore.h"
#import "PTKeyBar.h"
#import "PTTerminalController.h"
#import "PTTerminalView.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include "pt_metrics.h"
#include "pt_keys.h"
#include "pt_render.h"
#include "pt_term.h"

/* Ports on the iPad's loopback. The Mac reaches them through usbmux (iproxy). */
enum { PORT_FROM_MAC = 5022, PORT_FROM_APP = 5023, PORT_CONTROL = 5024 };

@interface PTTerminalController (SelfTest)
- (pt_term *)testTerm;
- (PTTerminalView *)testView;
- (PTKeyBar *)testKeyBar;
- (pt_render *)testRender;
- (NSString *)testStatus;
- (BOOL)testConnected;
- (BOOL)testAnswerAlert:(BOOL)accept;
- (BOOL)testHasAlert;
- (void)keyBarKey:(pt_key)key;
- (void)terminalViewDidType:(NSString *)text;
- (void)terminalViewDidTypeControl:(char)byte;
- (void)terminalViewPaste:(NSString *)text;
- (void)terminalViewWheelAtRow:(int)row col:(int)col lines:(int)linesUp;
- (void)fontUp;
- (void)fontDown;
- (NSString *)testTitle;
- (void)testShowSessions;
- (void)testForeground;
- (NSString *)testPopoverSelectRow:(NSInteger)row;
- (void)testGear;
- (void)testTheme:(NSString *)name;
@end

static PTSplitController *g_split;
static PTProfile *g_profile;

static int listen_on(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port)};
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    if (bind(fd, (struct sockaddr *)&a, sizeof a) != 0 || listen(fd, 8) != 0) { NSLog(@"PTSELFTEST listen %d failed", port); abort(); }
    return fd;
}

/* Pair one connection from the app with one from the Mac and pump bytes until either side ends. */
static void *relay_thread(void *arg) {
    int from_app = listen_on(PORT_FROM_APP), from_mac = listen_on(PORT_FROM_MAC);
    for (;;) {
        int a = accept(from_app, NULL, NULL);
        int m = accept(from_mac, NULL, NULL);
        NSLog(@"PTSELFTEST relay pair %d %d", a, m);
        int one = 1;
        setsockopt(a, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        setsockopt(m, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        setsockopt(a, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        setsockopt(m, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        static char buf[32768];
        for (;;) {
            fd_set rs; FD_ZERO(&rs); FD_SET(a, &rs); FD_SET(m, &rs);
            if (select((a > m ? a : m) + 1, &rs, NULL, NULL, NULL) < 0) break;
            int src = FD_ISSET(a, &rs) ? a : m, dst = src == a ? m : a;
            ssize_t n = read(src, buf, sizeof buf);
            if (n <= 0) break;
            ssize_t off = 0;
            while (off < n) { ssize_t w = write(dst, buf + off, (size_t)(n - off)); if (w <= 0) { off = -1; break; } off += w; }
            if (off < 0) break;
        }
        close(a); close(m);
        NSLog(@"PTSELFTEST relay pair closed");
    }
    return NULL;
}

static PTTerminalController *current(void) { return [g_split terminal]; }


/* ---- UI driver: the full UI test finds controls as a user does, by what they show ---- */

/* -windows, plus the window of each presented controller: Mac Catalyst keeps a sheet in its own window outside -windows. */
static NSArray *all_windows(void) {
    NSMutableArray *all = [[UIApplication sharedApplication].windows mutableCopy];
    for (UIViewController *vc = g_split.presentedViewController; vc; vc = vc.presentedViewController) {
        UIWindow *w = vc.view.window;
        if (w && ![all containsObject:w]) [all addObject:w];
    }
    return all;
}

static void walk(UIView *v, void (^fn)(UIView *)) {
    if (v.hidden || v.alpha < 0.01) return;
    fn(v);
    for (UIView *sub in v.subviews) walk(sub, fn);
}

static void walk_all(void (^fn)(UIView *)) {
    for (UIWindow *w in all_windows()) walk(w, fn);
}

/* Every control and text view that leaves the area its ancestors show. Scroll views may hold more than they show on
 * their scroll axis, so only the width counts inside a table; the screen itself bounds everything. */
/* Views behind a modal sheet are out of a finger's reach on purpose. */
static BOOL in_sheet(UIView *v) {
    for (; v; v = v.superview) if ([NSStringFromClass([v class]) isEqualToString:@"UIDropShadowView"]) return YES;
    return NO;
}

static NSString *layout_audit(void) {
    NSMutableString *out = [NSMutableString string];
    /* A finger must reach each control at its centre, and no label may lie over it. */
    UIWindow *mainWindow = [UIApplication sharedApplication].delegate.window;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        CGFloat alpha = 0;
        if (w != mainWindow && !w.hidden && w.backgroundColor) [w.backgroundColor getWhite:NULL alpha:&alpha];
        if (alpha > 0.01) [out appendFormat:@"%@ over the app has an opaque background\n", NSStringFromClass([w class])];
    }
    NSMutableArray *labels = [NSMutableArray array];
    walk_all(^(UIView *v) { if ([v isKindOfClass:[UILabel class]] && [(UILabel *)v text].length) [labels addObject:v]; });
    walk_all(^(UIView *v) {
        BOOL control = [v isKindOfClass:[UITextField class]] || [v isKindOfClass:[UITextView class]] || [v isKindOfClass:[UIButton class]]
                    || [v isKindOfClass:[UISegmentedControl class]] || [v isKindOfClass:[UISwitch class]] || [v isKindOfClass:[UIStepper class]];
        if (!control || !v.window || !v.userInteractionEnabled || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:[UIControl class]] && ![(UIControl *)v isEnabled]) return;
        for (UIView *a = v; a; a = a.superview)
            if ([NSStringFromClass([a class]) hasPrefix:@"UIKeyboard"] || [NSStringFromClass([a class]) hasPrefix:@"UIPeripheralHost"]) return;
        CGRect r = [v convertRect:v.bounds toView:v.window];
        CGPoint centre = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
        BOOL shown = CGRectContainsPoint(v.window.bounds, centre);
        for (UIView *a = v.superview; a && shown; a = a.superview)
            if (a.clipsToBounds || [a isKindOfClass:[UIScrollView class]])
                shown = CGRectContainsPoint(a.bounds, [v.window convertPoint:centre toView:a]);
        if (shown) {
            UIView *hit = [v.window hitTest:centre withEvent:nil];
            BOOL behind = in_sheet(hit) != in_sheet(v) || [NSStringFromClass([hit class]) isEqualToString:@"UIDimmingView"];
            if (!behind && hit != v && ![hit isDescendantOfView:v] && ![v isDescendantOfView:hit])
                [out appendFormat:@"%@ at %@ is covered by %@\n", NSStringFromClass([v class]), NSStringFromCGRect(r), NSStringFromClass([hit class])];
        }
        if (!shown || (![v isKindOfClass:[UITextField class]] && ![v isKindOfClass:[UITextView class]])) return;
        for (UILabel *l in labels) {
            if ([l isDescendantOfView:v] || l.window != v.window || in_sheet(l) != in_sheet(v)) continue;
            CGRect both = CGRectIntersection(r, [l convertRect:l.bounds toView:v.window]);
            if (!CGRectIsNull(both) && both.size.width > 4 && both.size.height > 4)
                [out appendFormat:@"label '%@' overlaps %@ at %@\n", l.text, NSStringFromClass([v class]), NSStringFromCGRect(r)];
        }
    });
    walk_all(^(UIView *v) {
        if ([NSStringFromClass([v.window class]) isEqualToString:@"UITextEffectsWindow"]) return; /* the keyboard's own shadow */
        BOOL watched = [v isKindOfClass:[UIControl class]] || [v isKindOfClass:[UILabel class]] || [v isKindOfClass:[UITextView class]]
                    || [v isKindOfClass:[UIImageView class]] || [v isKindOfClass:[UITableViewCell class]];
        if (!watched || v.bounds.size.width < 2 || v.bounds.size.height < 2) return;
        if ([NSStringFromClass([v class]) hasPrefix:@"_"]) return; /* UIKit's private parts: scroll indicators, shadows */
        BOOL scrolled = NO;
        for (UIView *a = v.superview; a; a = a.superview) {
            CGRect r = [v convertRect:v.bounds toView:a];
            BOOL isScroll = [a isKindOfClass:[UIScrollView class]];
            scrolled = scrolled || isScroll;
            CGRect box = a.bounds;
            BOOL clips = a.clipsToBounds || a.superview == nil || isScroll || [a isKindOfClass:[UITableViewCell class]];
            if (!clips) continue;
            BOOL wide = CGRectGetMinX(r) < CGRectGetMinX(box) - 1 || CGRectGetMaxX(r) > CGRectGetMaxX(box) + 1;
            BOOL tall = !scrolled && (CGRectGetMinY(r) < CGRectGetMinY(box) - 1 || CGRectGetMaxY(r) > CGRectGetMaxY(box) + 1);
            if (wide || tall) {
                NSString *text = [v respondsToSelector:@selector(text)] ? [(UILabel *)v text] : @"";
                [out appendFormat:@"%@ '%@' %@ outside %@ %@\n", NSStringFromClass([v class]), text, NSStringFromCGRect(r), NSStringFromClass([a class]), NSStringFromCGRect(box)];
                break;
            }
            if (isScroll) break; /* content off its scroll axis is out of sight, not out of place */
        }
    });
    return out;
}

/* What a user can read or press now: kind, text and frame on screen, one per line. */
static NSString *ui_list(void) {
    NSMutableString *out = [NSMutableString string];
    walk_all(^(UIView *v) {
        NSString *kind = nil, *text = nil;
        if ([v isKindOfClass:[UIButton class]]) { kind = @"button"; text = [(UIButton *)v titleForState:UIControlStateNormal]; }
        else if ([v isKindOfClass:[UISegmentedControl class]]) {
            UISegmentedControl *c = (UISegmentedControl *)v;
            NSMutableArray *a = [NSMutableArray array];
            for (NSUInteger i = 0; i < c.numberOfSegments; i++) [a addObject:[c titleForSegmentAtIndex:i] ?: @""];
            kind = @"segments"; text = [a componentsJoinedByString:@"/"];
        }
        else if ([v isKindOfClass:[UISwitch class]]) { kind = @"switch"; text = [(UISwitch *)v isOn] ? @"on" : @"off"; }
        else if ([v isKindOfClass:[UITextField class]]) { kind = @"field"; text = [(UITextField *)v text]; }
        else if ([v isKindOfClass:[UITextView class]]) { kind = @"textview"; text = @""; }
        else if ([v isKindOfClass:[UILabel class]] && [(UILabel *)v text].length) { kind = @"label"; text = [(UILabel *)v text]; }
        if (!kind) return;
        CGRect r = [v convertRect:v.bounds toView:v.window];
        [out appendFormat:@"%@|%@|%.0f %.0f %.0f %.0f\n", kind, [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "] ?: @"", r.origin.x, r.origin.y, r.size.width, r.size.height];
    });
    return out;
}

/* Press what shows this text: a button, a segment, a table row. The same action path as a finger, with no hit test. */
/* iOS 7 and later: a bar button's view is not a UIButton with a title, so it comes from the navigation item. */
static BOOL tap_bar_item(NSString *label) {
    NSMutableArray *navs = [NSMutableArray array];
    for (UIViewController *vc = g_split.presentedViewController; vc; vc = vc.presentedViewController) [navs insertObject:vc atIndex:0];
    [navs addObject:g_split.detailNav];
    for (UIViewController *n in navs) {
        if (![n isKindOfClass:[UINavigationController class]]) continue;
        UINavigationItem *it = [(UINavigationController *)n topViewController].navigationItem;
        NSMutableArray *items = [NSMutableArray arrayWithArray:it.leftBarButtonItems ?: @[]];
        [items addObjectsFromArray:it.rightBarButtonItems ?: @[]];
        for (UIBarButtonItem *b in items) {
            if (![b.title isEqualToString:label]) continue;
            [[UIApplication sharedApplication] sendAction:b.action to:b.target from:b forEvent:nil];
            return YES;
        }
        return NO; /* only the top screen can be tapped */
    }
    return NO;
}

static NSString *ui_tap(NSString *label) {
    __block UIControl *button = nil;
    __block UISegmentedControl *seg = nil;
    __block NSInteger segIndex = -1;
    __block UITableViewCell *cell = nil;
    walk_all(^(UIView *v) {
        if (!button && [v isKindOfClass:[UIButton class]] && [[(UIButton *)v titleForState:UIControlStateNormal] isEqualToString:label]) button = (UIControl *)v;
        if (!seg && [v isKindOfClass:[UISegmentedControl class]]) {
            UISegmentedControl *c = (UISegmentedControl *)v;
            for (NSUInteger i = 0; i < c.numberOfSegments; i++)
                if ([[c titleForSegmentAtIndex:i] isEqualToString:label]) { seg = c; segIndex = (NSInteger)i; }
        }
        if (!cell && [v isKindOfClass:[UITableViewCell class]] && ([[(UITableViewCell *)v textLabel].text hasPrefix:label])) cell = (UITableViewCell *)v;
    });
    if (button) { [button sendActionsForControlEvents:UIControlEventTouchUpInside]; return @"ok"; }
    if (tap_bar_item(label)) return @"ok";
    if (seg) {
        if (seg.selectedSegmentIndex == segIndex) return @"ok"; /* a finger on the selected segment sends nothing either */
        seg.selectedSegmentIndex = segIndex;
        [seg sendActionsForControlEvents:UIControlEventValueChanged];
        return @"ok";
    }
    if (cell) {
        UIView *t = cell.superview;
        while (t && ![t isKindOfClass:[UITableView class]]) t = t.superview;
        UITableView *table = (UITableView *)t;
        NSIndexPath *ip = [table indexPathForCell:cell];
        if (!ip) return @"ERR no index path";
        id<UITableViewDelegate> d = table.delegate;
        [table selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
        if ([d respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) [d tableView:table didSelectRowAtIndexPath:ip];
        return @"ok";
    }
    /* A finger scrolls first: bring each row of each table on screen, then look again. */
    NSMutableArray *tables = [NSMutableArray array];
    walk_all(^(UIView *v) { if ([v isKindOfClass:[UITableView class]]) [tables addObject:v]; });
    for (UITableView *t in tables)
        for (NSInteger sec = 0; sec < t.numberOfSections; sec++)
            for (NSInteger row = 0; row < [t numberOfRowsInSection:sec]; row++) {
                NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:sec];
                UITableViewCell *c = [t cellForRowAtIndexPath:ip];
                if (!c) {
                    [t scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionBottom animated:NO];
                    [t layoutIfNeeded];
                    c = [t cellForRowAtIndexPath:ip];
                }
                if (![c.textLabel.text hasPrefix:label]) continue;
                [t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
                if ([t.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) [t.delegate tableView:t didSelectRowAtIndexPath:ip];
                return @"ok";
            }
    return [@"ERR nothing shows " stringByAppendingString:label];
}

static UIAlertView *open_alert(void) { /* its window is in neither -windows nor the view tree of the key window on iOS 6 */
    UIAlertView *a = [PTTheme testLastAlert];
    return a.window ? a : nil; /* -visible stays NO during the show animation */
}

/* iOS 8 and later: the app shows a UIAlertController, somewhere in the presented chain. */
static UIViewController *open_alert_controller(void) {
    Class cls = NSClassFromString(@"UIAlertController");
    for (UIViewController *vc = g_split.presentedViewController; cls && vc; vc = vc.presentedViewController)
        if ([vc isKindOfClass:cls]) return vc;
    return nil;
}

static NSString *screen_dump(PTTerminalController *c) {
    pt_term *t = [c testTerm];
    if (!t) return @"";
    NSMutableString *s = [NSMutableString string];
    int rows, cols; pt_term_size(t, &rows, &cols);
    char row[4096];
    for (int r = 0; r < rows; r++) {
        if (pt_term_row_text(t, r, row, sizeof row) < 0) continue;
        [s appendString:[NSString stringWithUTF8String:row] ?: @""]; [s appendString:@"\n"];
    }
    return s;
}

/* A5 measurement: full redraw of the visible grid into a bitmap, ms per frame. */
static double perf_ms(PTTerminalController *c, int frames) {
    pt_term *t = [c testTerm];
    pt_render *r = [c testRender];
    double cw, ch; pt_render_cell_size(r, &cw, &ch);
    int rows, cols; pt_term_size(t, &rows, &cols);
    int W = (int)(cols * cw), H = (int)(rows * ch);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(ctx, 0, H); CGContextScaleCTM(ctx, 1, -1);
    static const uint8_t bg[3] = {24, 24, 27};
    pt_render_draw(r, ctx, t, bg);
    struct timeval a, b; gettimeofday(&a, NULL);
    for (int i = 0; i < frames; i++) pt_render_draw(r, ctx, t, bg);
    gettimeofday(&b, NULL);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    return ((b.tv_sec - a.tv_sec) * 1000.0 + (b.tv_usec - a.tv_usec) / 1000.0) / frames;
}

static NSString *handle(NSString *line) {
    NSArray *p = [line componentsSeparatedByString:@" "];
    NSString *cmd = p[0];
    NSString *rest = p.count > 1 ? [line substringFromIndex:cmd.length + 1] : @"";
    PTTerminalController *c = current();
    if ([cmd isEqualToString:@"ping"]) return @"pong";
    if ([cmd isEqualToString:@"profile"]) { /* profile <user> <dir> <pin|-> <hex key> */
        NSString *hex = p[4];
        NSMutableData *key = [NSMutableData dataWithCapacity:hex.length / 2];
        for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
            unsigned v = 0;
            sscanf([hex substringWithRange:NSMakeRange(i, 2)].UTF8String, "%2x", &v);
            uint8_t b = (uint8_t)v;
            [key appendBytes:&b length:1];
        }
        PTProfile *pr = g_profile ?: [PTProfile newProfile];
        /* optional: profile ... <host> <port> for a real network path; default = the USB relay */
        pr.name = p.count > 6 ? @"wifi-server" : @"mac-usb";
        pr.host = p.count > 6 ? p[5] : @"127.0.0.1";
        pr.port = p.count > 6 ? [p[6] integerValue] : PORT_FROM_APP;
        pr.user = p[1]; pr.directory = p[2];
        pr.pinnedFingerprint = [p[3] isEqualToString:@"-"] ? @"" : p[3];
        g_profile = pr;
        NSString *err = [[PTProfileStore shared] setKey:key forProfile:pr];
        if (err) return err;
        [[PTProfileStore shared] saveProfile:pr];
        return @"ok";
    }
    if ([cmd isEqualToString:@"open"]) {
        pt_agent a = [rest isEqualToString:@"claude"] ? PT_AGENT_CLAUDE : [rest isEqualToString:@"codex"] ? PT_AGENT_CODEX : PT_AGENT_SHELL;
        [g_split openTerminalForProfile:g_profile agent:a];
        return @"ok";
    }
    if ([cmd isEqualToString:@"state"]) { /* app state and what is presented, for a screen that did not open */
        NSMutableString *m = [NSMutableString stringWithFormat:@"appstate=%ld split.window=%@ presented=%@ windows=", (long)[UIApplication sharedApplication].applicationState, g_split.view.window ? @"yes" : @"no", NSStringFromClass([g_split.presentedViewController class])];
        for (UIWindow *w in [UIApplication sharedApplication].windows) [m appendFormat:@"%@(%d %.0fx%.0f) ", NSStringFromClass([w class]), !w.hidden, w.bounds.size.width, w.bounds.size.height];
        return m;
    }
    if ([cmd isEqualToString:@"screen"]) { /* the home and form screens: must open with no crash */
        [g_split dismissModals];
        if ([rest isEqualToString:@"list"]) [g_split showProfile:g_profile];
        if ([rest isEqualToString:@"new"]) [g_split editProfile:[PTProfile newProfile] isNew:YES];
        if ([rest isEqualToString:@"edit"]) [g_split editProfile:g_profile isNew:NO];
        if ([rest isEqualToString:@"launch"]) [g_split showProfile:g_profile];
        if ([rest isEqualToString:@"empty"]) [g_split showProfile:nil];
        return @"ok";
    }
    if ([cmd isEqualToString:@"docs"]) { /* where the app looks for imports, and what it sees there */
        NSString *d = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        NSError *e = nil;
        NSArray *a = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:d error:&e];
        return [NSString stringWithFormat:@"home=%@ docs=%@ files=%@ err=%@", NSHomeDirectory(), d, a, e];
    }
    if ([cmd isEqualToString:@"import"]) { /* import <name>: the same store calls as the Import row and Save */
        NSData *k = [[PTProfileStore shared] importableKeyForName:rest];
        if (!k) return @"ERR no file";
        NSString *err = [[PTProfileStore shared] setKey:k forProfile:g_profile];
        if (err) return err;
        [[PTProfileStore shared] removeImportableKeyForName:rest];
        return [[PTProfileStore shared] importableKeyForName:rest] ? @"ERR file still there" : @"ok";
    }
    if ([cmd isEqualToString:@"sessions"] || [cmd isEqualToString:@"session"] || [cmd isEqualToString:@"sessionrm"]) {
        UIViewController *top = g_split.detailNav.topViewController;
        if (![top isKindOfClass:[PTLaunchController class]]) return @"ERR no server page";
        PTSessionListController *l = [(PTLaunchController *)top sessionList];
        if ([cmd isEqualToString:@"sessions"]) { /* one row per line: key, agent, running, age, directory, name */
            NSMutableString *o = [NSMutableString string];
            for (PTSession *s in l.sessions)
                [o appendFormat:@"%@|%@|%d|%@|%@|%@\n", s.key, s.agentName, s.running, [PTSession ageOfDate:s.lastActive now:[NSDate date]], s.directory, s.displayTitle];
            if (l.footerMessage) [o appendFormat:@"footer: %@\n", l.footerMessage];
            return o;
        }
        if ((NSUInteger)rest.integerValue >= l.sessions.count) return @"ERR row";
        if ([cmd isEqualToString:@"sessionrm"]) { [l testSwipeDeleteRow:rest.integerValue]; return @"ok"; }
        [l testSelectRow:rest.integerValue]; /* the real tap path */
        return @"ok";
    }
    if ([cmd isEqualToString:@"stats"]) return [NSString stringWithUTF8String:ptm_report()];
    if ([cmd isEqualToString:@"launch"]) { /* the real path: the chooser plate in the detail pane */
        [g_split dismissModals];
        [g_split showProfile:g_profile];
        pt_agent a = [rest isEqualToString:@"claude"] ? PT_AGENT_CLAUDE : [rest isEqualToString:@"codex"] ? PT_AGENT_CODEX : PT_AGENT_SHELL;
        [(PTLaunchController *)g_split.detailNav.topViewController startAgent:a];
        return @"ok";
    }
    if ([cmd isEqualToString:@"snapshot"]) { /* the app's own windows as PNG hex: a SpringBoard alert cannot cover them */
        CGSize size = [UIScreen mainScreen].bounds.size;
        UIGraphicsBeginImageContextWithOptions(size, YES, 1);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        for (UIWindow *w in all_windows()) {
            if (w.hidden) continue;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, w.center.x, w.center.y);
            CGContextConcatCTM(ctx, w.transform);
            CGContextTranslateCTM(ctx, -w.bounds.size.width * w.layer.anchorPoint.x, -w.bounds.size.height * w.layer.anchorPoint.y);
            if ([w respondsToSelector:NSSelectorFromString(@"drawViewHierarchyInRect:afterScreenUpdates:")]) { /* iOS 7: blur and vibrancy too */
                if (![NSStringFromClass([w class]) hasPrefix:@"UITextEffects"] && ![NSStringFromClass([w class]) hasPrefix:@"UIRemoteKeyboard"]) /* these draw as opaque black here */
                    [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:YES];
            } else [w.layer renderInContext:ctx];
            CGContextRestoreGState(ctx);
        }
        NSData *png = UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext());
        UIGraphicsEndImageContext();
        NSMutableString *hex = [NSMutableString stringWithCapacity:png.length * 2];
        const unsigned char *b = png.bytes;
        for (NSUInteger i = 0; i < png.length; i++) [hex appendFormat:@"%02x", b[i]];
        return hex;
    }
    if ([cmd isEqualToString:@"resetprofiles"]) { /* test profiles must not stay in the app after a run */
        for (PTProfile *pr in [[PTProfileStore shared] profiles]) [[PTProfileStore shared] deleteProfile:pr];
        g_profile = nil;
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; /* a test's font and theme must not reach the owner */
        [ud removePersistentDomainForName:[NSBundle mainBundle].bundleIdentifier];
        [ud synchronize];
        [PTTheme setDarkAppearance:NO];
        [g_split showProfile:nil];
        [g_split reloadList];
        return @"ok";
    }
    if ([cmd isEqualToString:@"audit"]) return layout_audit();
    if ([cmd isEqualToString:@"ui"]) return ui_list();
    if ([cmd isEqualToString:@"tap"]) return ui_tap(rest);
    if ([cmd isEqualToString:@"alertshown"]) {
        UIViewController *ac = open_alert_controller();
        if (ac) return [NSString stringWithFormat:@"%@: %@", ac.title, [ac valueForKey:@"message"]];
        UIAlertView *a = open_alert();
        return a ? [NSString stringWithFormat:@"%@: %@", a.title, a.message] : @"";
    }
    if ([cmd isEqualToString:@"alertok"]) {
        UIViewController *ac = open_alert_controller();
        if (ac) { /* the Cancel action if there is one, as the UIAlertView path takes its cancel button; test-only KVC reads its handler */
            NSArray *actions = [ac valueForKey:@"actions"];
            id chosen = actions.firstObject;
            for (id act in actions) if ([[act valueForKey:@"style"] integerValue] == 1) chosen = act;
            void (^handler)(id) = [chosen valueForKey:@"handler"];
            [ac dismissViewControllerAnimated:NO completion:nil];
            /* Mac Catalyst closes a sheet later than the call returns, and a second dismiss would close the form under it. */
            for (int i = 0; i < 100 && open_alert_controller(); i++) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            if (handler) handler(chosen);
            return @"ok";
        }
        UIAlertView *a = open_alert();
        if (!a) return @"ERR no alert";
        [a dismissWithClickedButtonIndex:a.cancelButtonIndex >= 0 ? a.cancelButtonIndex : 0 animated:NO];
        return @"ok";
    }
    if ([cmd isEqualToString:@"setfield"]) { /* setfield <index among the visible fields> <text> */
        NSRange sp = [rest rangeOfString:@" "];
        NSInteger want = (sp.location == NSNotFound ? rest : [rest substringToIndex:sp.location]).integerValue;
        NSString *text = sp.location == NSNotFound ? @"" : [rest substringFromIndex:sp.location + 1];
        NSMutableArray *fields = [NSMutableArray array];
        walk_all(^(UIView *v) { if ([v isKindOfClass:[UITextField class]]) [fields addObject:v]; });
        [fields sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { /* top to bottom, as a user counts them */
            CGFloat ya = [a convertRect:a.bounds toView:nil].origin.y, yb = [b convertRect:b.bounds toView:nil].origin.y;
            return ya < yb ? NSOrderedAscending : ya > yb ? NSOrderedDescending : NSOrderedSame;
        }];
        if ((NSUInteger)want >= fields.count) return @"ERR field";
        [(UITextField *)fields[(NSUInteger)want] setText:text];
        return @"ok";
    }
    if ([cmd isEqualToString:@"settext"]) { /* the key box: text as it would come from a paste, and it takes the focus */
        __block UITextView *box = nil;
        walk_all(^(UIView *v) { if (!box && [v isKindOfClass:[UITextView class]]) box = (UITextView *)v; });
        if (!box) return @"ERR no text view";
        [box becomeFirstResponder];
        box.text = [rest stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
        return @"ok";
    }
    if ([cmd isEqualToString:@"scrolltop"]) {
        walk_all(^(UIView *v) { if ([v isKindOfClass:[UITableView class]]) [(UITableView *)v setContentOffset:CGPointZero animated:NO]; });
        return @"ok";
    }
    if ([cmd isEqualToString:@"endedit"]) { [[UIApplication sharedApplication].keyWindow endEditing:YES]; return @"ok"; }
    if ([cmd isEqualToString:@"appearance"]) { /* appearance light|dark: PTTheme applies it at once to every open screen */
        SEL set = NSSelectorFromString(@"setDarkAppearance:");
        if (![PTTheme respondsToSelector:set]) return @"ERR no appearance";
        BOOL dark = [rest isEqualToString:@"dark"];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[PTTheme methodSignatureForSelector:set]];
        inv.selector = set;
        inv.target = [PTTheme class];
        [inv setArgument:&dark atIndex:2];
        [inv invoke];
        return @"ok";
    }
    if ([cmd isEqualToString:@"rotate"]) { /* test build only: the private setter is the one way to turn the screen with no hand */
        NSInteger o = [rest isEqualToString:@"landscape"] ? UIDeviceOrientationLandscapeLeft : UIDeviceOrientationPortrait;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[UIDevice instanceMethodSignatureForSelector:NSSelectorFromString(@"setOrientation:")]];
        inv.selector = NSSelectorFromString(@"setOrientation:");
        inv.target = [UIDevice currentDevice];
        [inv setArgument:&o atIndex:2];
        [inv invoke];
        return @"ok";
    }
    if ([cmd isEqualToString:@"back"]) { [g_split dismissModals]; return @"ok"; }
    if ([cmd isEqualToString:@"pin"]) return g_profile.pinnedFingerprint ?: @"";
    if (!c) return @"ERR no terminal";
    if ([cmd isEqualToString:@"dump"]) return screen_dump(c);
    if ([cmd isEqualToString:@"status"]) return [NSString stringWithFormat:@"connected=%d status=%@", [c testConnected], [c testStatus]];
    if ([cmd isEqualToString:@"size"]) { int r, k; pt_term_size([c testTerm], &r, &k); return [NSString stringWithFormat:@"%d %d", r, k]; }
    if ([cmd isEqualToString:@"alertstate"]) return [NSString stringWithFormat:@"hasalert=%d", [c testHasAlert]];
    if ([cmd isEqualToString:@"alert"]) return [c testAnswerAlert:[rest isEqualToString:@"trust"]] ? @"ok" : @"ERR no alert";
    if ([cmd isEqualToString:@"perf"]) return [NSString stringWithFormat:@"%.1f", perf_ms(c, rest.intValue ?: 10)];
    if ([cmd isEqualToString:@"font"]) { if ([rest isEqualToString:@"+"]) [c fontUp]; else [c fontDown]; return @"ok"; }
    if ([cmd isEqualToString:@"theme"]) { [c testTheme:rest]; return @"ok"; }
    if ([cmd isEqualToString:@"title"]) return [c testTitle];
    if ([cmd isEqualToString:@"foreground"]) { [c testForeground]; return @"ok"; }
    if ([cmd isEqualToString:@"sessionspopover"]) { [c testShowSessions]; return @"ok"; }
    if ([cmd isEqualToString:@"popoverselect"]) return [c testPopoverSelectRow:rest.integerValue];
    if ([cmd isEqualToString:@"settings"]) { [c testGear]; return @"ok"; }
    if ([cmd isEqualToString:@"type"]) {
        [[c testView] insertText:[rest stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"]]; /* UIKeyInput path */
        return @"ok";
    }
    if ([cmd isEqualToString:@"tapkey"]) { /* a real key-bar button by its title */
        for (UIView *v in [c testKeyBar].subviews)
            if ([v isKindOfClass:[UIButton class]] && [[(UIButton *)v titleForState:UIControlStateNormal] isEqualToString:rest]) {
                [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
                return @"ok";
            }
        return @"ERR no such key";
    }
    if ([cmd isEqualToString:@"backspace"]) { [[c testView] deleteBackward]; return @"ok"; }
    if ([cmd isEqualToString:@"wheel"]) { [c terminalViewWheelAtRow:5 col:5 lines:rest.intValue]; return @"ok"; }
    if ([cmd isEqualToString:@"ctrl"]) { [c terminalViewDidTypeControl:(char)([rest characterAtIndex:0] & 0x1f)]; return @"ok"; }
    if ([cmd isEqualToString:@"paste"]) { [c terminalViewPaste:rest]; return @"ok"; }
    if ([cmd isEqualToString:@"key"]) {
        NSDictionary *k = @{@"esc": @(PT_KEY_ESC), @"tab": @(PT_KEY_TAB), @"backtab": @(PT_KEY_BACKTAB), @"enter": @(PT_KEY_ENTER),
                            @"up": @(PT_KEY_UP), @"down": @(PT_KEY_DOWN), @"left": @(PT_KEY_LEFT), @"right": @(PT_KEY_RIGHT),
                            @"pgup": @(PT_KEY_PAGEUP), @"pgdn": @(PT_KEY_PAGEDOWN), @"ctrlc": @(PT_KEY_CTRL_C)};
        if (!k[rest]) return @"ERR key";
        [c keyBarKey:(pt_key)[k[rest] intValue]];
        return @"ok";
    }
    return @"ERR unknown";
}

/* One command per line; the reply ends with a line "\x01END". */
static void *control_thread(void *arg) {
    int l = listen_on(PORT_CONTROL);
    for (;;) {
        int fd = accept(l, NULL, NULL);
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        FILE *in = fdopen(fd, "r"), *f = fdopen(dup(fd), "w");
        char line[16384];
        while (fgets(line, sizeof line, in)) {
            @autoreleasepool {
                line[strcspn(line, "\r\n")] = 0;
                NSString *cmd = [NSString stringWithUTF8String:line];
                __block NSString *reply;
                dispatch_sync(dispatch_get_main_queue(), ^{ reply = handle(cmd); });
                fprintf(f, "%s\n\x01" "END\n", reply.UTF8String ?: "");
                fflush(f);
            }
        }
        fclose(f);
        fclose(in);
    }
    return NULL;
}

@implementation PTSelfTest
+ (void)beat { ptm_heartbeat(); }
+ (void)startWithHome:(PTSplitController *)home {
    g_split = home;
    [UIApplication sharedApplication].idleTimerDisabled = YES; /* the test runs with nobody at the iPad */
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:[PTSelfTest class] selector:@selector(beat) userInfo:nil repeats:YES];
    pthread_t t;
    pthread_create(&t, NULL, relay_thread, NULL);
    pthread_create(&t, NULL, control_thread, NULL);
    NSLog(@"PTSELFTEST ready");
}
@end
