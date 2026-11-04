#import "PTSettings.h"
#import "PTArt.h"
#import "PTTheme.h"
#import <QuartzCore/QuartzCore.h>

NSString *const PTFontKey = @"PTFontSize", *const PTThemeKey = @"PTThemeName", *const PTKeyClickKey = @"PTKeyClick",
         *const PTKeepAwakeKey = @"PTKeepAwake";

enum { SEC_APPEARANCE, SEC_FONT, SEC_THEME, SEC_CLICK, SEC_AWAKE, SEC_COUNT };
enum { CHIP = 56, SWATCH_ROW_H = 76 };

/* The terminal themes as swatches in one row, as iBooks' Themes popover shows its three. The chips are placed in
 * layoutSubviews, so the row is right at any width. */
@interface PTSwatchCell : UITableViewCell
@property (nonatomic, readonly) NSArray *chips;
- (instancetype)initWithTarget:(id)target action:(SEL)action;
- (void)mark:(NSString *)name;
@end
@implementation PTSwatchCell
- (instancetype)initWithTarget:(id)target action:(SEL)action {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) {
        NSMutableArray *chips = [NSMutableArray array];
        for (PTTheme *th in [PTTheme all]) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.backgroundColor = th.bgColor;
            b.layer.cornerRadius = 10; /* a popover, not the terminal: the offscreen pass costs nothing here */
            b.titleLabel.font = [PTArt bold:20];
            [b setTitle:@"Aa" forState:UIControlStateNormal];
            [b setTitleColor:th.fgColor forState:UIControlStateNormal];
            b.accessibilityLabel = th.name;
            [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
            [self.contentView addSubview:b];
            [chips addObject:b];
        }
        _chips = chips;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat gap = floor((b.size.width - _chips.count * CHIP) / (_chips.count + 1));
    for (NSUInteger i = 0; i < _chips.count; i++)
        [(UIView *)_chips[i] setFrame:CGRectMake(gap + i * (CHIP + gap), floor((b.size.height - CHIP) / 2), CHIP, CHIP)];
}
- (void)mark:(NSString *)name {
    for (UIButton *b in _chips) {
        BOOL on = [b.accessibilityLabel isEqualToString:name];
        b.layer.borderWidth = on ? 3 : 1;
        b.layer.borderColor = (on ? [PTArt hex:PT_SEL_TOP] : [PTArt hex:0x000000 alpha:0.35]).CGColor;
    }
}
@end

@implementation PTSettingsController {
    UITableViewCell *_fontCell;
    PTSwatchCell *_swatchCell;
}

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{PTKeyClickKey: @YES, PTKeepAwakeKey: @YES}];
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) self.title = @"Settings";
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [PTTheme styleTable:self.tableView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged) name:PTAppearanceDidChangeNotification object:nil];
}

/* The segmented control that sent the change is still on the stack: the rows are rebuilt after it returns. */
- (void)appearanceChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [PTTheme styleTable:self.tableView];
        [self.tableView reloadData];
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return SEC_COUNT; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1; }
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return ip.section == SEC_THEME ? SWATCH_ROW_H : 44; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s == SEC_THEME ? @"Terminal Theme" : nil; }
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s { [PTTheme styleHeaderFooter:v]; }

- (UISwitch *)switchForKey:(NSString *)key {
    UISwitch *s = [[UISwitch alloc] init];
    s.on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    s.accessibilityLabel = key;
    [s addTarget:self action:@selector(switched:) forControlEvents:UIControlEventValueChanged];
    return s;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == SEC_THEME) {
        _swatchCell = [[PTSwatchCell alloc] initWithTarget:self action:@selector(chip:)];
        [_swatchCell mark:[PTTheme current].name];
        [PTTheme styleCell:_swatchCell in:t at:ip];
        return _swatchCell;
    }
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:ip.section == SEC_FONT ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault
                                                reuseIdentifier:nil];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.font = [PTArt bold:17];
    [PTTheme styleCell:c in:t at:ip];
    switch (ip.section) {
    case SEC_APPEARANCE: {
        c.textLabel.text = @"Appearance";
        UISegmentedControl *sc = [[UISegmentedControl alloc] initWithItems:@[@"Light", @"Dark"]];
        sc.frame = CGRectMake(0, 0, 150, 30);
        sc.selectedSegmentIndex = [PTTheme isDarkAppearance] ? 1 : 0;
        [sc addTarget:self action:@selector(appearancePicked:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sc;
        break;
    }
    case SEC_FONT: {
        c.textLabel.text = @"Font Size";
        UIStepper *st = [[UIStepper alloc] init];
        st.minimumValue = PT_FONT_MIN;
        st.maximumValue = PT_FONT_MAX;
        st.value = [[NSUserDefaults standardUserDefaults] integerForKey:PTFontKey] ?: PT_FONT_DEFAULT;
        [st addTarget:self action:@selector(stepped:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = st;
        c.detailTextLabel.textColor = [PTTheme valueColor];
        c.detailTextLabel.text = [NSString stringWithFormat:@"%d pt", (int)st.value];
        _fontCell = c;
        break;
    }
    case SEC_CLICK:
        c.textLabel.text = @"Key Click";
        c.accessoryView = [self switchForKey:PTKeyClickKey];
        break;
    default:
        c.textLabel.text = @"Keep Screen On";
        c.accessoryView = [self switchForKey:PTKeepAwakeKey];
    }
    return c;
}

- (void)appearancePicked:(UISegmentedControl *)s {
    [PTTheme setDarkAppearance:s.selectedSegmentIndex == 1];
    [self.delegate settingsChanged]; /* the matching terminal theme is already chosen */
}
- (void)stepped:(UIStepper *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)s.value forKey:PTFontKey];
    _fontCell.detailTextLabel.text = [NSString stringWithFormat:@"%d pt", (int)s.value];
    [self.delegate settingsChanged];
}
- (void)chip:(UIButton *)b {
    for (PTTheme *th in [PTTheme all]) if ([th.name isEqualToString:b.accessibilityLabel]) [PTTheme select:th];
    [_swatchCell mark:[PTTheme current].name];
    [self.delegate settingsChanged];
}
- (void)switched:(UISwitch *)s {
    [[NSUserDefaults standardUserDefaults] setBool:s.on forKey:s.accessibilityLabel];
    [self.delegate settingsChanged];
}
@end
