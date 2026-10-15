# Evaluator instructions: desk-swap scenario test

You are evaluating a hardware test of Deskjockey, a macOS menu bar utility that saves and restores multi-monitor arrangements (Swift, macOS 13+). This file gives you the context to judge the result. Read all three files in this folder.

## What is under test

The git worktree at the test location holds an uncommitted refactor of the display pipeline, plus debug-level logging and a HiDPI mode-enumeration fix, all already implemented and passing `swift test` (48 tests, 0 failures). Do not treat the installed `/Applications/Deskjockey.app` as the test subject: it is the released v1.2.0 build and predates all of this work.

Architecture in one paragraph: a display *class* is identified by the multiset of vendor/product IDs of the connected displays; one shared configuration per class stores each slot's target frame, target mode (logical + pixel), and the main slot. A physical *instance* is identified by model + serial and records which unit held which slot. On a connect, the app takes the restore path (never capture), resolves slot assignment (exact serial, then known device, then elimination), and applies all displays in one validated CoreGraphics transaction. A mode is selected by enumerating with `kCGDisplayShowDuplicateLowResolutionModes` (so scaled modes are listable) and matching logical + pixel dimensions, ranked by nearest refresh rate.

## Before the test

1. Quit the running Deskjockey (released v1.2.0). Two instances would fight over `~/Library/Application Support/Deskjockey/profiles.json`. Note: that file currently holds v1-format profiles, one of which was corrupted by the v1.2.0 bug on 2026-10-15; the new build migrates v1 profiles with an exact backup on first run.
2. Build from the worktree. Follow `DEVELOPMENT.md` (XcodeGen + Xcode; `project.yml` is the source of truth). For a quick run, `swift build` produces `.build/debug/DeskjockeyApp`.
3. Note the current log size or back up `~/Library/Logs/Deskjockey/deskjockey.log` so the test section is unambiguous.

## Test procedure

1. Run the new build.
2. Desk 1: connect the first physical unit of monitor model P. Set the arrangement, choose the external as main display, and set a non-default resolution. Wait a few seconds after each change.
3. Desk 2: disconnect, connect a different physical unit of the same model P. Wait about five seconds. Do not touch any settings.
4. Optional: disconnect and reconnect the same desk-2 unit to confirm exact-identity assignment.
5. Collect `~/Library/Logs/Deskjockey/deskjockey.log` (test section) and `~/Library/Application Support/Deskjockey/profiles.json`.

## Evaluation

Compare the log against `expected-log-trace.md`, phase by phase. For each assumption A1-A8 in `expected-behavior.md`, mark pass or fail with the exact log lines as evidence. The trace tables list both the passing evidence and the failure signature for each assumption.

Also verify visually: at desk 2 the monitor must sit in the saved position, be the main display, and run the saved resolution without user action.

Be strict about ordering in phase 3: `connection_invalidated` and `command_decision` with `capture=false` must precede everything, and `class_configuration_updated` must not appear between the connect and `configuration_applied`. If it does, a capture ran on macOS's default state — that is failure A4, the most dangerous one, because it silently overwrites the saved arrangement.

## Known limits - not failures

- A resolution change made during the test updates the class and does not remember the old-size layout. Per-size layout memory is future work.
- With two identical external units, left/right mapping for new serials is not guaranteed.
- The built-in display's mode is never switched; it is restored only when saved mode equals live mode (short-circuit).
- The first run migrates any v1 `profiles.json` to version 2 and keeps an exact backup.

## Report format

Report phase by phase: the observed log sequence (trimmed to the relevant lines), the A1-A8 table with pass/fail and evidence, the visual check results, and any failure signature with its meaning from the trace file. Distinguish what the log proves from what you inferred. Do not modify any source files; if something needs a code change, report it instead.
