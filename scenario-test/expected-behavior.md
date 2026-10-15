# Expected behavior: same monitor model, different physical unit

## Scenario

1. Desk 1: a monitor of model type P is connected for the first time. The user sets the arrangement, chooses the main display, and sets a non-default resolution.
2. Desk 2: a different physical unit of the same model type P is connected. Nothing else changes.

This document states what the Deskjockey build in this worktree should do at desk 2, and the assumptions the behavior rests on. The build under test is the uncommitted refactor plus debug logging and the HiDPI mode-enumeration fix (see CHANGELOG, Unreleased).

## Baseline: macOS without Deskjockey

macOS keys display settings by each physical unit's own serial (EDID). A different unit of model P is a new display:

- it gets the panel's default resolution, not the desk-1 choice;
- macOS places it adjacent to the current arrangement (typically to the right);
- the main display stays on the built-in display; macOS never moves the main role to a newly connected display on its own.

The user would redo arrangement, main display, and resolution by hand at every desk change.

## Intended Deskjockey behavior

At desk 2, within a second of the connect, without user input:

- the monitor lands in the saved position;
- the main display switches to the saved choice;
- the monitor switches to the saved non-default resolution;
- desk-1 saved data and the desk-1 unit's identity record stay untouched;
- the desk-2 unit's serial is recorded, so the next desk-2 visit is an exact-identity restore.

## Mechanism

The refactor separates the setup's shape from the plugged-in hardware:

- Class: identified by the multiset of vendor/product IDs, for example {built-in, P}. One shared ScreenConfiguration holds the slots: targetFrame, targetMode (logical + pixel dimensions), mainSlotID.
- Instance: identified by model + serial. Holds which physical unit held which slot.

Event chain at desk 2:

1. The connection event invalidates the session. Observe computes `capture = sameConnections`, false after a connect, so the restore path runs. The default-mode, wrong-position state from macOS is treated as something to fix, not as new truth.
2. Both units of model P report the same vendor and product IDs, so `DisplaySetClassID.from(displays)` matches the saved class.
3. The desk-2 serial is unknown, so exact instance lookup fails. `SlotAssignmentResolver` assigns by elimination: one P display, one P slot. The assignment is complete; the desk-1 instance record is not touched.
4. The plan carries the saved frames, main slot, and target mode.
5. The saved mode differs from the live default mode, so `selectMode` enumerates the mode list. With the duplicate-low-resolution option, scaled modes are listable; logical + pixel matching selects the saved mode.
6. Both displays stage origin and mode in one CG transaction and commit together. The result is verified before success is recorded. On failure nothing moves and the saved class is untouched.
7. On success the desk-2 serial is persisted as a known instance.

## Assumptions that require real hardware

| # | Assumption | Falsified by |
|---|---|---|
| A1 | Two units of model P report the same vendor/product IDs | different `class_id` at desk 2; a new class is captured instead |
| A2 | The desk-2 unit reports a readable, non-zero serial different from desk 1's | `missing_serial` warn; `session_only_identity` instead of `instance_identified` |
| A3 | The desk-2 unit's mode list contains the saved non-default resolution | `mode_candidates_empty` |
| A4 | The connect is one clean connection event; no same-connection capture runs before the restore (the 1 s settle suffices) | `class_configuration_updated` appearing before `configuration_applied` |
| A5 | macOS accepts origin and mode for both displays and does not adjust them after commit | `verify_mismatch` or `operation_failed` after `apply_started` |
| A6 | Setting origin (0,0) transfers the main-display role on this macOS version | post-apply `display_input` still showing `main=false` on the external |
| A7 | The desk-2 serial is persisted after success | no `instance_saved` after `display_set_database_saved` |
| A8 | CG delivers `addFlag` (a connection event), not a reshape-only event | `connection_fired=false` in the `display_change_flags` line |

## Scope limits of this build

- Restore path only. The per-size layout memory (PR #3 second half) is not included: changing the resolution during the test updates the class configuration and the old-size layout is not remembered.
- One unit of model P. With two identical units, left/right slot mapping for new serials is not guaranteed to match desk 1.
- The built-in display is restored only if its saved mode equals the live mode (short-circuit); the built-in's mode is not switched by the plan.
