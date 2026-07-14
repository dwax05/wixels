# wixels — session handoff (2026-07-14)

Native macOS Swift desktop-widget system replacing the user's cynaberii **Übersicht**
widgets. One `LSUIElement`/accessory SwiftPM binary (`wixels-proto`) draws pixel-art
sprites on the desktop layer, recolouring live with the pywal palette.

- **Repo:** `~/Developer/wixels` (NOT the dotfiles repo). Not a git repo.
- **Run:** `cd ~/Developer/wixels && swift run` (or `./.build/debug/wixels-proto`). Ctrl-C to quit.
- **Kill:** `pkill -x wixels-proto` (never `-f` — self-kills the shell).
- Swift 6.2, macOS 15.7. Build is clean; `swift build 2>&1 | tail`.

## IMPORTANT: read these first (don't re-derive)
- `~/Developer/wixels/DESIGN.md` — architecture, Widget/DataSource/RefreshPolicy seams.
- `~/Developer/wixels/wixels-handoff.md` — **STALE** (pre-dates most of this session; the
  "CURRENT BLOCKER: clicks" section is long resolved). Update or ignore it; this doc supersedes.
- Übersicht originals (source of truth for look/behaviour):
  `~/.dotfiles/theme/profiles/cynaberii/ubersicht/cynaberii-<name>/` (index.jsx + optional .py).
  Shared helpers: `.../_cynshared/` (cyncpu.py, cynmusic.py).

## What was done this session
Ported the **entire cynaberii widget set** from Übersicht to native Swift widgets, plus
built the shared infra they need. All sprite/data logic mirrors the JS/py originals.

### Widgets (all in `Sources/wixels-proto/Widgets/`)
- **DiskSnail** — disk gauge snail; crawls the sys-box perimeter over 24h (time-driven
  `TimelineView`, rotates per edge). Click = shy. `Crawl` enum holds tunable box geometry.
- **CatPet** — thermal-independent pet reacting to CPU/net/battery/music. Click = happy +
  heart burst; particles use shared `RisingParticle`. Perches on the now-playing card.
- **SysBox** — wifi bars + disk jar. `SysSource` (CoreWLAN + getifaddrs IPv4 + Data-volume disk).
- **NowPlaying** — cassette; album art (base64 decode), click toggles play/pause.
- **Plant** — click-to-water growth (water drops from top, no can); stage + bloom persist via `@AppStorage`.
- **Quotes** — speech bubble, click to reroll; sized to the tallest quote (measured once via TextKit in `QuoteSource`).
- **PixelClock** — HH:MM digits + blinking colon + date. (Renamed off stdlib `Clock`.)
- **Frog** — thermal-reactive (`ProcessInfo.thermalState`), sways, click/auto-poke pops it out
  from BEHIND the clock (see z-order note).
- **Stats** — CPU-wilt plant + memory soil + battery heart. `StatsSource` (host-tick CPU,
  `host_statistics64` mem, IOPS battery).
- **Owl** — idle-presence gauge (HID `HIDIdleTime` via IO registry, no `ioreg`); awake/drowsy/asleep, click blinks.
- **Weather** — pixel sky + temp; async `URLSession` (NWS → open-meteo, ipinfo.io location). interval 900s.
- **Poster** — album-recoloured now-playing card. Palette extracted from cover pixels via
  CoreGraphics (port of JS canvas quantiser in `CoverPalette.extract`). Controls = SF Symbols.
  Only renders while a track is loaded.

### Shared infra
- `PixelStrip.swift` — sprite renderer; plus `Cell` typealias, `set`/`fillShell`, `RisingParticle`,
  `triggerTransient`, `Font.pixel(_:bold:)` (Silkscreen), and the **`Pane`** modifier (dark panel +
  accent border + offset shadow pane; `.pane(_:insets:)`). Restyle all cards here.
- `Host.swift` — `WidgetHost`/`Scheduler`. `mount(..., zBoost:, align:)`:
  - **`zBoost`** raises a window's level (clock uses `zBoost:1` to stay above the frog).
  - **`align`** pins content to a window edge instead of NSHostingView's default center — this is
    how the right-column cards share a right edge (see below).
  - Occlusion pause: ticker `active` gate toggled by `didChangeOcclusionStateNotification`.
  - Anchors: topLeft/topRight/bottomLeft/bottomRight/center/**topCenter**.
- `Sources.swift` — all native DataSources (Disk, CPU, Pet, Sys, Frog, Stats, Owl).
- `MusicMonitor.swift` — reads shared cache `~/.cache/cynaberii/nowplaying.json`;
  `nowPlaying()`, `poster()`, `togglePlayPause()`, `next()`, `toggleShuffle()`.

## Layout convention (just established — important)
Right/left-anchored windows compute their edge as `maxX − pad + offset.width` (or `minX + pad + offset.width`).
- Set **`offset.width: 0`** to snap a widget to the shared margin; tune **`offset.height`** for vertical.
- Because NSHostingView **centers** content, a card narrower than its window floats and its visible
  edge drifts inward. Fix = pass **`align: .trailing`** (X pinned right, Y centered) so the content
  edge = window edge regardless of size. Stats/Weather/Poster now do this and share a right edge.
- Poster shadow was matched to `Pane` (offset 4 + trailing/bottom reserve) so its border aligns.

## Current state
All widgets build and run. Last action: fixed the three right-column cards
(Stats/Weather/Poster) to share a right edge via `align: .trailing`. Verified running (no crash).

## Gotchas already paid for
1. Palette watch = file fd, not dir (pywal rewrites in place). Re-arm on delete/rename.
2. No Swift Concurrency inside a DispatchSource handler on Swift 6 — fire on `.main` with plain closures.
   (The occlusion observer uses `MainActor.assumeIsolated` — OK because it's the main OperationQueue.)
3. In-process MediaRemote is dead on macOS 15.4+ for ad-hoc binaries → read the shared nowplaying.json.
4. Interactive widgets must sit at `.desktopIconWindow` level (clicks are eaten at `.desktopWindow`).
   Same-level windows reorder on click → use `zBoost` when one must stay above another.
5. macOS `sed` has no `\b`; use `perl -i -pe` for word-boundary renames.
6. `??` right-hand side is an autoclosure → can't `await` in it; unnest.
7. SourceKit routinely reports stale "Cannot find X in scope" for `main.swift` after adding widgets —
   `swift build` is the source of truth; ignore those.

## Open / not done
- **Placement is hand-tuned** in `main.swift` and approximate — the user iterates visually
  (widgets sit behind a fullscreen terminal, so `screencapture` from here won't show them; rely on user screenshots).
- Battery-vs-Übersicht measurement (DESIGN migration step 2, the real go/no-go) not done.
- Headphones slide-on/off transition (cat) still a hard cut.
- `wixels-handoff.md` in the repo is stale — consider replacing it.
- Not yet committed anywhere (repo has no git). `/prototype` capture step still pending.

## Suggested skills for next session
- **`/run`** or **`/verify`** — launch and confirm changes visually (this is a see-it-working project).
- **`mattpocock-skills:code-review`** — a broad review before any "v1" cut (last review's findings were all addressed).
- **`mattpocock-skills:codebase-design`** — if extending the Widget/DataSource/Host seams (e.g. formalising
  the anchor+align+offset placement API, or an occlusion/animation-freeze pass).
