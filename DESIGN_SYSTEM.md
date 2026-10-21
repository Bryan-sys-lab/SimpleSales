# Duka POS design system

> The values below are the ones the app renders with. Every colour, size and
> spacing step here is read out of `duka_pos_app/lib/theme/`, and every one of
> them is asserted in `duka_pos_app/test/theme/`. A number in this file that
> the code does not hold is a bug in this file.

## 1. Product direction

- **Product**: Duka POS (SimpleSales)
- **Surface**: offline-first mobile/native point-of-sale app
- **Platforms**: Android and iOS
- **Users**: shop owners and cashiers working quickly at a counter, on budget
  phones, often one-handed and often in a hurry
- **Main goal**: make selling feel immediate, and make inventory and reporting
  feel trustworthy
- **Design concept**: **the till as a dark instrument panel** — the shop's own
  light is off and the screen is the only light source, so every surface is a
  cool near-black that steps *up* with elevation rather than down with shadow;
  one saturated emerald is the only colour on screen and it belongs
  exclusively to the action you take; large left-aligned titles sit directly on
  the canvas the way iOS large titles do, with no coloured chrome bar stealing
  the top of the screen
- **Surface profile** (the ui-ux-kit routing vocabulary): **mobile / native**,
  with a dashboard and an analytics surface in the app. Every screen is judged
  against a thumb on a 320dp phone at 200% text before anything else.

### The one rule the palette is built to serve

**One saturated thing on screen, and it is the thing you press.** The emerald
belongs to the sell ball, the M-Pesa button, the selected state, and the figure
that matters. It is never a container, never a card, never an app bar, and
never decoration. A colour spent on chrome is a colour that has stopped
meaning "do this".

## 2. Brand and voice

- Style: cool, practical, calm, high-clarity
- Voice: plain and reassuring; direct verbs — "Add product", "Adjust stock",
  "Charge KSh 1,240"
- Errors: say what happened **and what the person can do next**; never expose
  exception text. An error that repeats the field's own label says nothing the
  person did not already know.
- Empty states: explain the next useful action, not just "No data"
- Success states: confirm the completed action and the amount or reference
- A dead end is a missing feature. Every failure screen offers a way forward:
  a retry, or a way to get the diagnostics to whoever can help.

## 3. Colour tokens

Tier 1 (`lib/theme/primitives.dart`) is the **only** file in `lib/` allowed a
colour literal. Tier 2 (`lib/theme/app_colors.dart`) is the semantic tier;
widgets read it through the asserting `AppColors.of(context)`.

| Role | Token | Light | Dark | Use |
|---|---|---:|---:|---|
| Canvas | `canvas` | `#F2F4F7` | `#0B0F14` | The page behind the cards |
| Surface | `surface` | `#FFFFFF` | `#151A21` | Cards, forms, navigation |
| Sunken | `surfaceSunken` | `#E8ECF1` | `#070A0E` | Wells, chips, input fields |
| Ink | `onSurface` | `#2D2A26` | `#F2F5F8` | Body text. **Also the launcher icon plate** |
| Secondary ink | `onSurfaceVariant` | `#414954` | `#C4CDD8` | Supporting text |
| Muted ink | `onSurfaceMuted` | `#5C6673` | `#97A3B2` | Metadata |
| Accent | `accent` | `#1B6B3A` | `#4ADE7E` | The action spine. **Also the brand ink** |
| On accent | `onAccent` | `#FFFFFF` | `#2D2A26` | Text on the accent |
| Accent container | `accentContainer` | `#E4F3E9` | `#163A22` | Tonal selection, focus, splash |
| Success | `success` | `#1A7A3A` | `#5CE68A` | Status text, with a word and a glyph |
| Success container | `successContainer` | `#E4F3E9` | `#123520` | The quiet green status pill |
| Warning | `warning` | `#8A6508` | `#FFB84D` | Low stock, attention |
| Danger | `danger` | `#C0392B` | `#FF6B5B` | Errors, destructive actions |
| Info | `info` | `#1A6BAA` | `#6AB0F5` | Neutral information |
| Outline | `outline` | `#DCE1E8` | `#2E3742` | Hairlines. Decorative, below 3:1 |
| Meaningful boundary | `outlineStrong` | `#6B7480` | `#606B7A` | Input edges. Clears 3:1 |

**The ramp is COOL.** A warm sepia ramp pulls the eye toward the paper instead
of toward the numbers, and it makes every saturated colour on screen look
dirtier than it is. The night ramp runs from a near-black with a blue cast
(`#070A0E`) up to a cool off-white (`#F2F5F8`), so **elevation is read as
luminance**: a surface gets *lighter* as it comes forward, rather than a shadow
being smeared over a dark page. The light theme is a cool near-white canvas
(`#F2F4F7`), not cream — a tinted canvas carries its hue through every surface
above it, and cream is the hue that makes a green accent look like moss.

**Two values are PINNED and must not drift**: the light `onSurface` `#2D2A26`
is the launcher icon's plate, the Android `brand_ink` colour resource, the
splash background and the brand mark's ink; the light `accent` `#1B6B3A` is
painted into the launcher icon and the brand artwork. Changing either in the
theme without regenerating `assets/branding/` is how an app ends up with two
logos. See `assets/branding/generate_launcher_icon.py`.

**Payment identities** (somebody else's brand, used only for the payment-mix
ring, which is a *graphical object* and so is held to 3:1, not 4.5:1):

| Tender | Light | Dark |
|---|---:|---:|
| M-Pesa | `#009C4E` | `#00A651` |
| Airtel | `#EC1C24` | `#EC1C24` |
| Equitel | `#0066CC` | `#3E90E8` |
| Cash | `#5F6873` | `#8E97A3` |

Each identity has a value per appearance, because a provider's logo colour is
not the colour that survives a dark surface. The legend names every slice, so
colour is never the only channel — and that is not a licence to draw a slice
the eye cannot find.

**Rules**: colour is never the only status signal — pair it with a word, a
count, an icon or a shape. Dark is designed, not inverted. Body and supporting
text clears 4.5:1; graphical objects and meaningful boundaries clear 3:1.
Every pair is measured in `test/theme/contrast_test.dart`.

## 4. Typography

Plus Jakarta Sans, bundled as a variable font (never `google_fonts`, never a
network fetch). Tabular figures are on **every** role, so a number can appear
anywhere without someone remembering to opt in.

| Role | Size / line / weight | Use |
|---|---|---|
| `displaySmall` | 28 / 1.15 / 800 | The one number a screen is about |
| `headlineMedium` | 26 / 1.2 / 700 | Screen titles |
| `headlineSmall` | 22 / 1.2 / 700 | Totals, dialog titles |
| `titleLarge` | 18 / 1.25 / 700 | Section headings |
| `titleMedium` | 15 / 1.3 / 700 | Card and list headings |
| `titleSmall` | 13 / 1.3 / 600 | Row headings, the product name in a tile |
| `bodyLarge` | 15 / 1.45 / 400 | Important copy |
| `bodyMedium` | 14 / 1.45 / 400 | Standard labels and rows |
| `bodySmall` | 12 / 1.4 / 400 | Secondary metadata |
| `labelLarge` | 14 / 1.2 / 700 | Button labels |
| `labelMedium` | 13 / 1.2 / 600 | Chips, small captions |
| `labelSmall` | 11 / 1.2 / 600 | The stock count, axis labels |

Every size is a token: a `fontSize: 14` in a feature file is a bug.

**Text must survive 200% scaling.** No fixed heights on anything that holds
text; no `FittedBox` or clamped text scaling to make a label fit. A `Text` with
an ellipsis and no `maxLines` still wraps — `maxLines` is what stops it.

## 5. Spacing, shape and layout

- **Spacing scale** (`AppSpacing`): `xs 2 · sm 4 · md 8 · lg 12 · xl 16 ·
  xxl 24 · section 20`. Tighter than a marketing layout — this is an Operate
  surface, and the steps are spent on data rows.
- **Tap target floor**: 44dp, on every interactive element.
- **Row height**: 44dp as a **minimum**, never a fixed height.
- **Radii**: 4 badge · 8 well · 12 control · 16 card · 24 sheet · pill for
  chips. A card is a surface you point at across a counter, and a soft
  silhouette reads as a panel rather than as a row of data; a sheet is a layer
  *above* the page and is rounder than a card so the two are never confused.
- **Page gutter** (`PageGutter`): a phone gets 12dp of page padding and 12dp
  inside a card; a tablet gets 16 and 16. The depth of a page is the sum of
  the page's padding, the card's border and the card's padding — 33dp of
  nothing before the first word is a tenth of a 360dp screen.
- **Navigation**: one bottom `NavigationBar` on a phone, a `NavigationRail` on a
  tablet. The breakpoint comes from `WindowSizeClass` — the same vocabulary for
  every screen — never from a device check.
- **Motion**: short and functional, and collapsed to nothing under reduced
  motion.

### The app bar is a TITLE, not a band
There is **no coloured app bar anywhere**. The bar is the canvas, the title
sits on it, and the screen's content starts underneath.

A saturated band across the top of every screen spends the app's only accent
on chrome: the eye reads the band as "important" and stops looking for the
thing the screen wants pressed. So the bar is unfilled, and each screen opens
with a `ScreenTitle` **on the canvas** — a large (26/700) left-aligned line, an
optional eyebrow above it, a supporting line below, and at most one action on
the trailing side. It is the shape of an iOS large title, for the same reason:
a screen should name itself in the space it is actually using.

The brand mark lives in the shell's bar, once, and nowhere else. A screen that
opens with a logo has spent its first line on the product instead of on the
shop.

### The bottom bar

The bar is a **horseshoe with a ball in it**: its top edge dips in the middle
(a semicircle — the hollow of an ohm symbol turned upside down) and the SELL
button is a **ball floating in that hollow**, detached from it by an even gap.
It is a shape rather than a rectangle because the sell button is what a
cashier presses forty times an hour, and the eye finds a raised circle faster
than it finds a rectangle.

- The remaining destinations **divide around it**, so the ball is always in
  the middle and each side's items are spread evenly within their half — the
  same shape whichever role is signed in.
- The mark is a **glyph on a solid accent circle**, not an image clipped to a
  circle. A square image inside a circular button is a square inside a
  circle, and it reads as a mistake. The ball is solid — one colour — with an
  accent-coloured glow, because the one saturated thing on screen is one
  colour, and a second green in the same ball reads as a printing error.
- The ball's press scales it to 96% for the shortest beat on the motion scale.
  The shortest feedback in the app: a ball tapped constantly cannot afford an
  animation worth waiting for.
- **The labels are MEASURED, not estimated.** Each destination measures its own
  cell and takes the full word when it fits and the short one when it does not.
  The bar used to estimate the room per cell and was about ten pixels
  generous, which nobody could see while the label was ellipsised and became a
  wrapped second line the moment the ellipsis came off. A widget that knows its
  own width does not have to guess. The full name is always what a screen
  reader announces.
- **Support is a floating bubble, not a tab.** It left the bar (which took a
  slot from the symmetry) and became a 44dp bubble in the corner, the way
  every website's help widget is — a person who needs help wants to say
  something now, not browse to a tab. It is a leaf: it reads nothing,
  subscribes to nothing, and never rebuilds the page behind it.

### The camera screen

A near-black instrument panel with the camera as the hero: a reticle drawn
over the feed, the area around it dimmed so the eye goes to the frame and
nowhere else, and quiet controls — a torch toggle, and a way to type a code
that will not scan.

**It never stops to ask.** The screen used to treat a scan as the END of the
session: the first code stopped the camera, popped the route, and handed one
result back. The till added that one item to the cart, and to scan the next
one the cashier had to press the scan button again, wait for the camera, and
aim at the next label. A till that stops and asks permission between every
item is a till that cannot scan a trolley.

So the camera keeps looking. A code is read, confirmed, handed to the till, and
the camera carries on reading the next one. The only thing between two scans
is a **re-read guard** — a short, deliberate debounce — whose whole job is to
stop the SAME label being charged for twice while it is still in frame.

"Try again" exists only where it is a real error: the camera was refused, the
camera cannot be opened, or the camera stopped decoding. A scan is not an
error.

The delivery is a **session**, not a return value: a route that pops a value
can only pop once, and the screen does not close when a code is read.

### Photographs

Two photographs, two rules, one store.

- The **account avatar** is a FILE, not a column: one avatar per DEVICE, not
  per workspace, because an owner runs several shops on one handset and is the
  same person in all of them. It is drawn from the file, and a photograph
  that has moved or been deleted reads the same as never having had one —
  initials, not a broken image.
- Tapping the avatar **opens the photograph, whole, over the screen**, in a
  dialog. The avatar is a 96dp circle and the photograph is up to 512px; the
  owner who wants to SEE the photograph wants all of it at once, and wants to
  be back on the profile a moment later. The app has one navigation system and
  it is go_router; a dialog is the one thing that opens without touching it.
- A **product photograph** is stored under a folder per workspace, so product
  #5 in shop B cannot overwrite shop A's. The path is RELATIVE, because the
  documents directory differs between phones — a photograph restored onto a
  different handset, where the image files were not part of the backup,
  resolves to nothing and the caller draws its placeholder rather than an
  error box.
- The store creates the file's **whole** folder before writing, not the first
  segment of it. A missing folder is a failed write, and a failed write is
  how a photograph ends up "saved" and never seen.

### The ledger, and the record behind a row

A ledger row is a SUMMARY: an amount, a relative time, a method. It is what a
shopkeeper scans down. But "what happened at 14:32" cannot be answered by a
summary, so **every row opens a record** that says:

- **WHEN** — the exact instant, not "2 hours ago". A relative time is right in
  a list you scan and wrong in a record you are asked about.
- **WHERE** — the shop the sale was rung in. A till can be shared, and a sale
  is accountable against a place as well as a person.
- **HOW** — the method, and what actually moved: the M-Pesa reference, or the
  cash tendered and the change given. "Cash" alone does not say whether the
  drawer balanced.
- **WHO** — the member of staff who rang it, and the audit line that recorded
  it. Two names, because they are two different claims: the sale says who rang
  it, the audit says who wrote it down. Gated by the same permission as the
  seller column on the row.
- **WHAT** — the lines, so a total can be checked against the shelf.

A row that is not tappable is a dead end: the person standing in front of the
till has to write the answer down instead.

### The welcome line

A SENTENCE, and only a sentence: "Good morning, Wanjiru."

It used to be "Good morning, Wanjiru · Cashier · you" — the greeting, the name,
the role and the scope run together with dots. That is a database row printed
as a welcome, and it read as robotic because it was one.

The facts live where each of them belongs: the NAME in the welcome, because a
greeting that does not say who it is for is not a greeting; the ROLE in the
shell's bar, beside the way out of the session; the SCOPE on the figure it
qualifies — "Sales today · the whole shop" — because it is a statement about
whose takings are on screen, not about the person reading them. And the scope
is localised: it used to be the English literals "the shop" and the staff's own
name, in an app that localises everything else.

### Permissions

A permission asked for at the moment it is needed is a permission prompt that
arrives in the middle of a sale: the shopkeeper opens the scanner and gets a
system dialog about the camera while a customer is standing at the counter.

So the app asks **once, in one place, after the walkthrough** — where the
owner is not in the middle of anything, and where they can read what each
permission is FOR before answering.

| Permission | For | Declared | Asked |
|---|---|---|---|
| Camera | Scanning barcodes; photographing a product | Android `CAMERA` (camera is `required="false"`), iOS `NSCameraUsageDescription` | In the step, and again by the scanner if it is refused |
| Bluetooth | The receipt printer | Android `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (legacy pair capped at API 30), iOS `NSBluetoothAlwaysUsageDescription` | In the step, and again when a printer is paired |
| Photos | Choosing a product photograph | iOS `NSPhotoLibraryUsageDescription` | By the system photo picker — no permission at all |

**NOT asked, and deliberately so.** Notifications — the app has no
notification feature, and a permission for something the app does not do is a
permission the owner refuses for nothing. Location — the app never derives a
place from a radio. Storage — the photo picker needs none.

**The step cannot block.** Every permission on it is optional and so is the
screen: "Continue" is there whatever the answer was. A shop with a wedge
scanner and no camera is a perfectly good shop, and a till that cannot sell
because nobody granted a permission it does not need is a broken till. The
screen says so in words, because a screen of system prompts with no
reassurance reads as a wall.

**It is admin-only, and it is asked once per workspace.** The copy is
addressed to whoever set the shop up, and a cashier goes straight to the shop.
A permission the owner has already answered — granted OR refused — is a
decision, and a till that asks again every morning is a till people learn to
dismiss without reading. The screen stays reachable from Settings for a till
that gains a printer later.

**"Allow" and "Open Settings" are different buttons.** A permission refused
with "don't ask again" can only be undone in the system Settings screen, so
the button says so rather than promising to ask again and wasting the tap.

**The channel is owned outright.** The `permission_handler` pub package would do
this in a few lines, but the printer's Bluetooth permission is already owned in
`PrinterChannel.kt` for the same reason — the package it wanted was
discontinued, and a till should not carry a dependency graph for one question.
The camera half is a small `PermissionChannel.kt`; the Bluetooth half is NOT
duplicated, because the printer channel already owns it and two channels
disagreeing about the same permission is a bug waiting to happen.

### The profile is editable

A profile that cannot be edited is a photograph of the past. An owner whose
name changed, or whose shop was renamed, had no way to correct it, and the
screen said so in its own header: it "deliberately does NOT offer editing the
identity".

That was right about the **email** and wrong about the rest:

- The **name** and the **shop name** are local facts about this till, and they
  are edited directly.
- The **email** is edited too — the address is where the PIN-recovery codes go,
  and a typed-in address is not a verified one, so changing it clears the
  verification flag until a code is sent to the new address and accepted. The
  sheet says that, before the Save button, not after it.
- The **PIN** is NOT editable here. It has its own flow, with its own
  confirmation and its own lockout, and a profile edit is not a way around it.

### The account deletion

The promise the owner is asking for is "we are not left with usable data even
if we backed up the system", so the deletion goes the other way round from a
`DELETE`: every personal field is overwritten with AES-256-GCM ciphertext
under a key derived from the admin PIN, the key material is destroyed, and the
database is vacuumed so the plaintext is not sitting in free pages. The books
survive — the takings, the stock, the tax rates — because those are the shop's
rather than its people's.

Three things about the flow are load-bearing, and each one was a bug:

- **It never opens a browser.** Ending the identity provider's session means
  opening the SYSTEM BROWSER at the provider's logout page, and on a Keycloak
  deployment that lands the owner on a **LOGIN screen — with a "Register"
  option beside it** — in the middle of deleting their account. The session is
  torn down LOCALLY instead.
- **The remote delete happens while the session is still alive.** The delete
  request carries the bearer token, and a deletion sent without it is a request
  the server is entitled to refuse. The order is: erase locally, delete
  remotely, THEN clear the session.
- **The cleanup cannot abort the deletion.** The personal data is erased
  BEFORE the key material is destroyed, so a failure in the cleanup used to
  leave the owner with a blanked app, no receipt, and an error saying
  "nothing was changed" — which was a lie, because everything had been. Every
  cleanup step is best-effort and the whole thing is wrapped.

**The local cashier logins are deleted too, with their own confirmation.** The
erasure seals them, which makes them unusable; deleting them removes the
rows, and with them the PIN hashes that would otherwise still sit in the file.
The two are different promises — a till whose cashiers can still sign in is a
till somebody else can use — so the owner is asked, in words, and the answer
decides.

### The status strip

A till's state changes without anybody asking it to: the network drops, the
backup falls overdue, the shop's account deletion could not reach the server.
None of those is worth stopping a sale for, and all of them are worth knowing
about.

So they are a **strip**: one line, under the app bar, on every screen, saying
the thing that is wrong — and **nothing at all** when nothing is wrong, so the
content does not move. It never blocks and it never asks.

It is not the dashboard's job: a dashboard is one screen of five, and a
cashier is on the SELL screen, and a till that cannot reach the server is
exactly where the owner needs to know.

### The three screens a till shows

- **Success.** The end of a sale gets a screen, not a snackbar: the amount, the
  method, the change, and one button that starts the next sale. A snackbar
  says "done" and vanishes in four seconds, and it overlays the till — the
  cashier is looking at the money they owe, not at a card in the corner. The
  change has to be HANDED OVER, and the amount has to be READ, and both take
  longer than a snackbar lives. It is a **sheet**, not a route: it is the end
  of a transaction, not a place.
- **Error.** One component, used in ten places: what failed, in words, and the
  one action that can fix it. A spinner that never stops is the least honest
  thing a till can show — it says "wait", when there is nothing to wait FOR.
- **Empty.** "Nothing here yet" and "nothing matches this filter" are
  DIFFERENT screens, with different actions: the first invites the user to
  create something, the second invites them to undo the filter.

### How an operation says what it did

Every operation that changes something ends on a **screen**, and every
operation that fails ends on a **failure screen**. One pair of functions owns
both, so the outcome is the same everywhere.

Before this, eleven screens reported an outcome eleven ways: some through a
snackbar, some through the *error* helper — so a success and a failure looked
the same — and several with **no failure path at all**, so a failed import or
a failed backup was silent. A failure nobody acts on is a failure that happens
again.

| Operation | Success | Failure |
|---|---|---|
| Product saved / updated | "Product saved" + the name | The form's own inline error, which is right for a validation problem |
| Stock adjusted | "Stock updated", or "saved on this phone only" when the server refused | "The stock could not be updated" |
| Export (encrypted / workbook) | "Export ready" + what was made | "The export failed", with a retry |
| Restore a backup | "Backup restored" + how many products | "That file is not one of ours" — and **no** "Try again", because a malformed file will be malformed again |
| Import | "Import complete" + how many products + which barcodes were refused | "The import failed", with a retry |
| Backup | "Backup made" | "The backup failed" + what it means for the data on the phone |
| Erase the local backups | "Backups erased" + **how many files** | "Some backups could not be erased" + why the key is gone anyway |
| Cashier added / removed, PIN reset | "Cashier saved" / "Cashier removed" / "PIN reset" | The same title, in the failure's words |
| Manual sync | "Sync finished" + what it pushed | — |
| Identity verified | "Identity verified" | — |
| Profile edited | "Details saved" + the name | "The details were not saved. Nothing was changed." |
| Import row repaired | "Row repaired" + the product | "The row was not repaired" |
| App update | The OS takes over | "The update was not installed" |
| **A sale** | "Sale recorded" + the amount + the change | The sale is committed, so a failure here says *what to do about it*, not that it failed |

Two rules the pair follows:

- **A failure is a sheet, not a toast.** A toast that disappears on its own is
  a failure nobody acts on. And the error is never the exception's text: an
  exception is untranslatable, unactionable, and it leaks file paths and ids
  to whoever is standing at the till.
- **"Try again" appears only when a retry can help.** A file that is not one of
  ours will not become one of ours, and a button that cannot help teaches the
  owner to stop reading the buttons.

### The vendor's mark

The app's footer used to say "Powered by Nerva" in the app's own typeface.

That is a vendor's name set in somebody else's face, and it reads as a line of
the app's own copy rather than as a brand. So the footer shows the vendor's
**mark** — a chrome wordmark with a blue "A" — and the words beside it shrink
to the role they play: "Powered by".

The master is a generated image, so the mark is **rendered from it by a
script**, the same way the launcher icons are
(`assets/branding/generate_nerva_logo.py`). Two variants come out of one
master, because a logo has to work on both of the app's surfaces:

| Variant | For | What it is |
|---|---|---|
| `nerva_wordmark_dark.png` | The night theme's near-black surfaces | The master, with its black ground removed. The surfaces are near enough to the master's own background that the metallic gradient survives intact |
| `nerva_wordmark_light.png` | The day theme's near-white surfaces | The same wordmark in the app's own ink, with the blue deepened for contrast — silver on white is a ghost |

The crop is **measured**, not guessed: the master carries a light flare and a
tagline under the wordmark, and a tagline is unreadable at the height a footer
can afford.

The mark is sized by **height**, so all four places it appears are the same
size, and the width follows the asset's own aspect ratio so it is never
stretched. The attribution is one **semantics node** — "Powered by Nerva" —
so a screen-reader user hears a sentence, not a word and then a name.

### The till page
The catalogue and the cart, and how they sit together:

- **Wide** (a tablet, a landscape till): side by side. The cashier looks at one
  and touches the other.
- **Phone**: stacked, catalogue above, cart below — the thumb reaches the
  bottom of the screen, and the bottom of the screen is where the money is.
- The pane layout **divides a height**, so it must be given a bounded one. A
  `Column` hands its non-flexible children an *unbounded* height; put the pane
  layout in an `Expanded`. An unbounded height in a grid is a grid with an
  infinite scroll extent, which is a crash in the sliver's index arithmetic.
- **The cart's share of the page grows with the text.** The cart holds the one
  part of the till that cannot scroll away — the total, and the button that
  takes the money — and that block is measured in lines of text. Splitting the
  page evenly is what overflowed: the pinned block outgrew its share, and the
  overflow came out of the money and the payment button.
- The two payment methods are **M-Pesa, filled** (the path almost every
  customer takes, and the one green thing on the till) and **offline
  payment, quiet**. Two saturated buttons on one screen would spend the
  accent twice and leave the eye with nothing to choose. Their labels are
  never truncated: at a large text scale a label wraps and the cart's share
  of the page grows to make room.
- The search field and the scanner share **one row** — two rows of controls
  before a single product is a fifth of the screen spent.

### Grids size their cells from the content

A cell's height is computed from the text it holds, at the text scale in force.
A ratio of the width is a *guess* about how much text a cell holds, and a guess
is wrong the moment the text scale moves — in the direction that breaks the
layout. The price and the stock count are **measured**, not assumed: a price
that wraps to two lines at 150% text needs two lines of room, and a price is
never truncated to make it fit.

### Charts

One line-chart implementation, used by the dashboard and by analytics, and it
answers to three rules:

- **The line is SMOOTH, and MONOTONE.** The curve is a monotone cubic
  (Fritsch–Carlson) through the readings: it passes through every reading and
  never leaves the range of the data. A Catmull-Rom spline through noisy
  readings invents a peak between two points and swings past the ends — a chart
  of a shop's takings that invents a peak is not smoothing the data, it is
  misreporting it. The shape gets softer; the values do not move.
- **The axis reads at an INTERVAL, not one label per reading.** A trading day
  is twenty-four hours, and twenty-four labels across a 320dp phone is a row of
  collisions rather than an axis. The floor is three readings — morning,
  midday, evening — and a narrower phone or a wider label widens it further.
  The interval is never *lowered* by a wide screen.
- **A tap reveals a reading.** The whole plot is the target, not one point: a
  finger between two readings still selects the nearer one, and a drag slides
  the selection along the chart. The revealed reading is announced, and the
  peak is stated in words on the card beside it — so the answer is never only
  in the picture.

## 6. Components

- Buttons: Material 3, 44dp minimum target, `MaterialTapTargetSize.padded`.
  A **filled** button is the accent — the one green thing on the screen. A
  **raised** button is the quiet secondary: a raised surface, not a second
  green field.
- The floating action button is **not** the accent. A green button beside the
  green sell ball spends the colour twice on the same screen.
- Inputs: a field is a **well**, not a box drawn around a hole — the fill is
  a step darker than the card it sits on, 12dp radius, explicit labels,
  correct keyboard types.
- Cards: a cool surface, a hairline edge, 16dp radius. Separated by depth and
  a hairline, not by a wall of borders and not by a shadow — on a near-black
  canvas a 1px edge draws the boundary and a shadow alone does not.
- **Selected state** is a **solid accent fill** with the accent's own ink on
  top, never a tonal wash of the same hue. A wash reads as "slightly on" and
  cannot be found at a glance — which on a till filtering the day's takings is
  the difference between a filter and a decoration.
- Rows: a **round tonal badge** on the leading edge, the thing it belongs to
  next to it, the value on the trailing side. A circle reads as a MARKER and a
  rounded square reads as a FIELD.
- Status: label + icon + count, never colour alone. Every stock row wears its
  state — the green is a deep quiet wash and the amber is bright, so the row
  that needs attention is the row the eye lands on.
- A stat tile is LABEL / VALUE / **DELTA**: a muted label, a large figure, and
  a small change with a direction. The delta carries a **glyph**, not just a
  colour, so a rise and a fall are still told apart in greyscale.
- Icon-only controls: always a tooltip and a semantic label
- Money: always `formatMoney()` from `lib/utils/money.dart`, always tabular
- Every data view has all three states: loading, empty, error — and the error
  is recoverable. A loading state is a **skeleton shaped like the result**,
  not a spinner over an empty box.
- One node for a thing a person reads as one thing: a product tile is a single
  semantics node ("Kenyatta bread, KSh 60, 12 in stock, adds it to the cart"),
  not four
- The sign-in PIN is a **field with the system's own numeric keyboard**, not a
  keypad drawn by the app: it is faster, it is already the right shape for a
  number, it comes with the owner's own input method, and a scanner or a
  keyboard case can fill it

### The shared component set

| Component | File | What it decides |
|---|---|---|
| `ScreenTitle` | `ui/components/screen_title.dart` | The large canvas title: eyebrow, title, supporting line, one trailing action |
| `SurfaceCard` | `ui/components/surface.dart` | Every raised surface: hairline, 16dp radius, generous padding |
| `StatTile` | `ui/components/surface.dart` | LABEL / VALUE / DELTA, with the delta's direction |
| `IconBadge` | `ui/components/surface.dart` | The round tonal marker on a row's leading edge |
| `SelectablePill` | `ui/components/controls.dart` | A filter chip: solid accent when selected, sunken well when not |
| `SegmentedChoice` | `ui/components/controls.dart` | A segmented control: solid accent when selected |
| `SearchField` | `ui/components/controls.dart` | The sunken search well |
| `StatusChip` | `ui/components/status.dart` | The state pill: tone, word, glyph |
| `EmptyStateView`, `ErrorStateView`, `SkeletonList` | `ui/components/states.dart` | The three states every data view owes the user |
| `SettingsInfoRow` / `NavRow` / `SwitchRow` | `ui/components/controls.dart` | A settings row, with the round badge |

## 7. Accessibility baseline

WCAG 2.2 AA. The matrix that proves it is `test/support/harness.dart`:
320 / 360 / 412 / 800 wide, text at 1.0 / 1.3 / 2.0, light and dark, bold
text, RTL, reduced motion. A screen that overflows at any of those is a
screen that clips for a real person.

- Every interactive target is at least 44dp.
- **A value a person must read is never truncated.** No `TextOverflow.ellipsis`
  on a name, a price, a total, a count or a status. Text wraps and the row
  grows. The only reviewed exception in the app is a product name in a **grid
  tile**, whose cell height is a fixed ratio of its width: there is no cell
  height that fits a 120-character name, and `maxLines` *without* an ellipsis
  would drop the overflow lines silently, cutting the name mid-word with
  nothing saying text was lost. The ellipsis IS that signal, and the tile's own
  semantics label announces the full name. The exceptions live in
  `duka_pos_app/tool/design_gate_exceptions.txt`, one line each, with the
  reason.
- Semantics hints say what the tap **does**, not how to perform it. "Double tap
  to add" repeats what the platform already announces and says nothing about
  what the tap is for.
- Payment and sale outcomes are visible and announced.

## 8. Implementation source of truth

| Thing | File |
|---|---|
| Raw values (the only colour literals) | `duka_pos_app/lib/theme/primitives.dart` |
| Semantic colours | `duka_pos_app/lib/theme/app_colors.dart` |
| Type, spacing, shape | `duka_pos_app/lib/theme/typography.dart`, `app_spacing.dart`, `app_shapes.dart` |
| Motion | `duka_pos_app/lib/theme/app_motion.dart` |
| Theme assembly | `duka_pos_app/lib/theme/app_theme.dart` |
| Shared components | `duka_pos_app/lib/ui/components/` |
| Page layout and the gutter | `duka_pos_app/lib/ui/layout/page.dart` |
| The till page | `duka_pos_app/lib/widgets/sell_page.dart`, `product_tile.dart` |
| The shell and the Omega bar | `duka_pos_app/lib/routing/home_shell.dart`, `shell_nav_bar.dart` |
| Money | `duka_pos_app/lib/utils/money.dart` |
| The contrast and token proofs | `duka_pos_app/test/theme/` |
| The layout matrix | `duka_pos_app/test/support/harness.dart` |
| The design gates (and their reviewed exceptions) | `duka_pos_app/tool/check_design_gates.sh`, `tool/design_gate_exceptions.txt` |

## 9. The gates, and what they are for

`bash tool/check_design_gates.sh` is the machine-checkable half of this
document. It fails the build on a raw colour, a literal radius, duration,
curve, font size or elevation outside `lib/theme/`; on clamped text scaling or
a `FittedBox`; on an ellipsis over a value a person must read; on physical-side
geometry that would not mirror under RTL; on a `FutureBuilder` over a
repository; on `Navigator.push`; on a `GlobalKey` used for identity; and on
imperative haptics.

A gate that needs to bend is **not** silenced — it is **reviewed**: a line goes
into `tool/design_gate_exceptions.txt` with the file, the gate and the reason,
and the reason has to survive the next person reading it.
