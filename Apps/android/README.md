# LinkPure for Android

LinkPure's native Android implementation (Kotlin / Gradle), alongside `Apps/macOS` and
`Apps/iOS`.

## Why this directory

The rule library and the conformance vectors are a **cross-language data contract**, and
the repo stores exactly one copy of each:

| Shared thing | Single source of truth | How Android uses it |
|---|---|---|
| Rule library | `Sources/LinkPureCore/Resources/shared-rules.json` | `core/build.gradle.kts` puts it on the classpath via `resources.srcDir(...)` |
| Conformance vectors | `Tests/LinkPureCoreTests/Vectors/` | the `syncVectors` task syncs them into `build/vectors` and passes the path to the tests via a system property |

**No copies live here.** When you run `Scripts/sync-spec.sh` to pull a new upstream
version, Swift and Android both move together.

## Structure

```
Apps/android/
├── settings.gradle.kts
├── gradle/libs.versions.toml
├── core/                             the Kotlin port of LinkPureCore (pure JVM, no Android)
│   └── src/main/kotlin/com/rxliuli/linkpure/core/
│       ├── Rule.kt                   data contract (mirrors shared-rules.json)
│       ├── UrlCleaner.kt             rule engine (behavioral contract: conformance/README.md)
│       ├── PercentCodec.kt           two kinds of percent-decode (capture group vs query key — different semantics)
│       ├── LocalRule.kt              user rules + import/export exchange format
│       └── RulesManager.kt           loads the built-in rule library + JSON config
└── app/                              the Android app
    └── src/main/kotlin/com/rxliuli/linkpure/
        ├── ProcessTextActivity.kt    ★ the only entry point; never calls setContentView
        ├── clean/Cleaner.kt          clean one URL (fast local path first, network only for short links)
        ├── clean/CleanNotifier.kt    notification: cleaned / already clean / not a URL
        ├── clean/CopyActionReceiver.kt  the "Copy" action on the notification
        ├── data/RuleStore.kt         file storage + Flutter rule migration
        ├── data/HttpRedirectFollower.kt  hop-by-hop following for followRedirect rules
        └── ui/                       Compose rule management + editor
```

`:core` is deliberately a **pure JVM module** (not an Android library): the 1053 vectors
run in seconds, and the engine cannot accidentally reach for an Android API.

## UI: hand layout to system containers

This rule was established in the Swift-side README, and the first Android UI violated it —
it hand-stacked "usage guide + test box + two rows of buttons + list" into one `LazyColumn`,
so the guide ate 40% of the screen and the actual list was pushed below the fold. It looked
like it had no idea what mattered. What it does now:

| Intent | Container |
|---|---|
| Which screen you're on (list / editor / guide) | `AnimatedContent` (slide in from the side + fade) |
| Switching "My rules / Built-in library" | `TabRow` (its own indicator and horizontal animation) |
| Search | search icon in the top bar → input inside the top bar (auto-focused) |
| New rule | `FloatingActionButton` |
| Import / export / guide / about | overflow menu in the top bar |
| Deleting a rule | **swipe** in the list |
| A rule's secondary actions | **no extra entry point**: built-in rule text is selectable/copyable (`SelectionContainer`), a user rule's regex is copied in the editor |
| Action feedback | `Snackbar` (with Undo after delete/import) |
| Save / cancel | the editor's own `TopAppBar` (Save at top right) |
| Test result | the **rewrite chain** in the editor (aligned with `RuleTestResultView` on the Swift side) |

Deliberate decisions:

1. **One action, one place.** Deleting only happens by swiping in the list — no delete button
   in the row, and none in the editor either. Same for the enable toggle: only at the end of
   the list row.
2. **The guide is its own page**, not a card on the main screen.
3. **Search spans both lists** and hides the tabs. When a user hits search they are thinking
   "find a rule", not "find a rule in this particular list" — searching `youtube` under
   "My rules", getting "no matches" while the built-in library is full of them, is just dumb.
4. **Import always merges, no dialog.** macOS and iOS both hardcode `merge: true`
   (`MainWindowView.swift:686` / `IOSRulesView.swift:470`). The first Android version invented
   a "Merge / Replace" dialog — three equally weighted buttons asking the user to make a
   decision they don't need to make. To replace, delete first and then import; merging never
   destroys existing data and there's undo as a backstop.
5. **Every screen draws its app bar inside `AnimatedContent`**, never on `Scaffold.topBar`.
   The editor screen's top bar is empty (it has its own app bar), so attaching it to the
   Scaffold makes the padding jump from "top bar with a two-line title" to 0 while switching —
   **the whole page jumps upward as it slides sideways**, which looks broken.
6. **The undo bar is 6 seconds, not Material's `Long` (10s).** iOS uses 6
   (`IOSRulesView.swift`), macOS 8 (`MainWindowView.swift`); Material only offers
   Short (4s) / Long (10s), so this uses `Indefinite` plus its own `delay(6000)` to dismiss.
   When deleting two in a row, remember to cancel the previous timer — otherwise the older
   timer hides the new bar early.
7. **The editor's preview runs twice**: first the synchronous `checkLocally` to draw the first
   frame (no flicker), then the asynchronous `check` to overwrite it. **The async pass is not
   optional** — `checkLocally` has no follower configured, so a `followRedirect` match can only
   report "no match" instead of the expanded URL. iOS's `RuleEditorView` does the same two
   steps (compute synchronously up front, then `await check` in `.task`). The async pass is
   debounced by 250ms, otherwise every keystroke would go to the network.
8. **No long-press menu.** There used to be one (copied from iOS: Edit / Enable-Disable /
   Copy rule ID / Copy regular expression / Delete), but 3 of the 5 duplicated "tap the row /
   toggle at the end / swipe". On a platform with no multi-select, a long-press menu is just a
   gathering place for duplicated actions — macOS has `contextMenu(forSelectionType:)`, which
   acts on the **selection**, and that is what an actual context menu is for. Built-in rule
   text now uses `SelectionContainer` and goes through the system's own select/copy.

It also fixed a real bug: pressing the system Back key in the editor exited the app (there was
no `BackHandler`). Now, whenever you're not on the list screen, Back returns to the list.

### Test results must show the **rewrite chain**, not just the final result

The question you're actually asking while writing a rule is "**which rules matched, in what
order**". Printing only a final result makes it easy to misread as "my rule didn't work" —
in practice an earlier built-in rule rewrote the URL and yours only matched on the second pass.

Example: rule `^https://youtu\.be/(\w+)$` (with a `$` anchor) and test URL
`https://youtu.be/xxx?si=yyy`

```
Rewrite chain (2 steps)
  https://youtu.be/xxx                          ← si already removed by an earlier rule
  https://www.youtube.com/watch?v=xxx            ← your rule only matches on the second pass
```

`MatchResult.chain` has always been computed by the engine (`check` / `checkLocally` both
return it) and the `03-iteration.json` vectors watch it — the UI simply wasn't showing it.
The Redirector reference implementation and the Swift side both do this.

## Running it

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

./gradlew :core:test                # the 1053 conformance vectors
./gradlew :app:assembleDebug        # the Android app
```

Expected output:

```
ok   01-params.json  (10 cases, 0 failed)
...
TOTAL: 1053 cases, 0 failed
```

## Trying the entry point on a simulator or device

```bash
P=com.rxliuli.linkpure.dev
adb install -r app/build/outputs/apk/debug/app-debug.apk
# The whole command must be wrapped in **one extra layer of quotes**: adb shell joins the
# arguments into a single command for the device's sh, and without the quotes the `&` in the
# URL is treated as a background-job operator — only the part before the `?` arrives.
adb shell "am start -n $P/com.rxliuli.linkpure.ProcessTextActivity \
  --es android.intent.extra.PROCESS_TEXT 'https://example.com/?utm_source=x&id=1'"

adb shell dumpsys notification --noredact | grep -E "android.title=|android.text="
```

True in-place replacement only shows up when you select a link in a browser's address bar and
go through the "process text" menu (`am start` has no calling activity, so it can't receive
`setResult`).

## Verifying the Flutter rule migration

The migration reads `flutter.local_rules` out of
`shared_prefs/FlutterSharedPreferences.xml`, but a debug build carries the `.dev` suffix and
therefore a different data directory, so it **cannot see it**. Build with the real package
name:

```bash
./gradlew :app:assembleDebug -PrealPackage
```

## Two things hit while porting (not in the spec — language differences)

1. **`\d` / `\w` / `\s` need no rewriting here.** Java's `Pattern` is ASCII-semantic by default
   (`\d` = `[0-9]`, `\w` = `[a-zA-Z_0-9]`), so the `asciiRewrite()` the Swift side needed to
   escape ICU's Unicode semantics is redundant. The 9 vectors in `05-regex-flavor.json` watch
   this.
2. **`java.net.URLDecoder` is not usable.** It always treats `+` as a space, which on a
   "capture group" diverges from Dart's `Uri.decodeComponent` (spec item 5 explicitly requires
   capture groups to **not** turn `+` into a space). See `PercentCodec`.

## Shape (settled by a probe)

**Only `ACTION_PROCESS_TEXT`, silent by default, plus a notification.**

Based on measurements in `~/code/kotlin/ClipboardAccessProbe`:

- Android 10+ **cannot read the clipboard in the background**, and **doesn't even deliver
  `clipboardChanged` events** — so macOS's "zero-interaction automatic rewrite" is
  fundamentally impossible on Android
- `ACTION_PROCESS_TEXT` carries its content in the intent and **never touches the clipboard**,
  which sidesteps every one of those restrictions
- Quick Settings tiles / floating bubbles / widgets: measured to not work, or given up on —
  see the probe repo's README

## User rules are only "one regex + one replacement target"

`Rule` has three mutually exclusive fields (`regexSubstitution` / `removeParams` /
`followRedirect`, in that priority order in the engine), but **only the first is meant to be
authored by users**:

| Field | Count in the built-in library | User-editable |
|---|---|---|
| `removeParams` | **978** (92%) | ❌ |
| `regexSubstitution` | 66 | ✅ |
| `followRedirect` | 13 | ❌ |

The other two are **mechanisms for the built-in library**: the engine supports them, the list
shows them read-only ("removes utm_x"), and the editor doesn't touch them. That's what the
Flutter reference implementation does (`removeParams` appears **zero times** in
`rule_edit_page.dart`, and the git history has never had editor support for it), and so do
iOS/macOS's `RuleEditorView` (its `canSave` requires a non-empty replacement target, so those
rules are read-only there).

> Why `removeParams` must not be exposed in the editor: **it can never be exported.** The
> exchange format can only express from→to, so `RuleExchange.export` has to skip such rules.
> Letting users author something that can't leave the app is a trap in itself.
>
> The Android version once added a "Replace URL / Remove params" mode switch on its own
> initiative; it was removed later — that was inventing a feature, not aligning.

## The notification body is the **cleaned URL**, not a summary

```
LinkPure
URL cleaned
https://www.youtube.com/watch?v=dQw4w9WgXcQ      ← body
2 params removed                                  ← extra line, only when expanded
[Copy]
```

What the user wants to know is "what did it become". macOS posts it the same way
(`NotificationService.post(title: "URL Rewritten", body: to)`), and so does Flutter.

Missed this once: the body carried `summary` ("URL rewritten" / "2 params removed") and
**the URL wasn't in the notification at all** — worse, that `summary` still said "URL rewritten"
when `removed == 0`, i.e. it just repeated the title. Now `summary` is only non-empty when
parameters were actually removed, and it only serves as the expanded line.

## Two things that must change before the first Play release

1. **`versionCode` must be greater than the Flutter version's current value on Play**
   (0.5.2 → 502). It is derived from `project.yml` now (0.6.5 → 605), which matches the Swift
   side's build number. **Making it smaller makes Play reject the upload outright.**
2. **The signing key must reuse the Flutter version's `android/upload-keystore.jks`**
   (in `~/code/flutter/LinkPure/android/`). Play requires the same upload key for the same
   package name; change it and you can never update the app again, only open a new one.

## CI release (the `android` job in release.yml)

`./gradlew :app:bundleRelease :app:assembleRelease` → verify the APK signature → hand the AAB
to Play; the AAB and APK are also kept as workflow artifacts (and attached to the GitHub
Release).

The four **signing** secrets already live in the `build-android` environment
(`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
`ANDROID_KEY_ALIAS`). CI writes `key.properties` and `upload-keystore.jks` from them on the
spot — both files are in `.gitignore`. To release locally, put your own copy under
`Apps/android/` (`storeFile` is resolved relative to the module root).

The **Play publishing credential** is a different thing and has to be created once:

1. Play Console → Settings → API access → link (or create) a Google Cloud project
2. In that Cloud project, create a service account and grant it the "Play service account"
   role; "Release to testing tracks" is enough for test tracks, and releasing to production
   additionally needs "Manage production releases"
3. Download that service account's JSON key
4. `gh secret set PLAY_SERVICE_ACCOUNT_JSON --env build-android < the-downloaded.json`

While that is missing the job **does not go red**: it prints a warning and explains itself in
the Step Summary, and the AAB/APK are still produced (no other channel is affected). Once it's
configured, every release uploads automatically.

The default track is **internal** (live within seconds, no review). To ship a production
release:

```sh
gh workflow run release.yml -f play-track=production
```

## Not done yet

- **Testing on a real device**: so far only an API 37 emulator
- **Swift-side export behavior needs aligning**: for `removeParams` / `followRedirect` rules,
  Kotlin currently **skips and tells the user how many were skipped** (the Flutter reference
  implementation skips too), while `RuleExchange.export` on the Swift side **throws** — so a
  single remove-params rule makes the whole export fail. Aligning to "skip" is the suggestion.

## Three pitfalls hit in practice

1. **kotlinx.serialization omits fields equal to their default value**, so the `rules.json` it
   writes has no `enabled` / `version`. But Swift's `LocalRule` / `RuleFile` declare both as
   non-optional with no default, and `Codable` **fails to decode** a missing key — i.e.
   "a file Kotlin wrote can't be read by Swift". The fix is `encodeDefaults = true` in
   `LinkPureJson`, with `RuleExchangeTest.ruleFileAlwaysWritesVersionAndEnabled` watching it.
2. **`adb shell` joins its arguments into one command for the device's sh**, so the `&` in
   `--es android.intent.extra.PROCESS_TEXT 'https://…?a=1&b=2'` is treated as a background-job
   operator and only the part before the `?` arrives. The whole `am start` command needs one
   more layer of quotes.
3. **`rememberSwipeToDismissBoxState` is `rememberSaveable` under the hood**, and `LazyColumn`
   saves each row's state by item key. So on "swipe away → delete → undo", the row that comes
   back with the same key also restores **the "swiped away" offset**: the rule is genuinely
   back, but it looks broken (content off-screen, just background colour and Delete).

   The fix is to skip that factory function and use
   `remember { SwipeToDismissBoxState(...) }` directly — the constructor is public. Not
   saveable means it isn't restored, so a re-inserted row always starts at `Settled`.
