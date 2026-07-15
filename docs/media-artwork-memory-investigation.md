# Handoff: isolate Wixels memory growth across track changes

## Goal

Determine whether Wixels retains memory as distinct songs play, and specifically
whether the MediaRemote artwork pipeline is responsible. Do not ship a fix until
the experiment produces a clear result.

## What we already know

- The host process (`wixels`) is the one with the high footprint; its bundled
  `mediaremote-adapter.pl` helper was stable at about 34 MB.
- On 2026-07-15, about ten minutes after launch, `vmmap -summary <wixels-pid>`
  reported a **361.8 MB physical footprint** and **549 MB peak**. `procs` RSS
  showed roughly 74 MB, so use `vmmap` physical footprint as the measurement.
- `MusicMonitor` launches the adapter using `stream --no-diff --debounce=200`.
  Full snapshots can therefore include the base64 `artworkData` on a metadata
  change.
- Each artwork change currently reaches both widgets:
  - `plugins/Cynaberii/NowPlaying/.../NowPlaying.swift` decodes it to `NSImage`.
  - `plugins/Cynaberii/Poster/.../Poster.swift` decodes it again and starts a
    detached palette-extraction task.
- A `leaks <pid>` run did not identify a large conventional malloc leak. The
  suspected retention is likely AppKit/SwiftUI image or render resources.

## Relevant code

- `WixelsKit/Sources/WixelsKit/MusicMonitor.swift`
- `plugins/Cynaberii/NowPlaying/Sources/WidgetNowPlaying/NowPlaying.swift`
- `plugins/Cynaberii/Poster/Sources/WidgetPoster/Poster.swift`
- `Vendor/MediaRemoteAdapter/src/adapter/stream.m`

## Controlled experiment

Run each case from a fresh Wixels launch. Use the installed app only if it is
rebuilt from the branch being tested; otherwise run the staged debug build with
the same user config. Keep the desktop layout and all non-media widgets unchanged.

For every sample, record this command's `Physical footprint`, `peak`, and the
`MALLOC_*`, `IOSurface`, `IOAccelerator`, and `CoreAnimation` rows:

```zsh
vmmap -summary "$(pgrep -x wixels | head -1)"
```

Take a baseline after launch settles for 60 seconds. Then play **20 distinct
tracks with distinct covers**, waiting 3–5 seconds after each change so the
stream and UI settle. Record samples after tracks 5, 10, 15, and 20. Also take a
10-second CPU stack sample after track 20:

```zsh
sample "$(pgrep -x wixels | head -1)" 10 -mayDie
```

Repeat the exact run in this order:

1. **Baseline:** current configuration (Now Playing and Poster enabled).
2. **No artwork transport:** temporarily start `MusicMonitor` with the adapter's
   `--no-artwork` argument, but leave both widgets mounted. This keeps streaming
   and metadata changes while removing cover payloads and image decoding.
3. **No Poster:** restore artwork transport, disable only Poster.
4. **No Now Playing:** restore Poster and disable only Now Playing.

Temporary switches should be narrowly scoped and clearly marked for removal;
do not hand-edit the user’s persistent desktop config. A launch environment flag
or a debug-only constructor argument is preferable.

## Decision rule

The experiment is red if physical footprint rises materially and monotonically
with track count in case 1, while case 2 stays near its settled baseline. A
consistent increase of more than ~2 MB per five tracks is worth investigating;
compare the slope, not just a one-off peak.

Interpret the isolation cases as follows:

| Result | Finding |
| --- | --- |
| Case 2 flat; case 1 grows | Artwork bytes/decode/rendering is causal. |
| Case 3 flat; case 4 grows | Poster is causal (palette extraction or image rendering). |
| Case 4 flat; case 3 grows | Now Playing image rendering is causal. |
| Cases 2–4 all grow similarly | Streaming or unrelated animation/reload path remains suspect. |

## If artwork is confirmed

Make the smallest fix that gives bounded live artwork ownership:

1. Decode artwork once in `MusicMonitor`, or otherwise share one bounded image
   representation between the two widgets; do not pass/decode raw base64 twice.
2. Tie Poster palette work to cancellation: avoid unbounded `Task.detached` work
   when artwork changes rapidly, and ignore a result that no longer belongs to
   the current artwork identity.
3. Ensure old image resources are released when a new track arrives or playback
   stops. Do not add an unbounded artwork cache.
4. Add a test at the chosen seam for deduplication/cancellation and rerun the
   20-track experiment as the acceptance test.

Remove all diagnostic switches and logs before committing. In the final report,
include the four footprint series and state whether the slope disappeared.
