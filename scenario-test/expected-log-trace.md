# Expected log trace: same monitor model, different physical unit

The app logs to `~/Library/Logs/Deskjockey/deskjockey.log`. Every line is
`[yyyy-MM-dd HH:mm:ss.SSS] [LEVEL] <message>`. Core-layer lines (DetectionLog)
are JSON objects with `detection_id` and `reason` keys. App-layer lines are
`event=...` key=value strings. `[DEBUG]` lines exist only in this build.

`runtime_id` is the live CGDirectDisplayID and changes between connections.
`detection_id` groups all lines of one coordinator run.

## Phase 1 - desk 1, first connect of model P

```
[INFO]  event=display_callback runtime_id=<id> flags=<flags>
[DEBUG] event=display_change_flags runtime_id=<id> change_flags=<raw> connection_fired=true
[DEBUG] {"reason":"connection_invalidated",...}
[DEBUG] {"reason":"command_decision","command":"observe","same_connections":"false","capture":"false",...}
[DEBUG] {"reason":"observation","count":"2",...}
[DEBUG] {"reason":"display_input", "runtime_id":"...", "model_id":"vendor=... product=...", "serial_number":"<S1>", "origin":"<macOS default>", "logical_size":"...", "pixel_size":"...", "main":"false", ...}
[INFO]  {"reason":"class_detection","class_id":"<CLASS>",...}
[INFO]  {"reason":"new_class_capture",...}        # or legacy_live_mapping / legacy_unresolved if v1 profiles exist
[INFO]  {"reason":"instance_identified","persistent_identity":"true",...}
[INFO]  {"reason":"display_set_database_saved",...}
[INFO]  {"reason":"instance_saved",...}
```

No apply happens on first capture.

## Phase 2 - desk 1, user edits arrangement, main display, resolution

Each System Settings edit fires CG events. Per edit burst:

```
[INFO]  event=display_callback ...                       # several, per event
[DEBUG] event=display_change_flags ... connection_fired=false
[DEBUG] {"reason":"command_decision","command":"observe","same_connections":"true","capture":"true",...}
[DEBUG] {"reason":"observation","count":"2",...}
[DEBUG] {"reason":"display_input", ... }                  # the edited values
[INFO]  {"reason":"class_detection","class_id":"<CLASS>",...}
[INFO]  {"reason":"known_class",...}
[INFO]  {"reason":"class_configuration_updated","origin":"external_or_unknown",...}
[INFO]  {"reason":"instance_identified","persistent_identity":"true",...}
[INFO]  {"reason":"display_set_database_saved",...}
[INFO]  {"reason":"instance_saved",...}
```

A pure drag with no size change after the save logs `instance_permutation` with
`class_configuration=unchanged` instead. The final saved class holds the user's
arrangement, main slot, and non-default mode.

## Phase 3 - desk 2, connect a different physical unit of model P

```
[INFO]  event=display_callback runtime_id=<id> flags=<flags>
[DEBUG] event=display_change_flags runtime_id=<id> change_flags=<raw> connection_fired=true
[DEBUG] {"reason":"connection_invalidated",...}
[DEBUG] {"reason":"command_decision","command":"observe","same_connections":"false","capture":"false",...}
[DEBUG] {"reason":"observation","count":"2",...}
[DEBUG] {"reason":"display_input", "serial_number":"<S2>", "origin":"<macOS default>", "logical_size":"<default>", "pixel_size":"<default>", "main":"false", ...}
[INFO]  {"reason":"class_detection","class_id":"<CLASS>",...}      # SAME class_id as phase 1/2
[INFO]  {"reason":"known_class",...}
[DEBUG] {"reason":"known_device","runtime_id":"<built-in>","slot_id":"<n>",...}     # built-in: serial matches desk-1 instance
[DEBUG] {"reason":"elimination","runtime_id":"<external>","slot_id":"<n>",...}    # new serial, one P display, one P slot
[DEBUG] {"reason":"apply_target","runtime_id":"<external>","origin":"<saved>","logical":"<saved>","pixel":"<saved>","is_main":"true","slot_id":"<n>",...}
[DEBUG] {"reason":"apply_target","runtime_id":"<built-in>","origin":"<saved>","logical":"...","pixel":"...","is_main":"false","slot_id":"<n>",...}
[INFO]  {"reason":"apply_started","display_count":"2",...}
[DEBUG] event=mode_already_current runtime_id=<built-in>          # built-in target equals live mode
[DEBUG] event=mode_enumeration runtime_id=<external> count=<N>    # scaled modes now listable
[DEBUG] event=mode_selected runtime_id=<external> logical=<WxH> pixel=<WxH> refresh_rate=<r> candidates=<k>
[DEBUG] {"reason":"observation","count":"2",...}                 # post-apply re-observation
[DEBUG] {"reason":"display_input", "runtime_id":"<external>", "origin":"<saved>", "pixel_size":"<saved>", "main":"true", ...}
[INFO]  {"reason":"configuration_applied","verified":"true",...}
[INFO]  {"reason":"instance_identified","persistent_identity":"true",...}   # S2 recorded
[INFO]  {"reason":"display_set_database_saved",...}
[INFO]  {"reason":"instance_saved",...}
```

## Phase 4 - desk 2, next connect of the same unit (optional confirmation)

Same as phase 3, except the assignment reasons are:

```
[DEBUG] {"reason":"exact_instance","runtime_id":"<external>","slot_id":"<n>",...}
```

## Pass criteria

| Check | Evidence |
|---|---|
| A1 class matches across units | `class_detection` class_id identical in phases 2 and 3 |
| A2 readable new serial | phase-3 `display_input` serial_number = S2; `instance_identified` persistent_identity=true |
| A3 saved mode exists on unit 2 | `mode_selected` with the saved logical/pixel values |
| A4 clean event, no premature capture | phase 3 order: `connection_invalidated` then `command_decision` capture=false; no `class_configuration_updated` before `configuration_applied` |
| A5 macOS keeps the applied state | post-apply `display_input` rows equal the `apply_target` rows; no `verify_mismatch` |
| A6 main role transfers | post-apply external `display_input` `main=true` |
| A7 instance persisted | `display_set_database_saved` then `instance_saved` in phase 3 |
| A8 connection event delivered | `connection_fired=true` in phase 3 |

## Failure signatures

| Line | Meaning |
|---|---|
| `mode_candidates_empty` | A3 false: unit 2 lacks the saved mode (or it is not GUI-usable) |
| `verify_mismatch` / `operation_failed` after `apply_started` | A5 false: macOS adjusted or rejected the commit |
| `session_only_identity` | A2 false: serial unreadable or zero |
| `class_configuration_updated` during phase 3 before `configuration_applied` | A4 false: a capture ran on the connect state |
| `connection_fired=false` on the connect | A8 false: CG reported a reshape, not a connection |
| `duplicate_serial`, `missing_serial` warns | identity data problems; check EDID/hub |
