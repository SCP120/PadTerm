# PadTerm UI: stock iOS 6, light and dark

Target: iPad mini 1, iOS 6.1.3, 768x1024 points (1x), A5, 512 MB. The terminal text area stays plain.
Rule for every element: would Apple ship it in Mail or Settings? If UIKit draws it, UIKit draws it. Custom art exists only where no stock control exists (the icons, the key bar, the dark rows, the black popover).

## 1. What the references say

| Finding | Evidence |
|---------|----------|
| Apple's productive iPad apps of 2012 (Mail, Settings, Notes, App Store) use the stock silver bar, grouped tables with the stock background, classic blue selection and slate-blue values. | `build/ipad/ref/settings.png` (capture from this iPad) |
| A split view is the Apple pattern for "a list on one side, its content on the other". The list is a table. | iOS HIG, Tables: "often appear as a means of navigation on one side of a split view" (codershigh.github.io mirror of the HIG) |
| Apple's own dark chrome of that time is black or charcoal with grey text: iBooks night theme (iBooks 1.5, Dec 2011), Photos and Videos (`UIBarStyleBlack`), Final Cut Pro X and Aperture panels. | `build/ipad/ref/web2/ibooks_night.jpg` (TidBITS); Macworld and Ars articles on Final Cut Pro X (text only) |
| UIKit has its own black popover art (`_UIPopoverViewBlack*`) but it is private. The public route is `UIPopoverBackgroundView` (iOS 5). | Stack Overflow thread "How to force black borders for UIPopoverControllers" |
| iOS 6 has two keyboards: default and `UIKeyboardAppearanceAlert` (dark). | UIKit header; Stack Overflow "New black keyboard on IOS 5" |

Research limits, plainly:
- Web research gave articles, HIG text mirrors and two images. It gave no pixel values for Mail, iBooks, Photos, Final Cut Pro X or the dark keyboard.
- The 2012 iOS HIG itself was not found as a primary document. The HIG pages found are later mirrors; they confirm the table and popover guidance, not exact pixels.
- Every light-mode number below comes from `settings.png` and the earlier `calendar.png` and `claude.png` captures. Every dark-mode number is chosen, not measured.

## 2. Measured colours (light)

Tool: a small CoreGraphics pixel reader (not in the repo). Samples are single pixels or row averages.

| Name in code | Value | Capture, sample |
|--------------|-------|-----------------|
| Stock bar, 44 rows (launch images only) | row 0 #FFFFFF, 3 #F4F5F7, 12 #F0F1F3, 18 #E6E7EB, 24 #D8DAE0, 30 #C7CAD3, 36 #B3B7C2, 42 #A8ACB9, 43 #797F90 | `settings.png`, column x=450, y=20+row |
| Bar shadow, 3 rows | #BABDC1, #CFD1D6, #DCDFE4 | same, y=64..66 |
| Divider | 1 px #000000, bar included | `settings.png`, x=300, y=0..1000 |
| `PT_SLATE_HEAD` (bar title, section header text) | #4C566C | `settings.png`, "Use Side Switch to:" |
| `PT_TITLE_GREY` | #717880 | `settings.png`, "General" in the bar, darkest pixel |
| `PT_SLATE` (value text) | #385487 | `settings.png`, "Not Connected" |
| `PT_SEL_TOP` / `PT_SEL_BOTTOM` | #058AF1 to #015DE6 | `settings.png`, General row |
| Grouped row | #F7F7F7, separator #CACACA with #FDFDFD below | `settings.png`, x=340 |
| Detail background | #E2E5EA at y=90 to #D3D5DB at y=900 | `settings.png`, x=700 |
| `PT_DOT_BLUE` | #1879F2 | `calendar.png`, today marker; used as the unread dot |
| `PT_GREY_TEXT` | #8C8C8C | `calendar.png`, "No Events" |
| Light keys | white top row, body #D6D6D8 to #B2B2B7, edge #4A4A4F, bottom rim #7C7C7F then #000000 | `claude.png`, shift key |
| Light key bar | #9E9DA7 at the top to #787881 at 57 px, top line #BDBDBD | `claude.png`, x=4 |

Not measured, and marked as such in code comments: the time-stamp blue in dark (#6CA8FF), the second title line colour in light (#636B7C), every dark value below.

## 3. Dark palette (chosen, not measured)

Apple's dark language of that era: black bars, charcoal panels, grey text, blue selection that does not change.

| Name | Value | Use |
|------|-------|-----|
| `PT_DK_BG` | #1E1F22 | behind grouped rows |
| `PT_DK_PLAIN` | #2B2C30 | plain table rows (the server list) |
| `PT_DK_ROW_TOP` to `PT_DK_ROW_BOTTOM` | #3A3C40 to #303236 | grouped row body; 1 px highlight #54575E on the first row |
| `PT_DK_ROW_EDGE` | #111214 | outer edge of a grouped row |
| `PT_DK_TEXT` / `PT_DK_TEXT2` / `PT_DK_VALUE` / `PT_DK_HEAD` | #F2F2F2 / #A6AAB2 / #7FB0F5 / #A2A6AE | text, secondary text, values, section headers |
| Dark keys | body #5E6065 to #44464B, edge #141517, rim #1B1C1F, highlight white 28% | next to `UIKeyboardAppearanceAlert` |
| Dark key bar | #3A3C41 to #232427, top line #5A5D63 | same |

Contrast against the row body (computed): text 13:1, secondary 5:1, value 5.5:1.

## 4. Screens

### 4.1 Home: split view
- Both bars are stock `UINavigationBar`. Light: silver, no tint, no image. Dark: `UIBarStyleBlack`.
- Master "Servers": plain table, 58 pt rows, a 36 pt glossy server icon, name in bold 17, `user@host:port` grey 14. Stock selection (blue). Stock Edit button left, stock Add item right.
- Detail, the server page: one grouped table. Group "New Session" has three Settings-style rows (29 pt glossy icon, label, disclosure chevron): Claude, Codex, Shell. Its footer is `user@host:port in directory`. Group "Sessions" follows, rows laid out like Mail's message list:

| Part | Look |
|------|------|
| Unread dot | `PT_DOT_BLUE`, 12 pt, only for a running session, x=10 |
| Icon | 40 pt glossy agent icon at x=28 |
| Line 1 | name in bold 17, truncates at the tail; time on the right in blue 14 (`PT_SEL_BOTTOM`) |
| Line 2 | `agent · directory`, grey 14, truncates in the middle |
| Accessory | stock disclosure chevron; check mark for the open session in the popover |

- Stock swipe-to-Delete, `UIRefreshControl`. The footer of the sessions group is `footerMessage` ("No sessions yet…", or the error text).
- Empty state (no server): centred stack in the Mail style: the cat, bold grey "No Servers", one line of help, three numbered steps with blue badges, then "Add Server" as the stock rounded-rect button (light) or a dark single row (dark).

### 4.2 Terminal
- Stock bar. Left: bordered bar button "Servers". Title: Music's two-line pattern, the session name in bold 15, under it the state with its LED, both centred. Right: bordered "Sessions" and a gear (20 pt alpha mask; UIKit draws it in the bar's own style).
- The terminal view keeps its 6 pt margin (it fixes the column count); the margin is the terminal theme's background colour.
- Key bar (50 pt): drawn to match the keyboard below it, light or dark, same key anatomy (white top row, edge, rim). Armed Ctrl is selection blue with a white dot. 44 pt keys.
- `PTTerminalView.keyboardAppearance` returns the dark keyboard in dark mode and the default one in light mode.

### 4.3 Form sheet (540 pt)
Stock grouped table, stock `UIAlertView`. Save is the stock Done button. Values are slate blue. The key-source control is a stock `UISegmentedControl`. Every field, the key box and the segmented control sit in `PTHostedCell`, which sets the frame in `layoutSubviews` from the cell's width. A reload, the 540 pt sheet or a rotation cannot leave a frame of another width behind.

### 4.4 Settings popover
Stock grouped table: Appearance (Light / Dark segmented control), Font Size (value and stepper), Terminal Theme (four swatches in one row, as iBooks' Themes popover), Key Click, Keep Screen On. Dark mode uses black glass through `popoverBackgroundViewClass`.

### 4.5 The mascot
One character: an orange tabby cat with terminal-green eyes, holding an old iPad with `>_` on its screen. It is on the app icon, on the Claude and Codex rows (the background colour tells the rows apart) and on the empty page. Recipe: `pt_art_mascot` in `ios/src/PTArt.m`.

| Trait of the iOS 5 and 6 era characters | Seen in | The cat |
|---|---|---|
| Glossy, shaded cartoon, not pixel art | Most icons on the reference sheet; only Pocket Planes and Tiny Tower use pixels | Gradients, a specular shine on the shell |
| The character fills the icon | Pou, Bad Piggies, Cut the Rope, Hay Day | Fills the icon edge to edge |
| Huge white eyes with catchlights | Cut the Rope, Pou, Feed Me Oil | The largest shapes on the face, green like terminal text |
| Dark tinted ink line, not pure black | Doodle Jump, Cut the Rope, Pocket God | `#3A1A06`, one outline over joined parts |
| One odd feature tied to the game | Om Nom's teeth and antenna, Doodle's snout | The iPad it holds, with a shell prompt on the screen |
| Loud background with rays or a radial | Bad Piggies, Monster Dash, Tiny Wings | Blue sky radial with sun rays |

Limit of this research: the App Store API returns each app's current icon, and archive.org refused the 2012 pages (HTTP 429). The icons of apps updated long ago are the closest evidence; no icon on the sheet is proven to be the 2012 version. Written design sources were thin, so the table comes from looking at the icons.

## 5. Appearance switching

| Piece | How |
|-------|-----|
| API | `+[PTTheme setDarkAppearance:]`, `+[PTTheme isDarkAppearance]`. Stored in `NSUserDefaults` (`PTDarkAppearance`). Default light. |
| Terminal theme | Setting the appearance also selects classic (dark) or light (light). The user can pick another theme afterwards. |
| Notification | `PTAppearanceDidChangeNotification`, posted on the main thread. |
| Navigation bars | `PTNavigationController` sets `barStyle` on load and on the notification. |
| Tables | `+styleTable:` (background, separator), `+styleCell:in:at:` (row images, text colours), `+styleHeaderFooter:`. In light mode these change nothing. Cells use one reuse queue per appearance (`+reuseId:`). |
| Controllers | Each open controller restyles itself on the notification: the split view, the server list, the server page, the empty page, the form, the settings popover, the key bar, the terminal (title colours, terminal theme, keyboard through `reloadInputViews`). |
| Connection | Nothing is rebuilt. The terminal controller, its connection and the session stay as they are. |
| Open popover | Its glass is fixed when it is shown, so the settings popover is dismissed and shown again. |
| iOS 13 and later | The window's `overrideUserInterfaceStyle` is set through KVC behind `respondsToSelector`, so stock bars and tables follow the chosen mode. |

## 6. Drawing and cost
- Every image is drawn once and cached (`PTArt` dictionary). Icons are drawn at the size used (29, 36, 40 pt). Row backgrounds are one 40x44 resizable image per row position.
- No image is drawn per row while scrolling. No `layer.shadow*` and no `cornerRadius` on scrolling views. The only `cornerRadius` uses are the static badges of the empty page and the swatches of the settings popover.
- `PTPopoverBackgroundView` draws in `drawRect:` once per presentation.
- iOS 7 and later: nothing uses a post-iOS 6 call without a `respondsToSelector` or KVC guard (`-Werror=unguarded-availability` enforces it for the armv7 build).

## 7. Preview and check
Launch images (light mode: stock bar over the white master and the grouped background) and a preview sheet of the recipes, on the Mac, no device:

| Command | Output |
|---------|--------|
| `xcrun clang -fblocks -w -framework CoreGraphics -framework ImageIO -framework CoreFoundation tools/make_art.c -o make_art` | tool |
| `make_art sheet sheet.png` | every recipe at 2x |
| `make_art launch assets/art/build` | `Default-Portrait~ipad.png` (768x1004), `Default-Landscape~ipad.png` (1024x748) |

## 8. Not verified without the device
1. Whether iOS 6 passes a `UITableViewHeaderFooterView` (or a view with a `UILabel`) to `willDisplayHeaderView:`. If not, section headers stay slate blue on the dark rows.
2. Whether the white mask of the gear and the bordered "Servers", "Sessions" buttons look right on `UIBarStyleBlack` in iOS 6.
3. The dark keyboard and key bar colours against the real `UIKeyboardAppearanceAlert` keyboard (not measured: need a capture).
4. The black popover: arrow, shadow and content corners.
5. Grouped session rows at 64 pt: the dot and icon positions against the real rounded cell edge.
6. The empty page spacing in portrait and landscape.
7. arm64 build on iOS 7 and later: not built here, only reviewed for guarded calls.
