# Intended behavior

## Revision 2: class-owned screen configuration

This document records the intended behavior. The implementation status appears below.
It replaces the earlier proposals for instance-specific settings, explicit class approval, and a stop on uncertain left/right order.
This is a behavior revision, not an application release or persistence schema version.

The governing rule is:

**The class owns the screen configuration. The instance owns the assignment of physical displays to class slots.**

System Settings remains the normal interface for display settings.
Deskjockey observes changes, remembers the shared configuration, and restores it when a compatible display set connects.
A known class always receives a complete assignment when the live displays and saved slots are valid and compatible.
Uncertain physical order alone does not prevent application.

## Definitions

### Display model

A display model is the hardware model reported by the display provider.
Its identity is the pair of vendor ID and product/model ID, not the display name.
On macOS, the source APIs are `CGDisplayVendorNumber` and `CGDisplayModelNumber`.

Display names remain presentation labels.
No rule strips `(1)`, `(2)`, or any other name suffix to infer model identity.
Unknown or generic identifier values do not establish a hardware model.

### Display set class

A display set class is an unordered collection of identified display models, with a count for each model.
Two sets belong to the same class when those model identities and counts match.
Serial numbers, cable order, logical unit numbers, and current settings do not define the class.

The definition includes the built-in display when it participates in the display set.
Its built-in role is explicit metadata, not an inference from its name.
Under this model-based definition, different identified built-in models belong to different classes.
The implementation uses the identified built-in model, not a canonical display-name string.

A class owns one current screen configuration and its slots.
Multiple instances share that configuration.

### Display set instance

A display set instance is a particular unordered collection of physical display devices within a class.
A usable model-and-serial identity distinguishes a physical device from another device of the same model.
A persistent instance requires enough evidence to distinguish the complete collection without collisions.

An instance stores the assignment of its physical displays to the class slots.
It does not store separate resolution, geometry, alignment, or main-display preferences.
There are no instance overrides of the class configuration.

An instance identifies devices, not a desk location or dock.
The same devices remain the same instance after a cable change, provided their reported identities remain stable.
A replacement device produces a new instance even when its model remains unchanged.

Missing or duplicate serials can prevent persistent instance identification without preventing class identification.
In that case, Deskjockey can still assign and configure the current displays through their runtime IDs.
It must not invent a permanent physical identity or promise exact recognition on reconnect.

### Slot

A slot is a stable reference within a class for one display of a specified model.
A slot is neither a physical monitor nor a connector on a hub.

Each slot owns target settings through the class configuration.
Its reference remains stable when those settings change.
Identical models can exchange slots; different models cannot exchange slots within the same configuration.

### Screen configuration

A screen configuration is the complete target state of the class slots:

- The target resolution and scaling for each slot.
- The relative positions of all slots.
- Their alignment, represented by the relative geometry rather than a separate competing value.
- The slot that acts as the main display.

Resolution and scaling are settings, not model identity or native panel specifications.
The representation must distinguish logical desktop dimensions from pixel dimensions where required to restore the selected mode.
Relative geometry and an explicit main slot prevent a coordinate-origin change from masquerading as a different layout.

All changes to these settings belong to the class.
They apply to every instance on its next restore, through that instance's assignments.
A device-specific capability failure can prevent application; it does not create an instance override.

This definition includes all participating slots.
Built-in scaling uses the same target-mode validation as external scaling. An unavailable mode prevents application and produces a diagnostic.
Brightness, colour profiles, HDR, refresh-rate preferences, rotation, and mirror mode are outside this revision's managed settings.

## Ownership and current code names

| Concept | Owner | Implementation |
| --- | --- | --- |
| Model identity | Reported hardware model | `DisplayModelID` contains vendor and product IDs. |
| Class identity | Display set class | `DisplaySetClassID` contains sorted model IDs and retains counts. |
| Shared screen configuration | Display set class | `DisplaySetClass.configuration` is a `ScreenConfiguration`. |
| Slot settings | Screen configuration | `DisplaySlot.targetFrame` and `targetMode`. |
| Main slot | Screen configuration | `ScreenConfiguration.mainSlotID`. |
| Physical device identity | Display set instance | `DisplayDeviceID` combines model ID and serial. |
| Instance assignment | Display set instance | `DisplaySetInstance.assignments`, stored in `DisplaySetClass.instances`. |
| Live observation | Neither saved owner | `DisplaySnapshot`. |
| One display's apply command | Neither saved owner | `DisplayApplyTarget`. |
| Complete apply command | Neither saved owner | `DisplayApplyPlan`. |

Names are presentation labels. They do not participate in class or instance identity.
Legacy names remain only in the version-one compatibility boundary.

## Detection and application

### Known instance in a known class

1. Identify the class from model identities and counts.
2. Look for an exact persistent instance match.
3. Reuse that instance's saved device-to-slot assignments.
4. Apply the current class configuration through those assignments.

The current class configuration takes precedence over the settings seen on the previous visit.
A reliable exact instance match takes precedence over assignments inferred from other instances.

### New instance in a known class

Use the best available evidence within each model group:

1. Reuse compatible known device assignments where they do not conflict.
2. Use elimination when only one display and one slot remain.
3. Use logical unit information as a weaker hint, never as physical left/right evidence.
4. Assign all remaining displays to remaining slots in a deterministic order.
5. Use an arbitrary tie-break when the available persistent data cannot distinguish those displays.

A stable runtime-ID order is preferable to random numbers for the final tie-break.
It makes the current decision reproducible without claiming stability across reconnects.
The result must be one-to-one: one display per compatible slot, with no display or slot omitted.

Apply the class configuration after assignment.
Do not require user approval just because the physical order is unknown.
Record the assignment for the instance when persistent identity is available.
Otherwise, retain the assignment for the current connection without a claim of durable recognition.

This is an intentional trade-off: the initial physical order can be wrong.
The user can correct that order through System Settings or the swap shortcut.

### Unknown class

Capture the current valid configuration as the class configuration once the display set settles.
Create slots and an assignment from that observation.
Record the instance when its devices are identifiable.

This behavior applies both at launch and after a new display set connects.
It does not require a draft, approval dialog, or separate save operation.
A subsequent change in System Settings updates the configuration automatically.

A failed database read is not an unknown class.
Do not overwrite existing data when the store cannot establish whether the class already exists.

## How configuration changes become authoritative

Keep the current learning policy:

- Coalesce rapid display-change notifications before evaluation.
- While Deskjockey applies a configuration, do not capture its intermediate states as a new configuration.
- Outside that operation, treat a valid change on an unchanged display set as authoritative.
- Do not attempt to prove whether System Settings, macOS, or a driver initiated that change.

An authoritative configuration change updates the class, not an instance override.
A class update preserves the identities of its slots and the assignments of all instances.
A model or count change triggers class detection instead of modifying the membership of the old class.

This policy knowingly permits an automatic macOS adjustment to become the saved configuration.
The software must not describe that observation as a confirmed user edit.
Logs should identify its origin as external or unknown unless the origin is actually known.

## Screen swaps versus configuration edits

A swap exchanges the physical displays assigned to compatible class slots.
It preserves every slot's target settings, including the main-slot selection.
Only the current instance's assignment changes.
Other instances keep their assignments.

System Settings remains the default editor, so the same distinction must work for observed changes there.
Use a complete comparison against the existing class configuration:

- If the observation is exactly a permutation of identical-model displays across unchanged target slots, update the instance assignment only.
- If any target settings change beyond that permutation, update the class configuration through the existing assignments.
- Do not infer a pure swap from horizontal coordinates alone; compare modes, relative geometry, and the main slot together.

The pure-permutation rule compares an observed edit against an existing configuration.
It does not use current positions to guess physical left/right when a new instance connects.

An explicit swap command has known scope even when its target slots have different modes.
It exchanges assignments and reapplies the complete target settings of the destination slots.
The shortcut accepts identical models with different target modes when both displays support their destination modes.

### Example

A class has a laptop slot and two external slots of the same model.
The left external slot is the main display.
Instance A assigns serial 72 to the left slot and serial 177 to the right slot.
Instance B has different serials and its own assignments.

A swap in instance A exchanges serials 72 and 177 between the two external slots.
The left slot remains the main slot; instance B does not change.

A resolution or alignment edit changes the class configuration.
Both instances use the new targets on their next restore.

## Graceful fallback and diagnostics

Distinguish uncertain assignment from invalid operation:

- Unknown physical order in a reliably identified class triggers a complete fallback assignment and application.
- Missing serials prevent durable instance recognition, not necessarily application of a known class.
- Missing model identity can prevent reliable class selection.
- Missing displays, invalid saved slots, unsupported modes, or system failures can prevent safe application.
- A storage failure must not masquerade as an absent display set class or a successful save.

Input and operational failures do not produce user-facing error dialogs.
Preserve valid saved data when an operation cannot complete.
Do not claim that requested settings were applied when the system rejected or adjusted them.
Validate the observed result, because macOS can adjust requested geometry.

Logs must explain each detection attempt through a shared detection ID and stable reason codes.
Record raw and interpreted identifiers, class and instance results, assignment choices, and the final outcome.
Record why each fallback or skipped operation occurred.
Differentiate an expected new instance from malformed data or an API failure.

An arbitrary assignment is an explicit successful fallback, not a hidden failure.
A suitable record includes `reason=unresolved_order`, the selected assignment, and whether the instance is persistently identifiable.

## Implementation status

The class/instance model replaces the earlier name-based profile keys and numeric-suffix migration.
The application uses typed vendor/model identities, exact-instance precedence, and complete fallback assignments.
System Settings edits update the shared configuration; pure permutations update only the instance assignment.

The coordinator serializes observation, application, readback, and persistence.
The macOS adapter preflights every display and submits all mode and origin changes in one CoreGraphics transaction.
An adjusted or failed application does not overwrite the saved class configuration.
Connection notifications invalidate session assignments even when a driver reuses runtime IDs.

The version-two database retains version-one records in `legacyProfiles`.
The first conversion also preserves the original bytes in a `profiles.json.v1-backup` file.
Only an unambiguous live correspondence can reuse a legacy configuration.
Unresolved or conflicting legacy configurations remain intact; the app captures the observed class instead of guessing a conversion.
Corrupt files, unsupported schemas, and detected external edits prevent a save.

Display failures go to logs, not error dialogs.
Detection records contain a detection ID, reason code, raw observations, assignment evidence, and the outcome.
Callbacks also record their display IDs and change flags.

### Validation boundaries

- Persistent recognition requires usable, distinct model-and-serial identities.
- Unknown or generic model identifiers prevent class-based automatic application.
- Mirror mode and rotated geometry are not managed; unsupported observations remain unchanged.
- Target logical and pixel dimensions must both match an available mode.
- Driver-generated identities can change across reconnects; no physical identity guarantee overrides the reported evidence.
- Unit tests cover domain behavior and failure paths with simulated displays. Real hardware still requires a manual restore and swap check.

### Source references

- [Models](Sources/DeskjockeyCore/DisplaySetModels.swift): typed identities and ownership.
- [Configuration logic](Sources/DeskjockeyCore/ScreenConfigurationLogic.swift): validation, capture, permutations, and complete plans.
- [Slot resolver](Sources/DeskjockeyCore/SlotAssignmentResolver.swift): exact instance and fallback assignment.
- [Coordinator](Sources/DeskjockeyCore/ScreenConfigurationCoordinator.swift): serialized operations and persistence.
- [Display set store](Sources/DeskjockeyCore/DisplaySetStore.swift): versioned, atomic storage and backups.
- [Legacy conversion](Sources/DeskjockeyCore/LegacyProfileMigration.swift): conservative live conversion without name parsing.
- [Diagnostics](Sources/DeskjockeyCore/DetectionLog.swift): correlated diagnostic records.
- [Runtime](Sources/DeskjockeyApp/Runtime.swift): macOS observation and atomic application.

## Acceptance examples for implementation

1. The same vendor/model IDs with different display labels still identify the same class.
2. New serials in a known class always receive compatible slots when the inputs support a valid complete plan.
3. An arbitrary assignment can be corrected without changing the class configuration.
4. A known instance returns to its saved assignments even after another instance of the class was used.
5. A configuration edit through System Settings changes the class targets for every instance.
6. A pure permutation through System Settings changes only the current instance's assignment.
7. The main slot and target modes remain unchanged by an assignment swap.
8. An unknown class is captured after connection as well as at launch.
9. Missing serials do not block a valid class restore or create a false promise of persistent identity.
10. Invalid model data, unavailable modes, and failed database reads preserve valid data and produce explicit logs without error dialogs.
11. Migration preserves distinct saved layouts and assignment evidence when conversion is ambiguous.
