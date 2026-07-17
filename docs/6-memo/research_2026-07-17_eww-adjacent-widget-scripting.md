# Research: Eww-adjacent widget scripting for Wixels

**Date**: 17-07-2026  
**Author**: Codex

## Summary

Migrating Wixels from runtime-loaded Swift widget dylibs to an Eww-adjacent
configuration-and-script model is technically feasible, but a direct migration is
not recommended. It would replace native SwiftUI composition, typed shared sources,
and the current single-process permission identity with shell execution whose
privileges belong to the interpreter or host that runs it.

The recommended direction is a hybrid: keep Wixels as the signed native renderer
and permission owner; add a Wixels-owned script/data broker beside the existing
`mediaremote-adapter.pl`; expose only named, typed capabilities to declarative
widgets. Start by proving that protocol with one read-only widget. Do not run
arbitrary widget shell commands inside Wixels.

## Questions investigated

### Can an Eww-like data model replace the current plugin system?

**Finding**: Partly. Eww's useful pattern is declarative widgets/windows plus
polling variables and long-lived listeners. Its documented `defpoll` executes a
command per interval; `deflisten` starts one process and consumes its line-oriented
output. That maps well to Wixels data updates, but not to macOS rendering or a
security boundary. Eww targets Linux window-manager environments, while Wixels
owns macOS desktop windows through AppKit/SwiftUI.

**Confidence**: High.  
**Evidence**: [Eww documentation](https://context7.com/elkowar/eww/llms.txt)
describes a daemon with windows, variables, poll commands, and listener commands.
No `eww` script or executable is present in this repository.

### Would scripts eliminate per-widget permission prompts?

**Finding**: No, not on their own. macOS privacy consent belongs to the requesting
app/process identity and protected resource, not to a widget manifest. Today every
plugin is loaded via `dlopen` into Wixels, so it already runs under Wixels' identity
and can use everything Wixels can use. The existing Calendar and Reminders sources
request access only when an enabled widget first reads them; subsequent reads reuse
that Wixels-level grant. A script run through `/bin/sh`, Python, Perl, or another
external interpreter does not safely inherit a generic, reusable “widget
permission”; it changes which process is asking and can trigger its own TCC path.

**Confidence**: High for current Wixels; high for the design implication.  
**Evidence**: `WixelsKit/Sources/WixelsKit/Sources.swift` invokes EventKit access
from `CalendarSource` and `RemindersSource`; `packaging/Info.plist` declares their
usage strings. Apple documents that `requestFullAccessToEvents()` prompts on the
first request and later event-store instances use the existing permission
([Apple](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents%28completion%3A%29)).
Apple Events likewise require an app usage description
([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription?changes=_3%2C_3)).

### Does replacing dylibs improve extension safety?

**Finding**: Only if the new format is declarative and capability-gated. It is an
improvement over the current model if third-party extensions no longer execute in
the Wixels address space. It is not an improvement if the host executes extension-
provided shell strings: that remains arbitrary code execution with the host's file,
network, and privacy access.

**Confidence**: High.  
**Evidence**: `docs/writing-widgets.md` explicitly calls plugins “trusted local
code” that runs in Wixels' process. `PluginLoader.swift` loads each extension with
`dlopen` and calls its exported registration function. The release packager signs
each dylib ad hoc. Apple notes that App Sandbox limits an app's resources through
entitlements, and that embedded command-line tools inherit the containing app's
sandbox configuration ([Apple](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)).

### How much of the installed widget set can use a declarative/script format?

**Finding**: Most read-only data widgets can, but pixel-art and interactive widgets
will need a real rendering/action language rather than just command output.

| Widget family | Current dependency | Script/data migration fit |
| --- | --- | --- |
| Clock, disk, stats, sys, frog, owl | Native system APIs | Good through broker capabilities |
| Weather | `URLSession` + network | Good, but network must be an explicit capability |
| NowPlaying, Poster, Pet | Shared `MusicMonitor` + bundled Perl adapter | Good as a shared broker stream; do not duplicate per widget |
| MacOS Clock, Reminders | EventKit read/write | Read-only display is good through broker; completion action must be explicit and user-mediated |
| Plant, Quotes | Local UI state/file source | Needs declarative interaction/state primitives |
| Cynaberii pixel widgets | SwiftUI custom drawing/animation | Poor fit for text-only output; needs a retained scene/DSL or an intentional visual rewrite |

**Confidence**: High.  
**Evidence**: Every current plugin defines `sample()` plus SwiftUI `render()` in
`plugins/*/*/Sources`; WixelsKit centralizes shared samplers in `Services`.

## Current architecture and constraints

1. **Extensions are in-process code.** A package contains `libWidget*.dylib` files.
   `PluginLoader` discovers them, calls `dlopen`, then invokes `wixels_register`.
   The plugin returns a typed SwiftUI view and an asynchronous sampler through the
   WixelsKit ABI.
2. **Permissions are host-level today.** The current privacy strings are Calendar,
   Reminders, and Apple Events. `CalendarSource` and `RemindersSource` prompt lazily.
   Wi-Fi SSID is deliberately handled with a privacy-safe fallback when Location
   Services redacts it.
3. **The one existing adjacent script is privileged by design.**
   `MusicMonitor` invokes `mediaremote-adapter.pl` through `/usr/bin/perl` because
   the private MediaRemote framework accepts reads from that entitled system process.
   It maintains one streaming child and shares its cache across widgets.
4. **The renderer is not interchangeable.** Wixels has native desktop window
   placement, click-through behavior, editing, fit-content sizing, occlusion-aware
   scheduling, themes, previews, and SwiftUI interactions. A script-only interface
   has to replace all of those contracts, not merely data fetching.
5. **Packaging currently assumes trusted extensions.** The host-only app contains
   no widgets; packs are copied into `~/.config/wixels/plugins/`. The user has to
   approve quarantine removal before dynamic libraries load.

## Options compared

| Option | Permission result | Safety result | Migration cost | Recommendation |
| --- | --- | --- | --- | --- |
| Keep dylib plugins | One Wixels-level grant, lazy prompts | Third-party code has full Wixels access | None | Keep for first-party/native widgets only |
| Arbitrary Eww-style shell commands | No reliable consolidation; interpreter identity matters | Unsafe if host launches commands | Medium | Reject |
| Separate generic script daemon | Can centralize only daemon-owned permissions | Requires IPC auth and still trusts script protocol | High | Do not start here |
| Wixels capability broker + declarative widgets | One prompt per Wixels capability, not per widget | Strong if extension cannot name arbitrary commands/files | Medium-high | Recommended |

## Recommended target architecture

```
extension manifest + declarative view
            |                        
            | capability subscriptions/actions
            v
     Wixels renderer / scheduler
            |
            | authenticated local IPC or supervised stdio
            v
  Wixels-owned script broker (beside mediaremote-adapter.pl)
            |
            +-- native source adapters: calendar, reminders, disk, CPU, weather
            +-- one long-lived MediaRemote adapter stream
```

The broker is an implementation detail of the signed Wixels distribution, not a
general shell runner. It should use versioned newline-delimited JSON over stdio or a
Unix-domain socket:

```json
{"type":"subscribe","id":"w1","capability":"system.stats","intervalMs":20000}
{"type":"snapshot","id":"w1","value":{"cpu":32,"memory":61,"battery":82}}
{"type":"action","id":"w1","capability":"reminders.complete","input":{"id":"..."}}
```

Rules:

- A manifest declares a fixed allowlist of capability names, refresh constraints,
  option schema, and allowed user-initiated actions.
- Wixels validates every request. No command strings, arbitrary executable paths,
  arbitrary environment variables, arbitrary file paths, or raw AppleScript.
- Protected capabilities disclose their data class and request permission only when
  first used. Actions require a visible user gesture and may require an additional
  confirmation.
- The broker owns process lifecycle, restart/backoff, output-size limits, timeouts,
  and structured errors.
- Cache and fan out shared sources: `music.nowPlaying`, `system.cpu`, and weather
  must not become one process/request per widget.
- Declarative views cannot execute code. Keep a deliberately separate “trusted
  native widget” lane for first-party Swift dylibs until the view DSL is capable.

## Migration plan

### Phase 0 — decide the trust model

Write an extension manifest and capability catalogue. Explicitly decide whether
third-party widgets are untrusted. If yes, no arbitrary scripts are allowed in the
extension format. This is the architectural fork.

### Phase 1 — extract a broker contract without changing widgets

Move one existing shared source behind an internal protocol; `MusicMonitor` is the
best fit because it already supervises a long-lived adjacent script. Preserve the
current WixelsKit API so existing dylib widgets continue to work.

### Phase 2 — read-only proof of concept

Implement `system.stats` as a broker capability and a tiny declarative widget
manifest/view. Validate subscription sharing, reconnect behavior, invalid manifest
rejection, and that no new prompt occurs after granting the Wixels-level capability.

### Phase 3 — declarative renderer slice

Support only text, image, row/column/stack, colors/themes, sizing, and visible state.
Port one simple noninteractive widget (Stats or Weather). Do not port pixel art or
interactive cards yet.

### Phase 4 — actions and protected sources

Add gesture-bound actions and permission-state rendering. Port Reminders only after
the broker can enforce an action schema and surface denied/restricted states.

### Phase 5 — selective migration, not a flag day

Keep Swift dylibs for first-party pixel/interactive widgets and developer builds.
Migrate only widgets whose representation and capability needs are proven. Remove
the dynamic dylib extension surface only if the declarative format meets those
widgets' needs and a compatibility/deprecation path is accepted.

## Acceptance criteria for the proof of concept

- [ ] A malformed or untrusted extension cannot cause Wixels to execute a shell
      command or read an arbitrary path.
- [ ] Two widgets subscribing to `system.stats` share one sampler.
- [ ] The broker survives a child crash and reports a bounded, visible error.
- [ ] A denied permission is represented in the widget state without retry loops.
- [ ] Capability manifests are validated before a widget is mounted.
- [ ] Existing dylib widgets and layouts remain functional with the broker disabled.
- [ ] The proof demonstrates no per-widget prompt after a Wixels-level grant.

## Risks and open questions

1. **“Eww script” is not present in this checkout.** The intended adjacent script
   location/name and whether it is an existing external project need confirmation.
2. **Unsigned local extensions remain a trust decision.** A data-only manifest can
   be safely untrusted; a script-bearing package cannot unless scripts execute in a
   meaningful sandbox with narrowly scoped I/O.
3. **App Sandbox is not a drop-in answer.** It would constrain Wixels and embedded
   helpers, may conflict with current home-directory configuration and extension
   packs, and requires an entitlement/design review.
4. **Presentation parity is substantial.** A declarative DSL must cover animations,
   artwork, interaction, pixel grids, fit-content measurement, and accessibility or
   accept a reduced extension feature set.
5. **Distribution policy remains open.** The current app is ad-hoc signed and
   extension dylibs are loaded from user configuration. A later Developer ID or App
   Store distribution strategy may constrain either dylib loading or embedded tools;
   Apple supports library constraints for limiting loadable dynamic libraries
   ([Apple](https://developer.apple.com/documentation/security/defining-launch-environment-and-library-constraints?changes=_1)).

## Verification notes

Research was read-only except for this memo. `git diff --check` passed. `swift build
--quiet` could not run in the sandbox because Swift attempted to write its module
cache outside the writable workspace and the installed Command Line Tools compiler
and SDK revisions also disagreed. This is an environment/toolchain issue, not a
result of the research changes.

The workflow's optional Codex CLI red-team could not run because this checkout does
not contain the required `.Codex/skills/codex-plan-review/` scripts. The conclusion
above therefore has not received that separate local-agent review.

An unrelated, untracked `wixels-composition-handoff.md` was already present and was
not changed.
