---
title: Helicopter Setup
---

# Helicopter Setup

A guided helicopter setup in the same 19-step order as the Configurator wizard.
It is a separate page; the existing Setup Assistant is unchanged. Remove the main
and tail blades before bench work. Keep servos unplugged until the connection gate.

## Where to find it

*Configuration* → *Wizards* → *Helicopter Setup*.

The Wizards group is hidden until *System* → *Settings* → *General* → *Preview* →
*Setup Assistant* is enabled (`visibleWhen = "previewSetupWizard"` on the parent).
The page is greyed out until the flight controller answers
(`enabledWhen = "fblConnected"`), locked while armed (`lockedWhileArmed = true`),
and requires MSP API 12.09 or later (`minApiVersion = {12, 0, 9}`). It works from
the TOOLS menu and when the tool is hosted by the dashboard widget.

Receiver setup requires an already working receiver/MSP link. Run automatic
receiver wiring detection in USB Configurator: that test reinitializes the same
UART that carries the radio link. ESC wiring detection and board auto-alignment
remain available on the radio when supported by firmware.

## Loading and fresh status

A dedicated loading view shows bounded-read progress, a power reminder and Back.
Its progress updates in the existing scene. The model-preparation card shows a
short instruction; **?** retains the complete model checklist and active name.

A status older than three seconds immediately blocks editing. Active tests and
pending writes still fail closed and release overrides. During an idle read-only
visit, the page displays **Checking current FC status; controls paused** while the
fresh STATUS request completes. It does not extend the safety window. A failed
request displays an error and a receiver-link hint. **Try again** starts a new
arming-disable/readback handshake; the expired timestamp cannot abort that handshake.
Status processing continues during resumable scene assembly. Legacy override
warnings appear when a legacy hold is actually used, rather than during model preparation.

## Before the 19 steps

Every new setup visit first shows **Prepare the radio model**, outside the numbered
sequence. The active model name is displayed. Select **Rotorflight template** or
**Manually checked**, then confirm **Model checked**. Check the active transmitter
model, its control functions, channel outputs, throttle travel and switches. **?**
explains the full preparation and shows the unabridged model name. This screen
records a current pilot confirmation, not an automatic model audit; template use
alone cannot pass it. Receiver mapping is still checked in step 2.

The confirmation is deliberately not stored in per-FC history, because a board can
be used with another transmitter model. It is required again on every new complete
or individual setup visit, before loading the selected step or entering holds. The
history/reset page needs no model-configuration confirmation. The Configurator's
19 numbered steps and their order remain unchanged.

## Navigation

The Suite menu offers **Complete setup**, each of the 19 individual steps, and
**Setup history**. All entry points share the same lazy-loaded page: only the
selected step definition is loaded. Complete setup starts at step 1 in the original
order. An individual step starts directly, using current FC settings, and returns
to the Suite menu after completion. The step title also returns to that menu after
saving or discarding pending changes. RTN/EXIT follows the same Back route.

Direct configuration steps ask for blades removed and servos unplugged; direct
servo/control tests, including a servo tail, ask for blades removed and the servo
type/rate checked before entering their holds. Motor tests retain their own gates.
These confirmations do not validate the mechanics. An existing restart requirement
is handled before direct entry to a test after the connection gate: remove blades,
unplug servos, restart, then confirm the test prerequisites.

| Control | What it does |
| --- | --- |
| Back | Previous task. At the start of a step entered from the Suite, return to its menu, with Save/Discard when changes are pending. RTN/EXIT follows the same route. |
| Continue | Next task within this step; no EEPROM write. |
| Save & next | Commit this step and write EEPROM only when something changed. A refused or missing reply blocks advance. |
| Reboot | At the connection gate, keep servos unplugged until restart completes. |
| Finish | Save pending settings, release overrides, restore arming availability and leave. It never arms the model. |
| Hold | A momentary motor control. Releasing the button stops the motor; motor overrides also lapse in firmware without refresh. |
| ? | Full instructions for the current task and the navigation help. |

On 320- and 480-pixel displays, illustrated tasks put a compact mechanical sketch
beside at most four control rows. The 800×480 layout has a separate instruction
column and a larger sketch. Numbered swash links follow the selected 120/135/140/90L/90V
geometry without rebuilding the scene; Direct shows each servo function instead.
Board orientation, servo lift/neutral, roll/pitch/collective response, swash levelling,
blade-pitch reference and opposing gyro correction have distinct diagrams.
The final Board orientation card has its own layout: a live helicopter above the
confirmation on small screens, and a larger model beside it on 800×480. Tilt the
real helicopter right/left and nose down/up; the picture must follow. Roll and
pitch are secondary readouts. The fixed view omits heading and fits the complete
model into the available space even at steep tilts. No fresh attitude for two
seconds hides the picture and displays a waiting message. Confirmation remains
manual; a level picture cannot prove correct mounting.

This view uses the existing MSP attitude read. While checking orientation, reads
alternate attitude/status/attitude/servo at the existing request cadence, without
increasing total request frequency. Projection runs once per changed sample in
wakeup; native getters only read fixed point tables. No reply rebuilds the scene.

Receiver, mode and profile detection capture a fresh FC-channel baseline when the
button is pressed; stale/missing samples ask the pilot to wait. Receiver mapping
uses raw wire-order RX_CHANNELS. Modes/profiles use RC in the FC function order,
with the displayed channel translated back through RX_MAP. Throttle may be a
switch: record its OFF/ON positions and finish OFF. The current endpoint is included
immediately. Control checks show the requested direction, FC channel and expected
physical response; **?** explains the viewing reference and the servo-direction remedy.

The mode-switch drawing follows the actual assigned ARM input range or the FC's
Rescue/Trainer flag. It shows unavailable input neutrally. ARM feedback describes
the switch while the wizard inhibits arming. The profile-switch reference stays
still. Servo pulse references cache custom Hz/width geometry on settings edits;
the native getters do not generate waves. Timing beyond the pulse limit displays
a restart/readback hint instead of a physically impossible waveform. Receiver bars and control-command meters already follow live inputs;
swash diagrams follow the selected geometry. All other mechanical drawings remain
test references: commanded output or board attitude cannot measure actual servo,
swash, blade or gyro-correction movement. Verify these on the real helicopter.
The short instruction area may show only its first lines; **?** opens the full text.

## Step sequence and settings

| # | Step | Controls and checks |
| --- | --- | --- |
| 1 | Board orientation | Confirm servos unplugged and all blades removed. Calibrate the accelerometer with the model level and still. Detect orientation by lifting the tail, or enter roll, pitch and yaw in degrees. After restart, compare the live helicopter model with real roll/pitch movements and confirm the directions. Automatic alignment requires firmware support. |
| 2 | Receiver | Keep the established receiver UART; protocol configuration remains available, and use USB Configurator for receiver wiring detection (the trial interrupts the radio MSP link). Save & reboot is available here. Detect roll, pitch, yaw, collective and throttle channel mapping one stick at a time, or select ELRS, FrSky, Futaba/Hitec or DSM/Graupner/JR presets. Check FC channel numbers and rising values for roll/yaw right, pitch forward and collective up. Detection uses a fresh pre-click snapshot, so an immediate stick/switch movement is retained. Record all throttle-switch positions (or both proportional endpoints), starting and finishing OFF, with at least 300 µs travel; Use measured range adds a 20 µs margin at each end. Zero limits select firmware defaults. Throttle is low compares the mapped input with the low threshold; it is not permission to arm. |
| 3 | Mode switches | Assign ARM, RESCUE and TRAINER when the FC exposes them. Move the switch to its intended ON position; a clear AUX movement and settled position determine the active window. Reassign or Remove an assignment. ARM assignment is required. No unrelated mode slots are overwritten. |
| 4 | Profiles & gain | Detect a two- or three-position switch; select PID + rate profiles, PID only or None. Visit the positions and Use switch. Optional gain uses a knob, or four trim-button values on one spare channel. Mapped gain is 50–150%; button gain is ±5%, bounded to 25–200%. The trim guide gives MAX mix weights 30/40/50/60%, with 100% at rest. Configure those mixes in EdgeTX; this page does not rewrite the transmitter model. |
| 5 | Rates | Select each rate profile and Keep current, Trainer (180/270°/s), Sport (250/400°/s), or 3D (400/600°/s). Only switch-selected profiles, or the active profile, are offered. Suggest fills a three-position switch in its position order. Collective pitch is preserved. Profiles are selected, read and written sequentially, then the original rate profile is restored. |
| 6 | Swashplate | Select Direct, 120, 135, 140, 90L or 90V; clockwise/counterclockwise main rotor; variable-pitch, motorised or bidirectional tail. Tail changes reset the yaw input rate to ±250 or ±1000. Switching between servo and motor tail sets TTA to 0 or 100 on every PID profile; motor-to-bidirectional changes preserve custom TTA. If supported and required, the tail pin is moved between SERVO 4 and MOTOR 2; a refusal blocks advance. A missing command is reported as unsupported. |
| 7 | Servo type | Servos must be unplugged. Choose cyclic and tail groups separately: 50 Hz/1520 µs, 333 Hz/1520 µs or 560 Hz/760 µs. Changing pulse band resets centre, travel and scale to the matching defaults. Frame-rate changes require restart. Only the PWM servos belonging to the selected swash/tail are used; bus channels are excluded.  Custom 25–5000 Hz fields are separate for cyclic/tail and preserve centre, travel and scale. Mixed groups are explicit. Manufacturer limits apply; firmware may reduce the rate for pulse limits/shared timers, so verify after restart. |
| 8 | Governor | Off, Limit, Direct, Electric or Nitro, plus Normal, Switch or Function throttle. Switch requires Electric or Nitro. The fast-RPM warning requires motor poles plus an RPM sensor or bidirectional DShot; serial ESC telemetry does not meet that requirement. |
| 9 | Motor & ESC | Choose throttle protocol, motor pole counts and bidirectional DShot. Enter motor pinion/main gear tooth counts and tail input/output gears for a servo tail, or tail motor poles for a motor tail. Castle telemetry and the ESC_SENSOR feature are kept consistent. |
| 10 | Connect the servos | One restart applies pending board, servo-rate, mixer, governor and motor settings. Keep servos unplugged during it. Afterwards, check that the required main/tail motor outputs exist, that all required servo outputs exist, and confirm servos connected/powered with blades still removed. |
| 11 | ESC & spin test | PWM only: with battery off, send full throttle; once the actual output reaches 99.5%, connect the battery and select low throttle, following the ESC's tones. Confirm calibration at low output. Then confirm blades removed and hold the main-motor test at 5–50%, initially 10%. Release to stop. Confirm the actual rotor direction. |
| 12 | ESC telemetry | Optional protocol and free/current ESC UART, wiring detection when supported, and Save & reboot. Check live volts, amperes, temperature and RPM. Off needs no serial ESC telemetry; Castle uses its throttle wire. |
| 13 | Servo direction & centre | Relevant servos are held at centre. Test each swash servo at +20°; it must lift its link. Reverse flips the servo's reverse flag. Set each centre pulse to the arm's specified neutral angle; an offset over 100 µs prompts a mechanics check. Confirm each swash direction and each arm centre. |
| 14 | Control directions | Roll, pitch and collective use mixer passthrough. Check live RC commands and physical swash response. Wrong reverses the corresponding mixer input rate. Use the named stick direction and the always-visible expected movement; roll is viewed from behind, pitch from the side with the nose right. Confirm each axis. |
| 15 | Level the swash | Hold roll, pitch and collective at zero. Adjust roll, pitch and collective trims in 0.1% units, ±100%. Reset clears them. Use a leveller or measure links and confirm level. |
| 16 | Blade pitch | Hold 9° collective or cyclic. Enter the measured angle in 0.1° units and Apply; the mixer rate is corrected by 9/measured, preserving sign and limiting magnitude to 20–200%. Set cyclic, collective and total pitch limits in degrees. Full-stick collective is applied to all supported Rotorflight/Actual rate profiles, restoring the original selection. Confirm no binding at full travel. |
| 17 | Tail rotor | Servo tail: hold neutral, set centre trim, check yaw passthrough and reverse if needed; command ±22° to calibrate rate, then ±60° to set CW/CCW limits. Raw yaw limits use 1000 units per 24°. Motor tail: blades-off hold controls for forward, and reverse for bidirectional tails. Idle test is limited to 15 seconds; idle is limited to 25.5% by the MSP U8 field. |
| 18 | Gyro check | With all overrides released, tilt roll/pitch and, for a servo tail, turn yaw. Confirm correction against motion. If it moves with the model, return to Board orientation. A motor tail omits the servo yaw check inside this step. |
| 19 | Finish | Review readable swash, rotor direction, tail, collective/cyclic limits, ESC protocol, telemetry, governor/throttle type, fast RPM and ARM assignment. Confirm the final checks, then Finish. Check failsafe, governor behaviour and every control before flight. |

## Completion history and prerequisites

The Suite stores a small history for each connected FC's MCU identity. A step is
recorded only after its required answers and successful settings save; incomplete,
discarded or failed steps are not marked. A former completion is shown as
**Completed before. Check again.** It never supplies a physical answer or skips a
preparation, direction, blades-off, arming-lock or restart check.

If related earlier steps have no recorded completion, a short footer hint gives the
count and **?** lists them. These are advisory dependencies: for example receiver
mapping before modes, swash/servo type/connection before servo centring, and
control directions/levelling before pitch measurement. A correctly configured FC
may have been set up elsewhere. History does not prove the current FC settings or
mechanics, and does not block such a model merely because no visit is recorded.

**Setup history** shows the recorded count. Select **Clear this FC history**, then
**Reset history**, to clear all 19 markers for that FC. It changes no FC settings,
transmitter settings, other FC's history or old Setup Assistant data. Readable FC
identity and a connected, disarmed model are required. This page reads only the
arming status needed to keep the visit locked; resetting never writes FC EEPROM.

An unwritable card or failed record readback reports that history was not saved.
Retry is explicit. For a completed setup step, **Continue without history** finishes
the action without claiming a stored completion. Back cancels that notice without
advancing. Unreadable history must be explicitly reset before it can record more
steps. Records are separate, versioned files under `rfsuite.user/wizard-history/`.

## Loading and live feedback

Startup reads adjustment ranges and servo settings one indexed record per request.
The progress text updates in place while loading. The larger USB bulk replies do
not fit the firmware telemetry response buffer and are never requested here.

When live System Status (`STAT`) or System Config (`SCFG`) telemetry is available,
the footer can show FC saving, unsaved changes, restart needed, active override,
missing receiver link, accelerometer calibration or active PID/rate/battery profiles.
Specific operation messages, errors and permanent-override warnings take priority.
Missing or stale packed words add no hint and do not prevent normal MSP operation.
Their values never acknowledge a save, clear a local restart requirement or replace
the fresh MSP arming-lock check. EdgeTX can retain per-sensor current status for up
to 20 seconds; treat these as supplementary observations.

## Overrides, connection loss and saving

MSP_ARMING_DISABLE blocks arming while the page is open and is asserted again after
a restart. The MSP arming-disable flag is independently read back before controls
are enabled and checked throughout the visit. Servo, mixer and motor overrides are explicitly released on each task/step
exit and on page teardown. Leaving drops unsent override keepalives. Configuration
writes are acknowledged before EEPROM and before moving to the next step.

Timeout support is **probed independently** for servo and mixer commands, never
inferred from API 12.10. An OFF request with a valid five-byte timeout payload must
succeed and an invalid four-byte OFF payload must be explicitly refused. A timeout
does not prove support. Firmware that ignores trailing bytes therefore stays on
legacy three-byte holds. Supported holds use a 3000 ms timeout; releases always
use the legacy payload. Motor overrides retain the fixed one-second expiry.

Leaving a task waits for OFF acknowledgements before another hold can start.
Normal exit restores arming availability only after confirmed cleanup and
Save/Discard. Failed cleanup keeps arming disabled and offers explicit retry.
On link loss, Back explains that the FC must be powered off before leaving:
permanent overrides cannot be released over a missing link. Reconnect allows
cleanup to resume for the same FC.

An externally interrupted visit retains the FC's arming lock. On reopening in the
same Suite session, a recovery gate asks for an FC power cycle before continuing;
this clears permanent overrides and unsaved RAM changes. Power-cycle the FC after
an unexpected tool/widget termination even if the radio has also restarted.
The Suite's independent ARMED banner remains visible above the wizard's frame.

Back across a dirty step asks to save or discard before loading another step, so
profile-specific changes retain their originating commit. Discard clears pending
pitch/rate drafts. ESC calibration has its own fresh blades-removed confirmation;
reloading configuration invalidates all physical answers.

Do not switch helicopters during a visit. The wizard binds itself to the FC identity.
An armed transition, lost connection, refused operation or malformed response blocks
progress; it does not report a successful save. Retry is an explicit action.
Returning to a physical-check step requires fresh answers.

The connection gate batches the initial restart. Receiver wiring and later ESC
telemetry can need their own restart, as in the Configurator sequence. Unsupported
automatic wiring/alignment commands do not prevent using the manual settings.
If automatic board alignment is refused, the status line explicitly asks for the
angles to be entered manually; that refusal does not change the current angles.

## Feedback and detailed settings

Test buttons show when a held command is active; pressing a servo/mixer test again
returns it to neutral. Motor controls are momentary and remain disabled until the
required preparation and output checks pass. The status line distinguishes staged
changes, live edits, pending restart, running detection and a found combination.
A successful wiring trial changes Continue to **Save & reboot**. Cancel restores
the previous wiring flags. No ESC data is labelled as received until voltage or
temperature confirms reception.

The profile/gain cards show the existing assignments, the current mapped profile
and knob/button feedback, followed by a paginated channel-use plan. For the trim
method, create a spare channel with a MAX source at 100% when no button is pressed.
Add replacement mix actions for cyclic down/up at 30/40%, yaw down/up at 50/60%,
and disable those trims' effect on the flight sticks. The guide lists the expected
channel values. Confirm each button in the live feedback before flying.

For detailed adjustments beyond the guided fields, save and leave the wizard,
then use the Suite's Receiver, Modes, Adjustments, Rates, Mixer, Servos, Governor,
Motor or Power pages. The wizard's **?** opens the complete current task text.
It does not jump out of an active bench test through a web-style tab shortcut.

## Implementation and verification

The reference is [Configurator PR #491](https://github.com/rotorflight/rotorflight-configurator/pull/491),
snapshot `4a57ba971d7ffef06f39bb66b3f376d150a27e25`. Timeout/tail-output semantics follow
[firmware PR #541](https://github.com/rotorflight/rotorflight-firmware/pull/541).
The sequence is fixed; conditional variants stay inside their steps.

API loads, reply decoding, indexed writes, profile transactions and scene assembly
are resumed across calls. MSP replies update cached values; they do not rebuild LVGL.
Reactive properties read cached page state. `bin/wizard/verify.lua` exercises the
protocol, failure paths, lifecycle, geometry and per-call instruction costs without
starting an EdgeTX or flight-controller simulator.
The previously published native tree remains valid while a replacement scene is
staged. Its getters tolerate navigation, reload, discarded rate drafts and teardown;
controls from a replaced card cannot edit the new step. Regression checks retain
every old card across these transitions at all four supported preview sizes.
Consumed MSP batches are released when a new idle batch starts, keeping completed
polling jobs from accumulating throughout a visit.
Completion history uses a separate versioned Lua data file per FC under
`rfsuite.user/wizard-history/`. Each record is read directly within 64 bytes;
compiled overlays are ignored. Unreleased text records are ignored; there is no
text-format migration or compatibility path.

[Source-to-port coverage and deliberate adaptations](../reference/helicopter-wizard-source-coverage.md)
record the function inventory, behavior contracts and independent golden vectors.

The preview images are approximate renders of the actual scene definitions, using
desktop fonts. They are not native EdgeTX screenshots or radio acceptance evidence.

[Compact live orientation](../images/helicopter_setup/01-small-task-3.png) ·
[Compact roll movement](../images/helicopter_setup/motion-attitude-roll-small.gif) ·
[Compact pitch movement](../images/helicopter_setup/motion-attitude-pitch-small.gif) ·
[320×240 roll movement](../images/helicopter_setup/motion-attitude-roll-narrow.gif) ·
[800×480 orientation](../images/helicopter_setup/01-large-task-3.png)

[FC input directions](../images/helicopter_setup/02-small-task-3.png) ·
[Throttle-switch endpoints](../images/helicopter_setup/02-small-task-4.png) ·
[Cyclic servo Hz](../images/helicopter_setup/07-small.png) ·
[Tail servo Hz](../images/helicopter_setup/07-small-task-2.png)

[320×240 illustrated tasks](../images/helicopter_setup/illustrations-narrow.png) ·
[480×272 illustrated tasks](../images/helicopter_setup/illustrations-small.png) ·
[800×480 illustrated tasks](../images/helicopter_setup/illustrations-large.png)

[320×240 all steps](../images/helicopter_setup/overview-narrow.png) ·
[Small-display preview sheet](../images/helicopter_setup/overview-small.png) ·
[Large-display preview sheet](../images/helicopter_setup/overview-large.png)

*Documented against RFSuite 0.2.1. Physical-radio acceptance remains required.*
