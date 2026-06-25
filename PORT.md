# Roplica — Features to Port onto the Argon Fork

This fork is **vanilla Argon v2.0.29**. The previous from-scratch implementation lives in `../roplica-old/`. Argon already provides most of the engine work the old codebase had to build by hand (reflection layer, middleware dispatch, name encoding, VFS echo suppression, installer/updater, CI, large-place perf), so those are **not** listed here.

This file lists only the features the old codebase had that **Argon lacks** and that are worth bringing over. Port *concepts*, not the old Rust — the old daemon was a worse engine.

Legend: **Effort** = rough size. **Refs** = blueprint files in `../roplica-old/`. **Target** = where it lands in this fork.

---

## 1. Core sync features

### 1.1 `roplica doctor` — drift / health report
- **What**: offline command that reports project divergence in four classes: orphan folders (in `src/`, not in snapshot), unindexed instances (no stable id), FS↔snapshot divergence, duplicate-name siblings. `--live` mode pulls a fresh snapshot from Studio first.
- **Why**: trust/UX. Turns "sync feels broken" into a concrete actionable report. Argon has nothing comparable.
- **Effort**: Medium. Builds on existing diff plumbing.
- **Refs**: `roplica-old/src/cli/doctor.rs`, `roplica-old/src/sync/diff/*`.
- **Target**: new `src/cli/doctor.rs`, wire into `src/cli/mod.rs`. Diff logic over `src/core/snapshot.rs` + `src/core/tree.rs`.

### 1.2 Terrain live sync
- **What**: live voxel sync over the wire. Argon has **zero** terrain support. Old codebase synced terrain as voxel JSON (`{resolution, min, size, materials[], occupancy[]}`) because the Studio plugin cannot read/write the `.rbxm` `SmoothGrid` blob — only `Terrain:ReadVoxels` / `WriteVoxels`. Kept separate from any offline rbxm path.
- **Why**: pure capability gap, no conflict with Argon's design.
- **Effort**: Medium. New daemon handler + plugin handlers + CLI subcommand.
- **Refs**: `roplica-old/src/daemon/handlers/terrain.rs`, `roplica-old/src/watcher/terrain_change.rs`, `roplica-old/src/sync/diff/terrain.rs`, `roplica-old/plugin/src/handlers/terrain/` (RequestTerrain.luau, PushTerrain.luau).
- **Target**: server handler under `src/server/`, plugin handlers under `roplica-roblox/src/Core/`, CLI `src/cli/terrain.rs`.
- **Caveats**: single `ReadVoxels` call has a region-size cap; chunking for huge terrains was deferred. Hash the voxel file so the daemon's own write-back is a no-op.

### 1.3 Stable wire identity on every entity (`roplica_id`)
- **What**: persistent id stamped on every instance **and** every leaf script, carried on the wire. Survives renames; disambiguates duplicate-name siblings without path-walk clobber.
- **Why**: Argon uses a per-session `Ref` that regenerates unless project-pinned. Stable ids on everything is something Argon's model can't cheaply match.
- **Effort**: High. Touches meta files, plugin id-sweep, and the snapshot/diff path.
- **Refs**: old `meta.json` id pattern + leaf-script sidecar `<name>.luau.meta.json`; `roplica-old/src/daemon/fs_sync/index.rs`, `instance.rs::stamp_instance_id_batch`, `script.rs`; plugin id-sweep handler.
- **Target**: extend `src/core/meta.rs` + `src/middleware/data.rs`; plugin sweep under `roplica-roblox/src/Core/`.
- **Verify first**: confirm Argon's project-pinned refs don't already cover your duplicate-sibling pain before committing to the full build.

### 1.4 FS-wins conflict logging
- **What**: when the same instance is edited on both sides inside the sync window, emit an explicit `⚠ conflict` warn line and apply the FS value. Argon resolves silently via VFS pause.
- **Why**: cheap, high-trust. User sees collisions instead of silent last-writer-wins.
- **Effort**: Low–Medium.
- **Refs**: `roplica-old/src/daemon/fs_sync/guard.rs` (`WriteVerdict::{Echo,Conflict,Clean}`, `classify_write`), the four content watchers under `roplica-old/src/watcher/content/`.
- **Target**: hook into `src/core/processor/` write path + `src/vfs/`.

### 1.5 Reflection canonicalization (only the gap)
- **What**: canonicalize property values to kill float-drift echo churn: Color3uint8 quantized to the 0–255 grid, floats truncated to 6 decimals, enums normalized to a single tagged form.
- **Why**: stable on-disk form, idempotent, echo-guard safe.
- **Effort**: Low — **if** needed at all.
- **Verify first**: Argon's `src/resolution.rs` + `rbx_dom_weak` Variant pipeline may already canonicalize. Grep before porting; only fill the gap.
- **Refs**: `roplica-old/src/roblox/reflection/normalize.rs`, `roplica-old/src/reflection.rs` (`check_property` → canonical `Accept(Value)`).

### 1.6 Script content drift detection (fnv1a-32)
- **What**: detect script content drift via an fnv1a-32 hash computed byte-identically on both sides. Plugin rehashes the live `Source`; diff renders "M / content drift". Argon's diff is presence-only and misses same-path content changes.
- **Why**: `status` / `doctor` accuracy.
- **Effort**: Medium. Needs a Luau hash byte-identical to the Rust hash (32-bit so it round-trips through Luau's f64).
- **Refs**: `roplica-old/plugin/src/Hash.luau`, the `source_hash` plumbing in `roplica-old/src/daemon/messages.rs` + `bootstrap.rs`, `roplica-old/src/sync/diff/scripts.rs`.
- **Target**: hash helper in `roplica-roblox/src/Helpers/`, source_hash on the snapshot in `src/core/snapshot.rs`.

---

## 2. CLI commands (Argon has no equivalent)

Argon CLI today: `build config debug doc exec init plugin serve sourcemap stop studio update`. Add:

### 2.1 `status`
- **What**: drift report — A/M/D per file vs the last snapshot. Argon has **no** status command.
- **Effort**: Low–Medium. Reuse the diff plumbing built for `doctor`.
- **Refs**: `roplica-old/src/cli/status.rs`.

### 2.2 `push` / `pull`
- **What**: one-shot directional sync. Argon only offers bidirectional `serve`. Useful for CI and scripted flows.
- **Effort**: Medium.
- **Refs**: `roplica-old/src/cli/push.rs`, `roplica-old/src/cli/pull.rs`.
- **Verify first**: confirm `serve` + `sourcemap` don't already cover the scripted need.

### 2.3 `regenerate`
- **What**: rebuild `src/` wholesale from a Studio snapshot.
- **Effort**: Medium.
- **Refs**: `roplica-old/src/cli/regenerate.rs`, `roplica-old/src/daemon/fs_sync/reconcile.rs`.

### 2.4 `reflect`
- **What**: reflection DB inspection command (query class/property schema from the CLI).
- **Effort**: Low.
- **Refs**: `roplica-old/src/cli/reflect.rs`.

---

## 3. VS Code extension (surface gaps)

Argon ext today: `start stop run play exec openMenu` + project-file completion + menu. It lacks the inspection UI the old extension had.

### 3.1 Roblox instance tree view
- **What**: live Studio explorer rendered in the VS Code sidebar. Browse the hierarchy without Studio focused.
- **Effort**: Medium.
- **Refs**: `roplica-old/packages/roplica-vscode/src/roplicaTree.ts` (a.k.a. rblxTree), `daemonClient.ts`.
- **Target**: new tree provider in `roplica-vscode/src/`.

### 3.2 Properties view / panel
- **What**: inspect (and edit) instance properties from VS Code. Command `roplica.showProperties`.
- **Effort**: Medium.
- **Refs**: `roplica-old/packages/roplica-vscode/src/propertiesPanel.ts`.

### 3.3 Status bar item
- **What**: always-on sync state in the VS Code status bar. Argon surfaces state through the menu, not a persistent bar item.
- **Effort**: Low.
- **Refs**: `roplica-old/packages/roplica-vscode/src/statusBar.ts`.

### 3.4 `pull` in the command palette
- **What**: one-shot pull from VS Code (frontend for 2.2).
- **Effort**: Low.

**Keep from Argon ext**: `completion.ts` (project-file autocomplete) and the richer `menu` — do not replace these.

---

## Recommended order

1. `status` (2.1) — small, immediately useful, builds the diff plumbing the rest reuses.
2. `doctor` (1.1) — extends that plumbing; the trust UX.
3. Terrain (1.2) — pure gap, isolated, no design conflict.
4. VS Code tree + properties (3.1, 3.2) — biggest surface gap.
5. Script drift hash (1.6) + `regenerate`/`push`/`pull` (2.2, 2.3).
6. Stable ids (1.3) + conflict logging (1.4) — largest, do after the engine is understood.
7. Reflection canonicalization (1.5) — only if the Argon pipeline gap is real.

## Do NOT port (Argon already provides)
Reflection property layer, middleware dispatch table, reversible name encoding, Windows/reserved-name handling, VFS echo pause, installer/updater/distribution, CI, large-place perf, the offline `lune/` jobs (covered by Argon middleware + `build`), and the old Studio plugin GUI (Argon's `roplica-roblox` App/Pages/Widgets is richer).
