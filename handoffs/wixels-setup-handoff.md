# wixels — handoff

## What this is
Building **wixels**: a native macOS Swift desktop-widget system to replace the
user's cynaberii **Übersicht** widgets (Electron + node + per-tick shell spawns).
One `LSUIElement`/accessory Swift agent draws pixel-art sprites on the desktop
layer, recolouring live with the pywal palette.

Prototype lives at **`~/Developer/wixels`** (NOT the dotfiles repo). SwiftPM
executable `wixels-proto`. Not a git repo yet. Swift 6.2, macOS 15.7.

Run: `cd ~/Developer/wixels && swift run` (Ctrl-C to quit; accessory app, no dock icon).

## Read these first (don't re-derive)
- **`~/Developer/wixels/DESIGN.md`** — full architecture: seams (Widget +
  DataSource are real; Palette + Placement are not), the `Widget`/`DataSource`/
  `RefreshPolicy` interfaces, type-erasure decision, deletion test, migration order.
- Source (`~/Developer/wixels/Sources/wixels-proto/`):
  - `Palette.swift` — RGB palette model + `PaletteStore` (live wal watch).
  - `PixelStrip.swift` — shared sprite renderer (char grid → palette map → crisp
    scaled pixels via Canvas; multi-frame cycling) + `set()`/`fillShell()`.
  - `Widget.swift` — Widget protocol, RefreshPolicy, DataSource, WidgetModel/View, erasure.
  - `Sources.swift` — DiskSource (statfs), CPUSource (mach), PetSource (cpu+net+battery+music).
  - `MusicMonitor.swift` — now-playing via the shared cache (see gotcha below).
  - `Host.swift` — WidgetHost (desktop windows + placement + shared scheduler),
    `InteractivePanel`, `ClickableHostingView`.
  - `Widgets/DiskSnail.swift`, `Widgets/CatPet.swift` — the two ported widgets.
  - `main.swift` — builds host, mounts the two widgets, runs.
- Übersicht originals being ported (source of truth for look/behaviour):
  `~/.dotfiles/theme/profiles/cynaberii/ubersicht/cynaberii-snail/` and
  `.../cynaberii-pet/` (index.jsx + .py). Shared music helper:
  `.../ubersicht/_cynshared/cynmusic.py`.

## Status — what works
Feasibility proven and both widgets ported faithfully as pixel sprites:
- Desktop-layer borderless windows, all-Spaces, single process, no Electron/node.
- Live wal recolour on theme switch (crash-fixed — see gotchas).
- **DiskSnail** (18×15): shell fills bottom-up with disk %, warm flush ≥90%, wal-derived shades.
- **CatPet** (16×17): pet.py state machine — idle/sleep(CPU<8)/run(CPU>70)/eat(net>150KB/s),
  charging blush, music headphones + drifting notes + **groove dance**. Native
  sources (mach cpu, getifaddrs net, IOKit charging), no shell spawn.
- Music state working via the shared cache.
- Verified end-to-end each step by launching headless and reading debug logs.

## CURRENT BLOCKER (where the next session starts)
**Click interactions not yet confirmed working.** Just added click support:
- `Widget.interactive` flag; snail/cat set it true.
- Interactive windows now use a **non-activating `NSPanel`** subclass
  (`InteractivePanel`, `canBecomeKey = true`) + `ClickableHostingView`
  (`acceptsFirstMouse = true`) — the fix for a borderless desktop overlay that
  can receive clicks without stealing focus. (A plain borderless NSWindow reports
  `canBecomeKey = false`, so clicks never routed — that was the first bug.)
- Tap reactions are ephemeral `@State` inside `SnailView` (shy, 0.7s) and
  `PetView` (happy face + heart burst, 1.5s), so `render` stays pure.

**User last reported "these are not clickable" BEFORE the NSPanel change.** The
NSPanel build compiles + launches clean but the user has NOT yet confirmed whether
clicks now work. **First action: ask the user to test clicking the snail/cat.**

If still dead, the prime suspect is the **window level**: `kCGDesktopWindowLevel`
(`CGWindowLevelForKey(.desktopWindow)`) may sit below where the window server
routes clicks on macOS 15.7. Next thing to try: bump interactive panels to
`.desktopIconWindow` level (or test normal level) — set in `Host.makeWindow`.

## Gotchas already paid for (don't rediscover)
1. **Palette watch = file fd, not directory.** pywal rewrites colors.json in place
   (same inode); a dir watch never fires. Watch the file; re-arm on delete/rename.
2. **No Swift Concurrency in a DispatchSource handler.** Task/MainActor/assumeIsolated
   from a libdispatch worker trips `swift_task_isCurrentExecutor` → abort on Swift 6.
   Fire the source on `.main` queue with plain closures; store is `@unchecked Sendable`.
3. **In-process MediaRemote is DEAD on macOS 15.4+** for ad-hoc-signed binaries —
   `MRMediaRemoteGetNowPlayingInfo` returns nil. Only the Apple-signed `swift`
   interpreter got real data (this faked out the standalone probes; the *compiled*
   binary returns nil). Fix: `MusicMonitor` reads `~/.cache/cynaberii/nowplaying.json`
   (the shared cache the sketchybar plugin publishes), fallback `nowplaying-cli`.
4. **`pkill -f wixels-proto` self-kills the shell** (matches its own command line) —
   caused mysterious exit-144s. Use `pkill -x wixels-proto`.
5. **Foreground `sleep` is blocked** in this harness — use `python3 -c "time.sleep()"`.
6. Test-launch recipe: `/tmp/run-wixels.sh` (sets `WIXELS_COLORS=/tmp/wixels-test-colors.json`
   so tests never touch the real palette) run in background, then `pgrep -x`.

## Parity still open (after clicks)
- Snail 24h perimeter crawl (needs a cynaberii-sys anchor that doesn't exist natively yet).
- Headphones slide-on/off transition (currently a hard cut).
- Interactive windows intercept clicks over their whole rect (incl. transparent
  pixels) — cat's 72×96 box clickable in empty areas. Tighten hit area if it annoys.
- Occlusion-pause + actual **battery measurement** vs Übersicht baseline
  (the real go/no-go for the migration — DESIGN.md migration step 2).
- Port remaining widgets; Metal port for cava/shader widgets.

## Housekeeping
- No debug `fputs` traces currently left in (removed). `WIXELS_COLORS` env override
  + `/tmp/run-wixels.sh` retained for isolated testing.
- Prototype is still throwaway per the /prototype workflow — not yet committed to a
  branch; `~/Developer/wixels` is not a git repo.

## Suggested skills for next session
- **`/verify`** or **`/run`** — to actually launch wixels and confirm clicks work
  (the immediate blocker). This is a see-it-working task, not a code-reading one.
- **`mattpocock-skills:codebase-design`** — if extending the Widget/DataSource seams
  (e.g. adding an interaction input to the protocol, or a Placement/anchor seam for
  the snail crawl).
- **`/prototype` capture step** — when ready to record the throwaway: git init +
  commit to a `proto/wixels-desktop-widgets` branch, leave the verdict on an issue.
