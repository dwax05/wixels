# Claude handoff: Wixels v0.2.0 public-beta release

This is a release handoff, not approval to publish. Prepare the release from the
current worktree, verify it, then stop for human approval before pushing a tag or
creating the GitHub pre-release.

## Scope to review

The worktree is intentionally dirty and contains two related bodies of work:

- Group-scoped widget layouts:
  - `desktop.toml` now retains enablement, options, theme, ordering, group
    membership, and stable widget IDs.
  - Placement is persisted in
    `~/.config/wixels/layouts/<UTF-8-hex-group-name>.toml`.
  - Placement resolution is group layout record, then legacy config placement,
    then widget default.
  - First layout persistence assigns deterministic per-group IDs (`clock`,
    `clock-2`, …) and migrates legacy placement fields out of `desktop.toml`.
  - Layout edits and resets write only the affected mounted group(s), and the
    layouts directory is watched for external changes.
- The already-present package/menu, plugin, theme, and release-packaging changes
  shown by `git status`. Treat them as candidate v0.2.0 work, but review them
  independently; do not discard, reset, or overwrite them.

The primary layout files are:

- `Sources/wixels/LayoutStore.swift`
- `Sources/wixels/Config.swift`
- `Sources/wixels/Host.swift`
- `Sources/wixels/main.swift`
- `Sources/wixels/ConfigTestSuite.swift`

## Required review and validation

1. Inspect the full diff and split it into coherent commits. Keep unrelated changes
   separate from the group-layout feature. Preserve all existing user changes.
2. Review the migration path carefully, especially duplicate kinds, folder-less
   legacy entries, disabled entries, and package switching.
3. Run the baseline checks:

   ```sh
   swift build
   ./.build/debug/wixels --config-tests
   ./.build/debug/wixels --interaction-tests
   git diff --check
   ```

4. Build and validate release artifacts:

   ```sh
   ./package-app.sh 0.2.0
   ./package-extension-pack.sh 0.2.0 Cynaberii
   ./package-extension-pack.sh 0.2.0 Macos
   ```

5. Manually verify on a clean Apple-silicon macOS 14+ account:
   - Install the host plus each extension pack and complete the quarantine flow.
   - Switch between Cynaberii and Macos when both provide a widget of the same
     kind; confirm each group restores its own position.
   - Configure duplicate widgets of one kind, move both, reorder their config
     rows, and confirm IDs preserve the two positions.
   - Start from legacy placement fields, make one layout edit, and confirm the
     active group receives a layout file while `desktop.toml` receives IDs and
     loses only migrated placement fields.
   - Edit a group layout TOML externally and confirm the host reloads; make an
     in-app drag and confirm it does not recursively reload.

## Proposed GitHub pre-release notes

Wixels v0.2.0-beta.1 is an Apple-silicon public beta for macOS 14 or later. It is
ad-hoc signed, not notarized, and has no automatic updates.

New in 0.2.0:

- Widget layouts are now scoped to their plugin package. Cynaberii, Macos, and
  ungrouped widgets can use the same widget kind without sharing placement.
- Wixels stores placement in separate group layout files while keeping widget
  enablement, options, themes, and ordering in `desktop.toml`.
- Existing desktop placement settings migrate automatically the first time a group
  layout is saved. Duplicate widgets receive stable IDs so their positions survive
  reorder and package switching.
- Editing a group layout file externally reloads Wixels live.

Release assets:

- `Wixels-0.2.0-arm64.zip`
- `Wixels-Cynaberii-0.2.0-arm64.zip`
- `Wixels-Macos-0.2.0-arm64.zip`

## Release stop point

After all checks and manual verification pass, present the commit list, artifact
paths/checksums, and the proposed release notes for approval. Only then create and
push `v0.2.0-beta.1` and create the GitHub pre-release with the three ZIPs.
