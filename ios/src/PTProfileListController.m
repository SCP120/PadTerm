#import "PTProfileListController.h"
#import "PTArt.h"
#import "PTProfileStore.h"
#import "PTSplitController.h"
#import "PTTheme.h"

@implementation PTProfileListController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) self.title = @"Servers";
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 58;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];
    self.navigationItem.leftBarButtonItem = self.editButtonItem;
    [PTTheme styleTable:self.tableView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged) name:PTAppearanceDidChangeNotification object:nil];
}

- (void)appearanceChanged {
    [PTTheme styleTable:self.tableView];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    [self.tableView reloadData];
    NSArray *all = [[PTProfileStore shared] profiles];
    for (NSUInteger i = 0; i < all.count; i++)
        if ([[all[i] uid] isEqualToString:_selectedUID])
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
}

- (void)add { [(PTSplitController *)self.splitViewController editProfile:[PTProfile newProfile] isNew:YES]; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return MAX(1, (NSInteger)[[PTProfileStore shared] profiles].count); }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *rid = [PTTheme reuseId:@"server"];
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:rid];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
        c.textLabel.font = [PTArt bold:17];
        c.detailTextLabel.font = [PTArt regular:14];
        c.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }
    [PTTheme styleCell:c in:t at:ip];
    NSArray *all = [[PTProfileStore shared] profiles];
    if (!all.count) {
        c.imageView.image = nil;
        c.textLabel.text = @"No servers";
        c.detailTextLabel.text = @"Tap + to add one";
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    PTProfile *p = all[ip.row];
    c.selectionStyle = UITableViewCellSelectionStyleBlue;
    c.imageView.image = [PTArt serverIcon:36];
    c.textLabel.text = p.name;
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@@%@:%ld", p.user, p.host, (long)p.port];
    return c;
}

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip { return [[PTProfileStore shared] profiles].count > 0; }

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    PTProfile *gone = [[PTProfileStore shared] profiles][ip.row];
    [[PTProfileStore shared] deleteProfile:gone];
    if ([gone.uid isEqualToString:_selectedUID])
        [(PTSplitController *)self.splitViewController showProfile:[[PTProfileStore shared] profiles].firstObject];
    else
        [self reload];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *all = [[PTProfileStore shared] profiles];
    if (all.count) [(PTSplitController *)self.splitViewController showProfile:all[ip.row]];
}

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end
