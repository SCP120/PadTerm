#import "PTProfileEditController.h"
#import "PTTheme.h"
#import "PTArt.h"
#import "PTProfileStore.h"

enum { SEC_SERVER, SEC_KEY, SEC_HOST_KEY, SEC_COUNT };
enum { KEY_MODE_PASTE, KEY_MODE_IMPORT };
enum { ROW_NAME, ROW_HOST, ROW_PORT, ROW_USER, ROW_DIR, ROW_COUNT };
enum { ROW_H = 44, KEY_ROW_H = 160, LABEL_W = 130 }; /* LABEL_W: "Directory" in bold 17 pt ends at 90 pt, plus the cell margin */

/* A cell that carries one view that outlives the cell (a field, the key box, the segmented control). The view's frame is
 * set in layoutSubviews from the cell's own width, so a rebuilt cell, a form sheet of 540 pt or a rotation never leaves a
 * frame from another width behind. */
@interface PTHostedCell : UITableViewCell
@property (nonatomic, strong) UIView *hosted;
@property (nonatomic) UIEdgeInsets insets;
@end
@implementation PTHostedCell
- (void)setHosted:(UIView *)v {
    _hosted = v;
    v.autoresizingMask = UIViewAutoresizingNone;
    [self.contentView addSubview:v]; /* moves it out of the cell that held it before */
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _hosted.frame = UIEdgeInsetsInsetRect(self.contentView.bounds, _insets);
    if (self.textLabel.text.length) { /* the default label spans the cell: it must end where the hosted view starts */
        CGRect f = self.textLabel.frame;
        f.size.width = MIN(f.size.width, _insets.left - f.origin.x - 4);
        self.textLabel.frame = f;
    }
    [self.contentView bringSubviewToFront:_hosted];
}
@end

@implementation PTProfileEditController {
    PTProfile *_profile;
    BOOL _isNew;
    UITextField *_fields[ROW_COUNT];
    UITextView *_keyText;
    UISegmentedControl *_keyMode;
    NSData *_newKey;
    NSString *_importedName; /* the file to delete after a Save: the Name field can change after the import */
}

- (instancetype)initWithProfile:(PTProfile *)profile isNew:(BOOL)isNew {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _profile = [PTProfile fromDictionary:[profile dictionary]]; /* edit a copy; save replaces */
        _isNew = isNew;
        self.title = isNew ? @"New Server" : @"Edit Server";
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStyleBordered
                                                                             target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    _keyMode = [[UISegmentedControl alloc] initWithItems:@[@"Paste", @"Import file"]];
    _keyMode.selectedSegmentIndex = KEY_MODE_PASTE;
    [_keyMode addTarget:self action:@selector(keyModeChanged) forControlEvents:UIControlEventValueChanged];
    static NSString *const labels[ROW_COUNT] = {@"Name", @"Host", @"Port", @"User", @"Directory"};
    static NSString *const hints[ROW_COUNT] = {@"my-vps", @"example.com or 192.168.1.10", @"22", @"you", @"~/projects/app"};
    NSString *values[ROW_COUNT] = {_profile.name, _profile.host, [@(_profile.port) stringValue], _profile.user, _profile.directory};
    for (int i = 0; i < ROW_COUNT; i++) {
        UITextField *f = [[UITextField alloc] init];
        f.font = [PTArt regular:17];
        f.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
        f.placeholder = hints[i];
        f.text = values[i];
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.keyboardType = i == ROW_PORT ? UIKeyboardTypeNumberPad : UIKeyboardTypeASCIICapable;
        f.accessibilityLabel = labels[i];
        _fields[i] = f;
    }
    _keyText = [[UITextView alloc] init];
    _keyText.font = [UIFont fontWithName:@"DejaVuSansMono" size:11] ?: [UIFont fontWithName:@"Courier" size:11];
    _keyText.autocorrectionType = UITextAutocorrectionTypeNo;
    _keyText.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _keyText.backgroundColor = [UIColor clearColor];
    [self restyle];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged) name:PTAppearanceDidChangeNotification object:nil];
}

/* The fields are the same views for the life of the form; only their colours follow the appearance. */
- (void)restyle {
    [PTTheme styleTable:self.tableView];
    for (int i = 0; i < ROW_COUNT; i++) {
        _fields[i].textColor = [PTTheme valueColor]; /* settings.png: value text */
        _fields[i].keyboardAppearance = [PTTheme keyboardAppearance];
    }
    _keyText.textColor = [PTTheme textColor];
    _keyText.keyboardAppearance = [PTTheme keyboardAppearance];
}
- (void)appearanceChanged {
    [self restyle];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return _isNew ? SEC_COUNT - 1 : SEC_COUNT; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return s == SEC_SERVER ? ROW_COUNT : s == SEC_KEY ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (s == SEC_SERVER) return @"Server";
    if (s == SEC_KEY) return [[PTProfileStore shared] keyForProfile:_profile] ? @"Private key (saved; paste a new one to replace it)" : @"Private key (none yet)";
    return @"Host key";
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == SEC_KEY)
        return @"Paste an unencrypted OpenSSH Ed25519 key (ssh-keygen -t ed25519 -N \"\"), or copy it as <name>.key into "
                "this app's Documents with iTunes File Sharing, choose Import file and tap Import; the app then deletes that copy. "
                "Add the .pub line to ~/.ssh/authorized_keys on the server. A device that refuses file protection, such as a jailbroken iPad, keeps the key with file mode 0600 only.";
    if (s == SEC_HOST_KEY) return @"Forget the pinned key only if the server key really changed.";
    return nil;
}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { [PTTheme styleHeaderFooter:v]; }
- (void)tableView:(UITableView *)t willDisplayFooterView:(UIView *)v forSection:(NSInteger)s { [PTTheme styleHeaderFooter:v]; }

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == SEC_KEY && ip.row == 1 && _keyMode.selectedSegmentIndex == KEY_MODE_PASTE ? KEY_ROW_H : ROW_H;
}

- (PTHostedCell *)hostedCell:(UIView *)v insets:(UIEdgeInsets)insets {
    PTHostedCell *c = [[PTHostedCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.insets = insets;
    c.hosted = v;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c;
    if (ip.section == SEC_SERVER) {
        c = [self hostedCell:_fields[ip.row] insets:UIEdgeInsetsMake(10, LABEL_W, 10, 10)];
        c.textLabel.text = _fields[ip.row].accessibilityLabel;
    } else if (ip.section == SEC_KEY && ip.row == 0) {
        c = [self hostedCell:_keyMode insets:UIEdgeInsetsMake(7, 10, 7, 10)];
    } else if (ip.section == SEC_KEY && _keyMode.selectedSegmentIndex == KEY_MODE_PASTE) {
        c = [self hostedCell:_keyText insets:UIEdgeInsetsMake(10, 10, 10, 10)];
    } else {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.selectionStyle = UITableViewCellSelectionStyleBlue;
        c.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        if (ip.section == SEC_KEY) {
            c.textLabel.text = @"Import <name>.key from Documents (File Sharing)";
            c.textLabel.font = [PTArt bold:15];
        } else {
            c.textLabel.text = _profile.pinnedFingerprint.length ? [@"Forget " stringByAppendingString:_profile.pinnedFingerprint] : @"Not pinned yet";
            c.textLabel.font = [PTArt regular:14];
        }
    }
    [PTTheme styleCell:c in:t at:ip];
    if (ip.section == SEC_KEY && ip.row == 1 && _keyMode.selectedSegmentIndex == KEY_MODE_IMPORT)
        c.textLabel.textColor = [PTTheme valueColor];
    if (ip.section == SEC_HOST_KEY)
        c.textLabel.textColor = _profile.pinnedFingerprint.length ? [UIColor redColor] : [PTTheme secondaryColor];
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SEC_KEY && ip.row == 1 && _keyMode.selectedSegmentIndex == KEY_MODE_IMPORT) {
        NSData *k = [[PTProfileStore shared] importableKeyForName:_fields[ROW_NAME].text];
        if (!k) { [self alert:@"No key file" text:[NSString stringWithFormat:@"Documents/%@.key does not exist. The file name must match the Name field.", _fields[ROW_NAME].text]]; return; }
        [self clearPastedKey]; /* a key pasted before this import must not stay on the pasteboard */
        if (_importedName && ![_importedName isEqualToString:_fields[ROW_NAME].text]) [[PTProfileStore shared] removeImportableKeyForName:_importedName];
        _newKey = k;
        _importedName = _fields[ROW_NAME].text;
        _keyText.text = @"(key imported \xE2\x80\x94 tap Save)";
        _keyMode.selectedSegmentIndex = KEY_MODE_PASTE;
        [self keyModeChanged];
    } else if (ip.section == SEC_HOST_KEY && _profile.pinnedFingerprint.length) {
        _profile.pinnedFingerprint = @"";
        [t reloadData];
    }
}

- (void)keyModeChanged {
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SEC_KEY] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)finish { [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil]; }
- (void)cancel {
    if (_newKey) [[PTProfileStore shared] removeImportableKeyForName:_importedName]; /* an imported copy must not stay in File Sharing */
    [self clearPastedKey];
    [self finish];
}

- (NSString *)pastedText { return [_keyText.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; }

/* The key must not stay on screen or on the pasteboard (BR-CONNECT-3). The pasteboard is read only when a key was pasted here. */
- (void)clearPastedKey {
    if (![[self pastedText] hasPrefix:@"-----BEGIN"]) return;
    _keyText.text = @"";
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if ([[pb.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] hasPrefix:@"-----BEGIN"]) pb.items = @[];
}

- (void)alert:(NSString *)title text:(NSString *)text {
    [PTTheme showMessage:text title:title from:self];
}

- (void)save {
    _profile.name = [_fields[ROW_NAME].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _profile.host = [_fields[ROW_HOST].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _profile.port = [_fields[ROW_PORT].text integerValue];
    _profile.user = [_fields[ROW_USER].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _profile.directory = _fields[ROW_DIR].text.length ? _fields[ROW_DIR].text : @"~";
    NSString *err = [_profile validationError];
    if (err) { [self alert:@"Check the server" text:err]; return; }
    NSData *key = _newKey;
    if (!key && [self pastedText].length) key = [[[self pastedText] stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]; /* anything else here must fail loud, not keep the old key */
    if (!key && ![[PTProfileStore shared] keyForProfile:_profile]) { [self alert:@"Add a key" text:@"This server has no private key yet."]; return; }
    if (key) {
        err = [[PTProfileStore shared] setKey:key forProfile:_profile];
        if (err) { [self alert:@"Key not accepted" text:err]; return; } /* EF-CONNECT-3 */
        if (_newKey) [[PTProfileStore shared] removeImportableKeyForName:_importedName];
    }
    [[PTProfileStore shared] saveProfile:_profile];
    [self clearPastedKey];
    [self finish];
    if (self.saved) self.saved(_profile);
}
@end
