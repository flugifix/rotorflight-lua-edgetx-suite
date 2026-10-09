---
title: Saving configuration
sidebar_label: Saving configuration
---

# Saving configuration

The **Save** action on a configuration page writes the values that page has read and edited.
A page can display initial values before the flight controller has answered; those values are
not a configuration that is ready to save.

On the pages listed below, Save requires a successful read of every record in the page load.
If loading is still running, failed, or returned data the parser rejected, Save reports **Not
saved** and explains that the complete configuration must be read first. It queues neither the
page writes nor the host EEPROM commit. Wait for loading to finish, or use **Reload** to try
again. A reload invalidates the previous completion until its own reads succeed.

The check also runs after a save confirmation, immediately before the deferred save executes.
A page change cancels that pending save and reports **Not saved**, asking you to return to the
page and save again. Arming continues to prevent FC writes. Both checks of the arming state use
the configured warning style: the notice, or the transient banner when the armed warning is
disabled. Local radio settings do not need an FC read and keep their existing save behaviour.

## Confirming a save

*Confirm on Save*, under *System* > *Settings* > *General*, puts a question in front of every Save.
It is on by default and can be switched off. Two things override it, and both ask whatever the
preference says.

The first is an arming state that cannot be read: the question is asked anyway, because the
alternative is writing to a flight controller that may be armed without anybody having been told
the check did not run.

The second is a page whose Save destroys something that cannot be read back afterwards. Such a page
supplies the words of the question itself, so that it names what is about to be lost instead of
only asking whether to save, and it requires the question rather than leaving it to the preference.
**Tools > Copy Profiles** is the one page that does this today: it asks which profile is about to be
overwritten and which one it is copied from, because the destination profile's tune is replaced and
nothing anywhere holds what was there before. Answering *No* writes nothing.

The re-checks described above are unaffected either way: the page, its read state and the arming
state are all checked again after the answer and immediately before anything is written.

## Leaving a page with unsaved changes

A value changed on a page lives only on that page until it is saved; leaving the page discards it.
On the pages listed below, Back on a page with a change that is not saved does not leave at once.
It asks first, in a box titled **Unsaved changes**, with three answers:

- **Stay** closes the box and keeps the page with its changes. Back while the box is up does the
  same, so pressing Back twice never discards anything. Stay is the button that has the focus when
  the box opens.
- **Save** saves the page exactly as the header's Save does -- the same checks, the same notice --
  and the page stays open; Back then leaves it without asking. The box counts as the confirmation,
  so *Confirm on Save* does not ask a second time. A save that has to be confirmed anyway -- an
  arming state that cannot be read, Copy Profiles -- still asks.
- **Discard** leaves the page. Nothing is written; the next visit reads the flight controller
  again.

The question is put only where the header offers Save, never while the model is armed, and not
while a save of the page is still on its way: then Back leaves the page as before. It is not put
when the page goes without a Back on it -- the link to the flight controller is lost, or the tool
opened from the dashboard closes because full screen was left or the model armed; the changes are
discarded then as before. Trims, Swash Geometry and both Servos pages are not on the list: with
their override on they send a change to the flight controller while it is being edited, before
Save, and what leaving them should do with such a change is a question of its own.

The page decides what counts as a change through `hasUnsavedChanges()`, an optional hook the
tool asks before it leaves; on the pages below it is the same state that draws their *Unsaved
changes* line. A page without the hook is left as before.

Pages that ask:

- Flight Tuning: PIDs, Rates and Governor.
- Flight Tuning > Advanced: Autolevel, Filters, Main Rotor, PID Bandwidth, PID Controller,
  Rescue, Tail Rotor, and all three Rates Advanced pages.
- Setup: Configuration, Radio Config, Accelerometer, Alignment, GPS, Ports, Model and Telemetry.
- Setup > Mixer: Swash and Tail.
- Setup > Power: Battery, Sources, SmartFuel, Alerts and Preferences.
- Setup > Governor: General, Time, Filters and Curves.
- Setup > ESC/Motors: RPM, Telemetry, Throttle, and the ten ESC Configurator pages.
- Setup > Controls: Modes, Adjustments, In-Flight Tuning, Failsafe, Stats, both Beepers pages, and
  Blackbox Configuration and Logging.
- System > Settings: General and Localization; Audio: Volume and all nine Audio Events pages;
  Dashboard: Design and Quick Settings.

## A save that restarts the flight controller

A save on Configuration, Alignment, GPS, Ports, Radio Config, and ESC/Motors RPM, Telemetry and
Throttle restarts the flight controller after writing; on Swash and Tail it does so when the swash
type or the tail mode differs from what the page read. A Save that was refused or did not finish
leaves that comparison as it was, so the next Save restarts the flight controller too; the page
compares with the new values only once a save is done. While the settings are being written the
page cannot be left.
Once the flight controller has confirmed they are stored, the notice can be closed and the page
left, and the save finishes on its own. Its outcome is shown the next time that page is opened, in
the same box a save reports in when it is watched to the end.

## When a different flight controller answers

Adjustments, Beepers, Blackbox, Failsafe and Stats under Setup > Controls, the four Governor pages,
both Servos pages, and ESC/Motors Motor Override, RPM, Telemetry and Throttle keep what they have
read while they are open. If the link drops and comes back from a different flight controller --
another board, or one reporting a different MSP API version -- such a page reads again. A link that drops and comes back to the same
board does not make it read again, so values edited and not yet saved stay on the page.

## When the profile changes under an open page

PIDs, Rates and Governor, and the advanced tuning pages except Filters, each show one PID or rate
profile, and their Save writes the whole record of that profile. The flight controller has no way
to be told which profile a record is for: it stores it in whichever profile is active when the
write arrives. So a profile switch from the transmitter -- a profile switch or an adjustment --
while such a page is open matters:

- **Nothing edited:** the page reads the new profile, and the heading shows its number.
- **An edit not yet saved:** the page keeps the edit and does not read over it, and its heading
  keeps the number of the profile the values were read from. Save is refused
  with **Not saved** and a notice that the profile changed after the page was read; nothing is
  written and no EEPROM commit is queued. Switching back to the profile the page was read from
  makes Save available again. **Reload** reads the active profile instead and replaces the edit,
  after the usual question if *Confirm on Reload* is on. Leaving the page asks about the unsaved
  change as on any other page.

A page learns of a switch from the `pid_profile` and `rate_profile` telemetry sensors, or from the
packed *System Config* sensor on MSP API 12.10 when those are not selected. Without any of them it
cannot see a switch at all and keeps the profile the connection reported. The suite's MSP response
cache keeps a PID profile's reply only while one of these sensors reports the profile, so such a
model reads the PID profile from the flight controller on every visit instead of being served the
profile of an earlier one.

Power > Sources writes the battery configuration, whose cell values belong to the battery profiles
on MSP API 12.10. Its Save sends every profile's cell values back as they were read, so a battery
profile switch while the page is open leaves every profile's values where they were.

## Pages covered

- Flight Tuning: PIDs, Rates and Governor.
- Flight Tuning > Advanced: Autolevel, Filters, Main Rotor, PID Bandwidth, PID Controller,
  Rescue, Tail Rotor, and all three Rates Advanced pages.
- Setup: Configuration, Radio Config, Accelerometer and Alignment.
- Setup > Governor: General, Time, Filters and Curves.
- Setup > ESC/Motors: RPM, Throttle and Telemetry.
- Setup > Controls: Modes, Failsafe, Stats, both Beepers pages, and Blackbox Configuration
  and Logging.
- Setup > Power: Battery, Sources and SmartFuel.
- Setup > Mixer: Swash, Swash Geometry, Tail and Trims.
- Setup > Servos: PWM Output and BUS Output.

A chained load must finish successfully even if an earlier error allowed the page to continue
reading other records. Previously read session values alone do not grant permission to save.
The page's existing parameter help and save/reboot sequence are otherwise unchanged.

Configuration, Radio Config, Accelerometer and SmartFuel write whole records from what the page
holds, and before a read has succeeded that is the page's own starting values rather than the
board's. On Configuration that would be every feature switched off -- the serial receiver
included -- and an empty craft name, followed by a restart.

**Tools > Copy Profiles** reads no record of its own; what its Save needs is how many profiles of
the selected kind the flight controller has, which the connection reads straight away. Until that
count has arrived, Save is held and the lists offer six. Reload asks the flight controller again.

On Tail, the yaw limits and the centre trim are kept as the flight controller stores them, and
changing Tail Mode changes only the unit they are shown in -- percent for a motorised tail, degrees
for variable pitch. The firmware applies the same stored numbers in every tail mode, so a Save after
a Tail Mode change writes them back unchanged unless one of those fields was edited. Yaw Calibration
is set to the new mode's starting value on that change -- 100 % for a motorised or bidirectional
tail, 25 % for variable pitch -- as in the Rotorflight Configurator; the yaw direction is kept.

The four Mixer pages show the values of their previous visit while they read again, and each
writes whole records -- the mixer configuration, and on Swash, Swash Geometry and Tail the mixer
inputs -- with the page's own fields laid over them. A save from a visit whose read did not
succeed would send an earlier visit's records, including settings another Mixer page has changed
since. The live write that Trims sends while the swash override is on, and Swash Geometry while
setup mode is on, waits for the same read: until it has succeeded, a changed value is shown and
not sent. Switching the override or setup mode on with the * button waits for it too -- the button
is disabled until the read has succeeded -- while switching either off is available at any time.

The two Servos pages write one servo's whole record -- the one selected -- from what the page
holds, and keep the records of their previous visit while they read again. Save waits for this
visit's read and, after another servo has been picked, for that servo's own read; a servo whose
record this visit has not read shows no fields. Switching the servo override on with the * button
waits for the same read, while switching it off is available at any time. On flight controllers before API 12.09,
which read every servo in one reply, a reply shorter than the servo count it announces is refused
instead of being read as zeros. When PWM Output puts a servo back -- on Reload, or when the page
is left with a change that was not saved -- it sends the value of this visit's read, or of the last
save that completed, not the value of the first visit. Reload on PWM Output then reads the flight
controller again, as it does on BUS Output.

Modes and Adjustments under Setup > Controls write only the ranges that were changed since the page
last read or saved, then one EEPROM write; a Save with nothing changed writes nothing at all. A
range the page did not touch stays on the flight controller as it was stored -- on Modes that
includes an AUX channel above AUX 13 stored by another tool, which a save used to move to AUX 13.
Reload discards every change -- on Adjustments that includes a slot other than the one shown, which
is read again when it is next selected. While Modes writes its ranges, the page is covered by the
save's progress, as Adjustments is, so a range cannot be changed half-way through a save, and Save or Reload pressed in
the header meanwhile does nothing.

## ESC Configurator pages

*Setup* > *ESC & Motors* > *ESC Tools* opens one page per ESC firmware. These pages do not use
the shared Save action above; each writes the ESC's whole parameter block over MSP, not the
settings that were changed. Two rules follow from that.

A page reads the block only if it is that ESC's. The flight controller names the ESC family it
detected in the first byte of the block, and the *AM32*, *BLHeli_S*, *Bluejay*, *Flyrotor*,
*Hobbywing V5*, *OMP*, *Scorpion*, *XDFly*, *YGE* and *ZTW* pages -- all ten -- refuse a reply
from another family rather than decoding it with their own field list. BLHeli_S and Bluejay
report the same family, so those two decide on the ESC's main revision instead. A refused
read leaves the page on its own initial values; use *Reload* after selecting the page for
the ESC that is actually fitted.

On every ESC Configurator page, Save is refused until the read of the current visit has
succeeded, and reports the reason. A block that was never read cannot be written back: every
setting the page does not itself show would go to the ESC as zero. The page is kept between
visits, so a block read on an earlier one does not authorise a save on a later one: a read that
fails -- a different ESC, another *ESC Target*, an ESC that did not answer -- cannot be saved
from what the previous one sent. The settings on screen, the ESC's name and its firmware go back
to the page's own initial ones when the page is left as well, so a visit whose read fails does not
show the previous ESC's either.

The ESC Tools grid lights AM32, BLHeli_S and Bluejay together, because what lights them is the
ESC telemetry protocol, which all three share. Which of the three pages fits is still the
pilot's choice; on the BLHeli_S and Bluejay pages these checks make a wrong choice visible
instead of writing it to the ESC.

## Scope

The shared check protects the Save action from absent page data. It does not change wire
encodings, validate every field inside an accepted parser result, or alter the transport policy
for writes already queued. ESC encoding and telemetry-catalog issues have separate fixes.

Checked against RFSuite 0.1.7. Related: [issue 273](https://github.com/rotorflight/rotorflight-lua-edgetx-suite/issues/273).
