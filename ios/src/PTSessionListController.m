#import "PTSessionListController.h"
#import "PTArt.h"
#import "PTSessionLister.h"
#import "PTTheme.h"

@interface PTSessionListController () <PTSessionListerDelegate>
@end

/* A session row in the layout of Mail's message list: unread dot, icon, name with the time on the right in blue, a grey
 * second line. Every frame is set in layoutSubviews from the cell's own width, so a reload never keeps a stale frame. */
enum { ROW_H = 64, ICON = 40, DOT_X = 10, ICON_X = 28, TEXT_X = 76, PAD = 8 };
@interface PTSessionCell : UITableViewCell
@property (nonatomic, readonly) UIImageView *icon, *dot;
@property (nonatomic, readonly) UILabel *name, *time, *detail;
@end
@implementation PTSessionCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid])) {
        _icon = [[UIImageView alloc] init];
        _dot = [[UIImageView alloc] initWithImage:[PTArt dot]];
        _name = [[UILabel alloc] init];
        _name.font = [PTArt bold:17];
        _name.lineBreakMode = NSLineBreakByTruncatingTail;
        _time = [[UILabel alloc] init];
        _time.font = [PTArt regular:14];
        _time.textAlignment = NSTextAlignmentRight;
        _detail = [[UILabel alloc] init];
        _detail.font = [PTArt regular:14];
        _detail.lineBreakMode = NSLineBreakByTruncatingMiddle;
        for (UILabel *l in @[_name, _time, _detail]) {
            l.backgroundColor = [UIColor clearColor];
            l.highlightedTextColor = [UIColor whiteColor];
        }
        for (UIView *v in @[_icon, _dot, _name, _time, _detail]) [self.contentView addSubview:v];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat timeW = ceil([_time.text sizeWithFont:_time.font].width), textW = b.size.width - TEXT_X - PAD;
    _dot.frame = CGRectMake(DOT_X, 14, 12, 12);
    _icon.frame = CGRectMake(ICON_X, floor((b.size.height - ICON) / 2), ICON, ICON);
    _time.frame = CGRectMake(b.size.width - PAD - timeW, 11, timeW, 21);
    _name.frame = CGRectMake(TEXT_X, 11, MAX(0, textW - timeW - 6), 21);
    _detail.frame = CGRectMake(TEXT_X, 35, MAX(0, textW), 18);
}
@end

@implementation PTSessionListController {
    PTProfile *_profile;
    PTSessionLister *_lister;
    NSArray *_held; /* rows that came while a Delete button shows: a row must not move under the finger */
    BOOL _swiping;
    NSMutableSet *_removed; /* keys deleted here: a read that started before the Delete must not bring them back */
}

- (instancetype)initWithProfile:(PTProfile *)profile {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _profile = profile;
        _sessions = @[];
        _footerMessage = @"Reading the sessions\xE2\x80\xA6";
    }
    return self;
}

- (void)dealloc {
    [_lister stop]; /* a popover can go with no viewWillDisappear */
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIRefreshControl *r = [[UIRefreshControl alloc] init];
    [r addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = r;
    [self restyle];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged) name:PTAppearanceDidChangeNotification object:nil];
}

- (void)restyle {
    [PTTheme styleTable:self.tableView];
    self.refreshControl.tintColor = [PTTheme isDarkAppearance] ? [PTArt hex:PT_DK_TEXT2] : nil;
}
- (void)appearanceChanged {
    [self restyle];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _swiping = NO;
    _held = nil;
    [_lister stop];
    _lister = [[PTSessionLister alloc] initWithProfile:_profile delegate:self];
    [_lister start];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_lister stop];
    _lister = nil;
}

- (void)refresh { [_lister refreshNow]; }

- (void)setShowsNewSession:(BOOL)shows {
    _showsNewSession = shows;
    if ([self isViewLoaded]) [self.tableView reloadData];
}

- (void)lister:(PTSessionLister *)lister didGetSessions:(NSArray *)sessions {
    if (lister != _lister) return;
    [self.refreshControl endRefreshing];
    if (_removed.count) {
        NSMutableArray *kept = [NSMutableArray array];
        NSMutableSet *still = [NSMutableSet set];
        for (PTSession *s in sessions) {
            if ([_removed containsObject:s.key]) [still addObject:s.key];
            else [kept addObject:s];
        }
        _removed = still; /* a read with no such key: the server has done it */
        sessions = kept;
    }
    if (_swiping) { _held = sessions; return; }
    [self showSessions:sessions];
}

/* AC-SESSION-2: no reload when nothing changed: a reload closes a Delete button and can move a row under a tap. */
- (void)showSessions:(NSArray *)sessions {
    NSString *footer = sessions.count ? nil : @"No sessions yet. Choose Claude, Codex or Shell to start one.";
    BOOL same = sessions.count == _sessions.count && (footer == _footerMessage || [footer isEqualToString:_footerMessage]);
    for (NSUInteger i = 0; same && i < sessions.count; i++) same = [sessions[i] sameRowAs:_sessions[i]];
    _sessions = sessions;
    _footerMessage = footer;
    if (!same) { [self.tableView reloadData]; return; }
    /* The age text moves on with no change in the data. */
    NSDate *now = [NSDate date];
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        UITableViewCell *c = [self.tableView cellForRowAtIndexPath:ip];
        if (![c isKindOfClass:[PTSessionCell class]] || (NSUInteger)ip.row >= _sessions.count) continue;
        [(PTSessionCell *)c time].text = [PTSession ageOfDate:[_sessions[(NSUInteger)ip.row] lastActive] now:now];
        [c setNeedsLayout];
    }
}

- (void)tableView:(UITableView *)t willBeginEditingRowAtIndexPath:(NSIndexPath *)ip { _swiping = YES; }

- (void)tableView:(UITableView *)t didEndEditingRowAtIndexPath:(NSIndexPath *)ip {
    _swiping = NO;
    if (_held) [self showSessions:_held];
    else [t reloadData]; /* a footer that came during the swipe, and the corners of the rows around a Delete */
    _held = nil;
}

- (void)appWillEnterForeground { [_lister reconnectNow]; }

- (void)lister:(PTSessionLister *)lister didFail:(NSString *)message {
    if (lister != _lister) return;
    _footerMessage = message; /* the rows from the last good read stay */
    [self.refreshControl endRefreshing];
    if (!_swiping) [self.tableView reloadData]; /* a reload closes a Delete button */
}

/* ---------------- table ---------------- */

static const pt_agent NEW_AGENTS[] = {PT_AGENT_CLAUDE, PT_AGENT_CODEX, PT_AGENT_SHELL};
static NSString *const NEW_TITLES[] = {@"Claude", @"Codex", @"Shell"};

- (NSInteger)sessionsSection { return _showsNewSession ? 1 : 0; }
- (BOOL)isNewSessionSection:(NSInteger)s { return _showsNewSession && s == 0; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return _showsNewSession ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return [self isNewSessionSection:s] ? 3 : (NSInteger)_sessions.count;
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return [self isNewSessionSection:ip.section] ? 44 : ROW_H; }

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if ([self isNewSessionSection:s]) return @"New Session";
    return _showsNewSession ? @"Sessions" : nil;
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return [self isNewSessionSection:s] ? _startFooter : _footerMessage;
}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { [PTTheme styleHeaderFooter:v]; }
- (void)tableView:(UITableView *)t willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { [PTTheme styleHeaderFooter:v]; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isNewSessionSection:ip.section]) {
        NSString *rid = [PTTheme reuseId:@"n"];
        UITableViewCell *c = [t dequeueReusableCellWithIdentifier:rid];
        if (!c) {
            c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
            c.textLabel.font = [PTArt bold:17];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        [PTTheme styleCell:c in:t at:ip];
        c.imageView.image = [PTArt agentIcon:NEW_AGENTS[ip.row] size:29]; /* the 29 pt icon of the Settings rows */
        c.textLabel.text = NEW_TITLES[ip.row];
        return c;
    }
    NSString *rid = [PTTheme reuseId:@"s"];
    PTSessionCell *c = [t dequeueReusableCellWithIdentifier:rid];
    if (!c) c = [[PTSessionCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
    [PTTheme styleCell:c in:t at:ip];
    PTSession *s = _sessions[(NSUInteger)ip.row];
    c.name.text = s.displayTitle;
    c.name.textColor = [PTTheme textColor];
    c.time.text = [PTSession ageOfDate:s.lastActive now:[NSDate date]];
    c.time.textColor = [PTTheme timeColor];
    c.detail.text = [NSString stringWithFormat:@"%@ \xC2\xB7 %@", s.agentName, s.directory];
    c.detail.textColor = [PTTheme secondaryColor];
    c.icon.image = [PTArt agentIcon:s.agent size:ICON];
    c.dot.hidden = !s.running;
    c.accessoryType = [s.key isEqualToString:_currentKey] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    [c setNeedsLayout];
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if ([self isNewSessionSection:ip.section]) {
        if (self.onNewSession) self.onNewSession(NEW_AGENTS[ip.row]);
        return;
    }
    if (self.selected) self.selected(_sessions[(NSUInteger)ip.row]);
}

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isNewSessionSection:ip.section]) return NO;
    return ![[(PTSession *)_sessions[(NSUInteger)ip.row] key] isEqualToString:_currentKey]; /* not the open one */
}

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    PTSession *s = _sessions[(NSUInteger)ip.row];
    NSMutableArray *rest = [_sessions mutableCopy];
    [rest removeObject:s];
    _sessions = rest;
    _held = nil;
    if (!_removed) _removed = [NSMutableSet set];
    [_removed addObject:s.key];
    [t deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    if (_sessions.count) { /* dark rows take their corners from their position */
        NSMutableArray *around = [NSMutableArray array];
        for (NSInteger r = MAX(0, ip.row - 1); r <= MIN((NSInteger)_sessions.count - 1, ip.row); r++)
            [around addObject:[NSIndexPath indexPathForRow:r inSection:ip.section]];
        [t reloadRowsAtIndexPaths:around withRowAnimation:UITableViewRowAnimationNone];
    }
    [_lister removeSession:s];
}

#ifdef PT_SELFTEST
- (void)testSwipeDeleteRow:(NSInteger)row {
    [self tableView:self.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:[self sessionsSection]]];
}
- (void)testSelectRow:(NSInteger)row {
    [self tableView:self.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:[self sessionsSection]]];
}
#endif

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end
