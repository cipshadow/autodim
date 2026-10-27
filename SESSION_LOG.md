# AutoDim session log

### 2026-10-27 — Recover tint synchronization after display gamma resets

**Goal:** Diagnose and repair the external screen's red tint differing from the built-in screen.

**What we did:**
- Confirmed different live gamma tables, then confirmed restart restores matching tables.
- Reproduced failed recovery by resetting the built-in table while the scheduled target stayed unchanged.
- Forced the existing 30-second timer refresh to reapply gamma. The live recovery check failed on the original app and passed on the updated installed app.
- Built and installed the signed universal app at `/Applications/AutoDim.app`. Schedule and hardware-brightness checks passed. The production fix is one line; reviewed manually without additional simplification.

**Learned:** A cached tint target cannot establish the display's current gamma state. The original reset trigger remains unknown; recovery now occurs on the next timer refresh (30 seconds, 5-second tolerance).

**Pending:** Review and merge the draft PR, then release. The physical-display recovery check is opt-in and requires an active, stable, non-neutral phase.

**Files involved:** `DisplayFilter/AppState.swift`, `Checks/GammaRecovery.swift`, `README.md`.

**How to continue:** Use branch `fix/display-tint-recovery`. Run `./build.sh check`; run `swift Checks/GammaRecovery.swift` with AutoDim active to reproduce recovery on hardware. Timing omitted because the session-time helper selected an unrelated transcript on its final run.
