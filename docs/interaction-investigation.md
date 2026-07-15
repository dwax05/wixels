# Interaction failure investigation

## Reproduction command

Run in a logged-in macOS GUI session after granting Accessibility permission to
the invoking terminal:

```sh
WIXELS_INTERACTION_REPETITIONS=100 swift run wixels --interaction-tests
```

The internal suite mounts two isolated interactive probes, derives click and drag
coordinates from their mounted window frames, and posts real mouse events through
`CGEvent`. It checks launch, edit cancel, edit save after an actual drag, host
shutdown/rebuild, and edit-save followed by rebuild. Placement writes are no-ops;
the suite does not load or mutate desktop config or widget persistence.

`WIXELS_INTERACTION_REPETITIONS` may be set from 1 through 100 for a shorter run.

## Result

The exact reported symptom was not reproduced deterministically. A first stress
run produced one partial failure after the fifth edit-cancel transition:

```text
FAIL edit-cancel #5: both probe widgets must react; before=[5, 5] after=[6, 5]
  probe[0] window=23992 level=3 key=false ignoresMouse=false editing=false
  probe[1] window=23993 level=3 key=false ignoresMouse=false editing=false
```

This was not the reported state (both widgets dead), and it did not recur after
instrumentation. A no-transition control delivered 202/202 clicks. The instrumented
edit-cancel loop then delivered all clicks through panel, hosting view, SwiftUI
gesture, and probe effect for 100/100 transitions. The smallest suspected sequence
is therefore launch → edit → cancel, but it is not a confirmed reproduction.

## Hypotheses tested

1. General synthetic-event loss: falsified by the 100-iteration no-transition
   control.
2. A stale `layoutEditing` flag or SwiftUI gesture: not observed; every instrumented
   event that reached `LayoutHostingView.mouseDown` reached the gesture and effect.
3. `ignoresMouseEvents` or window-level restoration: not observed in the partial
   failure; both windows reported the expected values after cancel.
4. Key-window state: not distinguished. Both working and partially failing probes
   were non-key, as intended for nonactivating panels.
5. WindowServer ordering at desktop-icon level: still viable and not covered
   deterministically by this unattended harness.

## Coverage limitation and recommendation

Production interactive widgets live at the desktop-icon window level. Arbitrary
foreground application windows legitimately win hit testing at those coordinates,
so an unattended test cannot deterministically click those widgets without changing
the user's desktop state. The probes use the existing `zBoost` placement mechanism
to run at floating level. This preserves the real `InteractivePanel` → AppKit →
SwiftUI path and all host transitions, but it cannot detect an ordering defect that
exists only at desktop-icon level.

No production behavior was changed and no root cause is claimed. The strongest
remaining lead is WindowServer ordering when panels either round-trip from floating
back to desktop-icon level during layout editing or are closed and immediately
recreated during reload. A follow-up investigation should capture front-to-back
`CGWindowListCopyWindowInfo` ranks for widget and Finder desktop windows before and
after those transitions in a controlled, unobscured desktop session. A permanent
fix should only follow if that probe predicts failure and restart recovery.

## Resolution (2026-07-14)

The desktop-icon-level ordering hypothesis was confirmed with
`CGWindowListCopyWindowInfo` against a live production process. Finder owns a
full-screen, alpha-1.0 window at exactly `kCGDesktopIconWindowLevel`; activating
Finder (any desktop click) reorders it above every widget panel at that level and
it then wins all hit testing — every interactive widget goes dead simultaneously,
and a restart recovers because new windows are ordered front. The fix bases
elevated widgets (interactive or positive `zBoost`) at
`kCGDesktopIconWindowLevel + 1`; WindowServer never reorders across levels, so
Finder cannot climb above them. See `CLICK_FAILURE_HANDOFF.md` for the full
capture and verification.
