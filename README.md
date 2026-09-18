# LinkPure (Swift)

LinkPure's **native Apple-platform implementation**: a macOS menu bar app + iOS (AppIntent).

The rule engine is extracted into the `LinkPureCore` Swift Package — sharing **the same
rule library and the same behavioral spec** with the Flutter version and the future
Android version.

## Installation

| Platform | Available channels |
| --- | --- |
| iOS | **App Store only** (no external channels such as TestFlight) |
| macOS | App Store / Homebrew / direct DMG download — pick one |

- **App Store** (macOS and iOS share the same app record, Universal Purchase):
  <https://apps.apple.com/app/id6753670551>
- **Homebrew** (direct-distribution build):

  ```sh
  brew install --cask rxliuli/tap/linkpure
  ```

- **DMG** (direct-distribution build, Developer ID signed + notarized):
  <https://github.com/rxliuli/LinkPure/releases/latest>

> ⚠️ The direct-distribution build installed via Homebrew / DMG and the App Store build
> have the **same bundle id** (`com.rxliuli.linkpure2`); installing both will overwrite
> each other. Uninstall the other one before switching channels.

Requirements: macOS 15 (Sequoia) or later; iOS 17 or later.

## Why it's organized this way

The core logic (rule engine + 1061 rules) is the only asset; platform integration is
where the platforms differ. So the strategy is:

> **Share the truth (rule data + conformance vectors), not the runtime (code).**

`LinkPureCore` is only about 250 lines, but it is verified by **1053 language-agnostic
vectors** — the same vectors also run against Dart (the reference implementation) and
Rust (an independent implementation).

## Structure

```
linkpure/
├── Package.swift                     # LinkPureCore
├── Sources/LinkPureCore/
│   ├── Rule.swift                    data contract (mirrors shared-rules.json)
│   ├── LocalRule.swift               user rules + import/export exchange format
│   ├── UrlCleaner.swift              rule engine (behavior contract: conformance/README.md)
│   ├── RulesManager.swift            loads the built-in rule library + default redirect following
│   └── Resources/shared-rules.json   vendored rule library
├── Tests/LinkPureCoreTests/          1053 conformance vectors
├── Apps/Shared/                      shared by both platforms
│   ├── AppModel.swift                rule state + testing (macOS additionally has clipboard monitoring)
│   ├── RuleStore.swift               user-rule persistence
│   ├── RuleEditorView.swift          rule editing (macOS sheet / iOS Form)
│   ├── JSONDocument.swift            used for import/export
│   └── CleanURLTextIntent.swift      ★ pure-function AppIntent for Shortcuts
├── Apps/macOS/                       menu bar app (MenuBarExtra + window)
│   ├── MainWindowView.swift          rule management window (NavigationSplitView + Table)
│   ├── SettingsView.swift            settings (⌘,)
│   └── LinkPureApp.swift             scenes / menu commands (FocusedValues)
├── Apps/iOS/                         rule management + usage guide
├── Apps/android/                     native Android implementation (Kotlin / Gradle)
│   ├── settings.gradle.kts           Gradle root (:core is pure JVM / :app added later)
│   └── core/                         the Kotlin port of LinkPureCore
│       └── src/                      ★ the rule library and vectors are NOT copied here;
│                                       build.gradle.kts references the two directories above
├── Scripts/sync-spec.sh              syncs the rule library and vectors from the Flutter repo
└── project.yml                       XcodeGen (macOS / iOS)
```

## Capability differences between the two platforms (important)

| | macOS | iOS |
|---|---|---|
| Automatic rewriting (zero interaction) | ✅ background polling of `NSPasteboard` | ❌ **not allowed by the system** |
| What the user must do | nothing at all | configure a shortcut once, then trigger manually |
| Entry point | always-on menu bar | Control Center / Back Tap / Siri |
| Integration | clipboard monitoring | `CleanURLTextIntent` + Shortcut |

### iOS's shape was **forced by real-world testing**, not chosen

1. **`ControlWidget` (Control Center widget) is not viable.**
   When it runs in the background, `UIPasteboard.general` isn't "denied" — it's **a
   different, empty pasteboard**: `numberOfItems == 0`, and `detectedValues` throws
   `PBErrorDomain Code=4` outright.
2. **`AppShortcutsProvider` doesn't save you either.**
   An App Shortcut can only wrap one of your own intents; it **can't hold a system
   action like `Get Clipboard`** — and the intent itself can't read the clipboard in
   the background.
3. **The only workable approach**: let **Shortcuts read it itself** and pass the
   string in as a parameter — which is why `CleanURLTextIntent` takes a plain string
   in and out and **never touches the clipboard**, and can therefore avoid the
   "allow paste" prompt.

The corresponding workflow (the in-app "How to Use" page walks through it step by step):

```
Get Clipboard (system reads) → Clean URL Text (this app) → [only if the result changed] Copy to Clipboard (system writes) + notification
```

The write-back ("Copy to Clipboard") must be **inside** this `If`, not outside it: iOS
clipboard writes have **no content deduplication**, so writing an unchanged result
would needlessly trigger Universal Clipboard sync and flatten copied rich text into
plain text. `Clean URL Text` itself has no side effects; all the risk is in where this
write-back sits. On macOS the same check guards it (`rewritten != text` in
`ClipboardMonitor`).

## Build and test

```bash
# rule engine: run the 1053 conformance vectors
swift test

# sync the rule library and vectors (the Flutter repo is the single source of truth)
./Scripts/sync-spec.sh ~/code/flutter/LinkPure

# macOS app
xcodegen generate
xcodebuild -project LinkPure.xcodeproj -scheme LinkPureMac -destination 'platform=macOS' build

# iOS app
xcodebuild -project LinkPure.xcodeproj -scheme LinkPureIOS \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Implementation notes (a few easy-to-hit pitfalls)

1. **`\d` / `\w` must be interpreted as ASCII.** Swift's ICU defaults to Unicode
   semantics, but the spec requires ASCII (to match Dart/JS). `UrlCleaner.asciiRewrite()`
   rewrites them into explicit character classes `[0-9]` / `[0-9A-Za-z_]`. The Rust side
   hit the same pitfall.
2. **Rule matching is case-insensitive** (`NSRegularExpression.Options.caseInsensitive`),
   consistent with Redirector; but **parameter-name matching is case-sensitive**.
3. **Parameter removal operates on the raw query string**, not via a `URLComponents`
   round-trip: otherwise it would collapse duplicate parameters, re-encode parameter
   values, and drop default ports.
4. **Parameter names are matched exactly first, then as regexes**: Branch-style `$3p` /
   `$deep_link` literally contain `$`, and treating them as a regex makes them
   permanently fail because `$` is an end-of-line anchor.
5. **`followRedirect` uses an injected `RedirectFollower`**, so network calls never
   enter the golden vectors.
6. **Renaming the app takes more than changing `CFBundleDisplayName`.**
   `PRODUCT_NAME` defaults to `$(TARGET_NAME)` and in turn determines the **`.app` file
   name**, `CFBundleName`, and `CFBundleExecutable`; `CFBundleDisplayName` **only
   overrides the Finder / Home Screen** display name. What it once looked like:

   | Scenario | Key actually used | Wrong display |
   |---|---|---|
   | Finder / iOS Home Screen | `CFBundleDisplayName` | ✅ LinkPure |
   | **System Settings → Login Items** | **`.app` file name** | ❌ LinkPureMac.app |
   | iOS permission prompts / Settings | `CFBundleName` | ❌ LinkPureIOS |
   | Process name | `CFBundleExecutable` | ❌ LinkPureMac |

   So both targets must set `PRODUCT_NAME: LinkPure` explicitly.
   > Note: for a login item that has already been registered, its display name is
   > **cached at registration time** in the BTM database, so even unregister →
   > `lsregister -f` → register won't refresh it; a clean install won't have this problem.
7. **Don't use `NSApp.applicationIconImage` for the menu bar icon.**
   That's the **Finder-rendered** version (the system adds a rounded backing plate
   around it), so the actual artwork comes out about 30% smaller (measured 11.5pt vs
   17.5pt for other icons). You should crop the transparent padding from the original
   artwork and generate a menu-bar-specific image (`MenuBarIcon.imageset`).
   > While debugging this I also hit: an instance launched by the Xcode debugger keeps
   > running the old binary, so changes appear to have no effect — clear out
   > `debugserver` too first.
8. **The UI's "test result" must include the rule-set version in its `task(id:)`.**
   With only `.task(id: testURL)`, toggling a rule on/off doesn't change the URL, so
   the result isn't recomputed and stale output sticks around.

The first 5 are guarded by corresponding vectors in `Tests/LinkPureCoreTests/Vectors/`;
6–8 are UI/engineering-level and are constrained by docs and code comments.

## The macOS app

- Always-on menu bar (`LSUIElement`, no Dock icon)
- Polls `NSPasteboard.changeCount` to monitor the clipboard (macOS allows background
  reads, so the desktop app achieves true "zero-interaction automatic rewriting")
- Writes the rewritten value back to the clipboard + system notification (auto-dismisses
  after 3 seconds)
- Rule list (search / per-rule toggle), URL testing, adding user rules, import/export
- Launch at login: `SMAppService.mainApp` (macOS 13+), reachable from the bottom of the
  main window's sidebar and the status bar menu (also ⌘,)
- Minimum version **macOS 15**: the only reason is `Scene.defaultLaunchBehavior(.suppressed)`
  (used to avoid showing the main window at launch), which is `@available(macOS 15.0, *)`
- **App Sandbox is enabled** (a hard requirement for Mac App Store submission)

### Window UI: hand layout to system containers

The main window deliberately does **not** hand-place a toolbar + divider stack with a
`VStack`; instead each intent is handed to the corresponding system container, which
decides position, size, and interaction:

| Intent | Container | Behavior you get for free |
|---|---|---|
| Switch between "My Rules / Built-in Rule Library" | `NavigationSplitView` sidebar | live translucent material, system column width, `⌃⌘S` collapse |
| Search | `.searchable` | search field in the toolbar, `⌘F`, `Esc` to clear, focus ring |
| Add / Import / Export | `ToolbarItemGroup` | height, spacing, hover, overflow collapse when the window narrows |
| Status | `.navigationSubtitle` | goes into the title bar subtitle |
| 1061 built-in rules | `Table` | click column headers to sort, drag column widths, automatic virtualization |
| Launch at login | `Settings` scene | the settings window |
| Menus / shortcuts | `.commands` + `FocusedValues` | `⌘N` / `⌘I` / `⌘E`, automatically greyed out when the window isn't open |

Four pitfalls hit during real-world testing (all noted in code comments):

1. **`.commands` must be attached to the `Window` scene.** Attached to the `Settings`
   scene, the menu items only exist while the settings window is active — pressing `⌘N`
   does nothing.
2. **The `Settings` scene does not automatically install a "Settings…" menu item for an
   `LSUIElement` app.** The environment's `openSettings()` is fine (the window opens
   normally), but there's no such menu item and `⌘,` does nothing. You have to wire it
   up yourself with `CommandGroup(replacing: .appSettings) { SettingsLink { … } }`.
3. **`ContentUnavailableView` does not fill its container by itself** — it sizes to its
   content. Put an empty state directly into the detail column and the whole column
   (test bar + empty state + status bar) becomes a "content-sized block" centered by
   `NavigationSplitView`, leaving big blank areas above and below. You need an explicit
   `.frame(maxWidth: .infinity, maxHeight: .infinity)`. With data, that spot is a `List`,
   which fills naturally, so only the empty state shows the problem.
4. **The settings entry point can't live only in the status bar menu.** This is a menu
   bar app and users habitually click the status bar icon; while the main window is
   open, settings should be reachable in the window too (bottom of the sidebar, where
   app-level controls go on macOS).

### iOS window UI: conventions are the opposite of macOS

Same data model, but "native" is not the same thing on the two platforms:

| | macOS | iOS |
|---|---|---|
| Secondary information (e.g. rule id) | `.help()` hover tooltip | **not shown** (`.help()` is dead on iPhone) |
| Go to detail | double-click (`primaryAction`) | **tap the whole row** (swipe-only means hidden; nobody will try) |
| Long lists | must truncate/virtualize yourself | `List` is lazy already, **don't** truncate |
| Empty state | `ContentUnavailableView` fills | same component, but clear `listRowBackground` |
| Operation result feedback | bottom status bar | **must be `.alert`** (the built-in rule library has 1061 rows; a message appended to the end of the list is invisible) |
| Delete | select → toolbar / context menu / Delete key → **delete immediately** + 8-second "Undo" in the status bar | swipe → **delete immediately** + 6-second undo bar at the bottom |
| Row context/long-press menu | ✅ `contextMenu(forSelectionType:)`, acts on the **selection set** | ❌ **not implemented** |
| External links / rule-library attribution | `Links` group in the settings window | `About` + `Rules` groups at the end of the "How to Use" page |

> **About "About"**: macOS has the system About panel (`.appInfo` untouched), so the
> version number isn't duplicated; but links can't go in the Help menu — this is an
> `LSUIElement` menu bar app that **is almost never in the foreground**, so app-level
> menus (including Help) are basically invisible to users. The settings window is the
> one entry point both can reach. iOS has neither a settings page nor a system About
> panel, so the version number + links can only go after "How to Use" (Android uses an
> overflow menu + a separate page, the Material idiom).
>
> The URLs must stay consistent across all three platforms: on the Swift side in
> `Apps/Shared/AboutContent.swift`, on the Android side in `AboutScreen.kt`. **That
> rule-library attribution is an LGPL-3.0 licensing requirement** — writing it only in
> the repo README means users who installed the app can't see it.

> **Why iOS has no long-press menu but macOS does**: it's not "different style", it's
> **whether there's multi-select**. macOS's menu takes the selection set (`Enable` /
> `Disable` apply to all selected, and the delete label is `Delete N Rules`), making it
> a genuine "context" menu; iPhone has no multi-select, so such a menu would just be a
> dumping ground of duplicate actions (Edit / Enable / Delete are already handled by
> tapping the row / the trailing toggle / swipe respectively). Android follows the same
> rule (also single-select).
>
> The cost: on mobile the "get the regex of a built-in rule" capability is left to
> **selecting text to copy** (built-in rules are read-only and can't open the editor),
> so those texts enable `.textSelection(.enabled)` / `SelectionContainer`. macOS's
> `Table` cells don't support text selection, so it keeps the `Copy Regular Expression`
> menu item.

Neither platform confirms twice:

- **macOS**: confirmation is reserved for operations that **can't be undone** (Safari
  clearing history, closing an unsaved document), whereas deleting a rule can be
  recovered with a single array insert. Finder / Xcode / Mail / Notes don't ask either
  when deleting.
- **iOS**: swipe-to-delete never confirms anyway (Mail / Reminders / Messages / Files
  don't ask), and iOS's answer to accidental deletion is **undo**, not confirmation —
  confirmation only helps with "a slip of the finger", not with "picked the wrong one".
- There's another iOS side effect: a `Button(role: .destructive)` inside `.swipeActions`
  makes SwiftUI **optimistically** swipe the whole row away (it assumes the row is about
  to disappear); while confirming, the data hasn't changed, so the row comes back when
  List redraws — that "disappears then comes back".

**Deliberately not wiring up `UndoManager`** (no undo registration, no Edit > Undo
integration): that machinery carries a fair number of invariants to maintain (undo/redo
must register with each other in both directions, the interaction with `groupsByEvent`,
index drift when reversing operations), and all it buys is one entry point — "⌘Z" —
which happens to be **the least discoverable** one. Here we use a visible banner instead
and don't touch `UndoManager` at all. The only extra cost on macOS is that for those 8
seconds the status bar's "Undo" button carries `.keyboardShortcut("z")`; once the banner
is gone, so is the shortcut, and it won't steal the text field's own ⌘Z.

Undo must insert the rule back at its **original index**: the rule set is ordered, and
the order affects which rule matches.

Row layout: the regex takes two lines (however you truncate it, one line doesn't tell
you which rule it is), the replacement target takes one line and truncates **from the
middle** (`https://addons.mozilla.org/en-US/…addon/$1/` has both ends meaningful). A
single toggle goes at the trailing edge, consistent with "Settings"; putting it in front
would fight the body text for the left edge and make the column of text ragged.

### About the sandbox

Verified: **the sandbox does not affect clipboard polling** (the Flutter version was
sandboxed too). The entitlements only need:

```xml
com.apple.security.app-sandbox                        = true
com.apple.security.network.client                     = true   <!-- followRedirect -->
com.apple.security.files.user-selected.read-write     = true   <!-- import/export -->
```

Side effect: under the sandbox you can't read other apps' preferences, so the two "scan
plist files" steps in rule migration get denied (it degrades to checking only
`UserDefaults`). That's actually correct — in the real upgrade scenario the native and
Flutter versions **share a bundle id, and thus the same container**.

> Enabling the sandbox moves the rules file from `~/Library/Application Support/` to
> `~/Library/Containers/<bundleID>/Data/Library/Application Support/`, so existing
> dev-time data becomes unreadable.

## Data and storage

### Rules live in a file, not UserDefaults

```
~/Library/Application Support/LinkPure/rules.json
```

```json
{ "version": 1, "rules": [ { "rule": {...}, "enabled": true, "testUrl": "..." } ] }
```

**Why not `UserDefaults` (a pitfall we hit)**: it's **scoped by bundle id**. During
development, just changing the bundle id once is equivalent to a brand-new empty store;
the same goes for upgrades/renames/multiple environments coexisting. The symptom was
"the rules are empty every time I open it", and **with no trace**. A file path is
independent of the bundle id and is also easier to back up, migrate, and debug.

> Decoding accepts both an object with `version` and a **bare array** (a shape that
> appeared historically).

### Migrating rules from the Flutter version

On release, the native version **replaces** the Flutter version on the App Store (same
bundle id), but the two store their data under different keys:

| | Location |
|---|---|
| Flutter version | `UserDefaults` key `flutter.local_rules` (a JSON **string**) |
| Native version | `Application Support/LinkPure/rules.json` |

So on first launch (when the local rules file doesn't exist), it **automatically
migrates** the old data, trying sources in priority order:

1. `UserDefaults.standard[flutter.local_rules]`
   — applies to both platforms; on iOS with a shared bundle id the container is shared,
   so an upgrade replacement hits it directly
2. `~/Library/Preferences/<legacyID>.plist` (macOS only)
3. `~/Library/Containers/<legacyID>/Data/Library/Preferences/<legacyID>.plist` (macOS only)

`<legacyID>` is tried as `com.rxliuli.linkpure2`, then `com.rxliuli.linkpure`. Migration
is **idempotent**: once the local file exists it goes through the load path and won't
migrate twice.

The Flutter version's `LocalRule` shape (`{"rule":{...},"enabled":bool}`) is exactly the
same as this repo's, including `removeParams`-type rules (which can be stored but not
exported).

## Status

| Part | Status |
|---|---|
| `LinkPureCore` | ✅ 1053/1053 vectors pass |
| macOS app | ✅ usable (always-on menu bar / clipboard monitoring / write-back after rewriting / notifications / rule management / import-export / URL testing / launch at login / **sandbox enabled**) |
| iOS app | ✅ usable (rule management / usage guide / `CleanURLTextIntent` registered with Shortcuts) |
| Android `:core` | ✅ 1053/1053 vectors pass (Kotlin; a pure JVM module, no Android dependency) |
| Android app | ✅ usable (`ACTION_PROCESS_TEXT` silent in-place replacement + notifications / rule management / URL testing / Flutter rule migration) |
| Cross-language consistency | ✅ zero divergence across the Dart / Rust / Swift / Kotlin implementations |

### Known debts on the two platforms

**macOS**

- ~~App Sandbox disabled~~ → ✅ enabled and verified (clipboard polling unaffected)
- ~~No launch at login~~ → ✅ implemented (`SMAppService`)
- Notification banners need verification in a clean environment (on the current dev
  machine the notification-permission database has been dirtied by repeated rebuilds)
- No Sparkle updates
- The menu bar icon uses the cropped color artwork; a monochrome template image needs a
  dedicated vector design

**iOS**

- ~~The rule list shows at most 300 built-in rules~~ → ✅ removed (`List` is lazy
  already; truncation only creates "you can't find it even though it exists")
- App Store-related setup not done (privacy manifest, screenshots, etc.)

## Release notes

### bundle id (decided)

| Configuration | Both platforms |
|---|---|
| Debug | `com.rxliuli.linkpure2.dev` |
| **Release** | **`com.rxliuli.linkpure2`** |

`com.rxliuli.linkpure2` is the Flutter version's record on the App Store, and **iOS and
macOS share the same bundle id (Universal Purchase)**. For the native version to replace
it as an update, it **must reuse it**:

- ✅ Reuse → existing users get the update, ratings / reviews / downloads preserved
- ❌ Don't reuse → two independent apps, starting from zero

Note that the macOS and iOS Release bundle ids **must be identical** — that's a hard
requirement of Universal Purchase (Apple docs: "uses the same Apple ID (an app
identifier), SKU, and bundle ID as the iOS app").

Debug adds `.dev` so it can coexist with the App Store version and avoid the
notification-permission records polluted on the dev machine.

### Still missing before distribution

| Item | Notes |
|---|---|
| ~~macOS App Sandbox~~ | ✅ **enabled** (see "About the sandbox"); the prerequisite for Mac App Store submission is met |
| ~~Launch at login~~ | ✅ implemented (`SMAppService`) |
| Distribution signing | Currently `Apple Development`; formal distribution needs `Apple Distribution` / `3rd Party Mac Developer Application` |
| iOS submission materials | Privacy manifest, App Store screenshots, etc. |
| Auto-update | Sparkle not wired up |
| Real-world migration verification | So far only verified under the dev bundle id; before release, apply the Release configuration + actually upgrade from the Flutter version once |

## Relationship with the Flutter version

The Flutter version remains the **single source of truth** for the rule library and
conformance vectors. This repo makes a vendored copy via `Scripts/sync-spec.sh` so it
can build self-contained.

Long term, `Spec/` (rule library + vectors) should become an independent repo or
submodule, referenced by every implementation.
