---
nav_order: 2
parent: Audio
grand_parent: Settings
---

# Volume

The Volume page sets how loud the suite's announcements are, in one of two ways: a level for the announcements themselves, or the radio's whole master volume through a global variable. A save the card refuses shows *Save failed: the settings file could not be written to the SD card*.

## Mode

* **Mode:** one of three, and only one at a time.
  * **Off (radio default)** (the default): the radio's own Wav volume and master volume rule; the suite writes nothing.
  * **Callout level:** every announcement plays at the *Level* set below; the master volume stays with the pot.
  * **Master volume:** the suite sets the radio's whole volume through a global variable; see [Master volume](#master-volume).

The two cannot be combined because they multiply: the level scales the sound files, and the master volume scales everything the radio plays after that. Under a master volume the suite sets, a level could only make the announcements quieter than that master volume says.

**A settings file written before the page offered a mode** is read the way the suite used it then: a global variable set means *Master volume*, a level set means *Callout level*, neither means *Off*. A file that had both a level and a global variable set opens in *Master volume*, and the level is ignored from then on -- the announcements then play at the radio's own Wav volume under the master volume, rather than at that level. The level stays in the file and is offered again when *Callout level* is picked. The mode is written to the file on the page's first save.

* **Connected only:** shown in both modes, under *Mode*.
  * **On:** the mode acts only while the radio's link to the model is up, so bench and menu work stays at the radio's own volume. In *Master volume* the pot rules until the link comes up, the *Normal Level* is written then, and `-1024` is written when the link goes down (unless a critical alert is still active, see below).
  * **Off:** the mode acts from the moment the dashboard or the tool starts, and the link changes nothing. In *Master volume* the pot therefore stays overridden for as long as the mode is on.
  * Until it is set, it follows the mode: in *Callout level* the earlier *Connected only* of the level, in *Master volume* on, which is how the master volume always behaved. A file written before this setting existed reads the same way, and so does a mode picked on the page before *Connected only* is touched or saved in one of the two modes; a save in *Off* does not store it.
  * For adjustment announcements made where neither the dashboard nor the tool runs (by the [background decoder](../../../reference/background-decoder.md), or by the service widget on its own), *on* means that the radio's RF link is up.

## Callout level

* **Level:** 1 to 5 (5 the loudest). It applies to the sound file of an announcement, to the number and unit the radio speaks after it, and to the adjustment announcements the background decoder or the service widget makes. Level 3 plays a sound file at a quarter of its amplitude, which is what the radio's own *Wav volume* does at its middle setting 0; 5 plays it at full amplitude, 1 at a sixteenth. Picking *Callout level* with no level stored starts at 3.
* **Test:** *Play* (behind a play symbol) speaks a sample announcement -- the word "battery" and the number 80 with its unit -- at the *Level* shown, also before it is saved. It writes nothing and works while the model is armed.

## Master volume

The suite changes the entire radio's volume during flight. While no critical alert is active it writes the *Normal Level*; while any critical alert is active it writes the *Alert Level* instead. The critical alerts are low voltage, an empty tank, telemetry lost in flight, and the ESC or MCU temperature at its critical level -- the tank and the temperatures only while their own alert is switched on. With *Connected only* on, the *Normal Level* is written only while the link is up, the *Alert Level* whenever a critical alert is active.

* **Global Variable:** picked with the radio's own source picker, which lists only the global variables this radio has, with their names -- GV1 to GV9 on most radios, GV1 to GV15 on radios that have fifteen. It has no entry for off: *Mode* *Off* is what turns the master volume off. Until a global variable is picked, the picker shows EdgeTX's empty source `---`, the suite writes nothing, and the page says under the picker that one is to be picked. EdgeTX lists no global variable while global variables are switched off for the model (in its model setup, or for every model in the radio setup); a global variable picked before stays shown and is still written. A settings file that names a global variable this radio does not have (copied from a radio with more) leaves the master volume off, and the page says so under the picker; the setting stays in the file.
* **Normal Level (%):** the master volume while no critical alert is active.
* **Alert Level (%):** the master volume while any critical alert is active.

The setting is radio-wide: every model memory that carries the chain below uses the same global variable.

**Radio Setup (once per model):**
1. **Settings > Audio > Volume:** set *Mode* to *Master volume* and *Global Variable* to a free global variable (e.g. **GV9**). Set your desired *Normal* and *Alert* volume levels.
2. **Inputs:** Add one input, e.g. `I15 "Vol"`, **Source = GV9**, weight 100. (Give it its own slot and leave it out of the mixer).
3. **Logical Switch:** Create a logical switch `L10: a > x` with **a = GV9**, **x = -1024**. This is true while the suite is driving the volume.
4. **Special Function:** Create a special function `SF: L10 -> Volume = I15 (Vol)`. (Use the **input**, not the GVAR).

Steps 2 to 4 can also be left to the page: *Create* under the [model chain](#model-chain) check writes the links that are missing, after a preview.

When the suite stops driving the volume while the dashboard or the tool runs (the link goes down with *Connected only* on, another mode is picked, or another global variable is picked -- then the one it held), it writes `-1024` to the GVAR. This makes the logical switch false, the special function releases, and your regular volume pot regains control. Each changed value is a write into the model, which EdgeTX saves with the model.

> [!NOTE]
> Retiring the feature does not automatically release the GVAR. The last written value stays in the model file, so the pot will remain overridden until something writes `-1024` again. The same holds when the radio is switched off while the suite holds the volume and the mode is changed before the next start: only a running dashboard or tool that wrote the global variable releases it, so write `-1024` by hand (or pick the mode again, start the dashboard, then change it) before relying on the pot.

### Model chain

Under *Alert Level* the page shows whether the model carries this chain for the global variable picked, one line per link:

* **Input:** the input whose source is the global variable, or that none is.
* **Logical switch:** the logical switch `a > x` with `a` = the global variable and `x` = `-1024`, or that none is -- or the one that compares the global variable with another `x`, which it names.
* **Special function:** the *Volume* function switched by that logical switch with that input as its source, or what is wrong: one that has the right switch and another source, or the right source and another switch, each named, or that there is none.

Any slots count, and the names are those EdgeTX shows: an input by its name (or its number), a logical switch as `L01` to `L64`, a special function as `SF1` to `SF64`. A link found reads with a check mark. The check also warns about what lets a chain be found and still not do what it should: *Popup* set for the global variable, a second *Volume* function that is on (the one further down the list wins), an input with a weight other than 100, an offset, a curve, a switch, a restriction to some flight modes, a *Side* of `x>0` or `x<0` (the other half of the global variable's range then reads as 0) or more than one line (the first line that is on is the input's value, so another line can take over); a logical switch with an AND switch, a delay or a duration, and a *Volume* function that is switched off. Mixes are not searched for other uses of the global variable. The radio's own *Global Functions* can hold a *Volume* function too, and the check cannot see them: EdgeTX's Lua reads only the model's special functions.

The model is read when the page opens, when another global variable is picked, on *Reload*, and by *Create* at *Yes* and after its writes (below) -- not on every pass, and not again when the page is redrawn for anything else. The check only reads; it changes nothing in the model and works while the model is armed. A radio whose firmware does not answer the questions it needs gets a line saying so instead.

* **Create:** shown while the chain is not complete. *Preview* opens EdgeTX's own confirm dialog, which lists one line per link: the links to be written as EdgeTX's lists show them -- for example `Input 31: GV3, weight 100%`, `Logical switch L64: a>x GV3 -1024`, `Special function SF58: L64 Volume 31`, where EdgeTX draws its input symbol before the input's number -- and the links already in the model as *present*. A slot still to be written is named the way EdgeTX names it once it is in use, so the preview and the check above name it alike. Its buttons are EdgeTX's *No* and *Yes*, and *No* has the focus when it opens, so a press of the wheel cancels. Nothing is written before *Yes*.
  * **Where:** each missing link goes into the LAST free slot of its kind -- the highest input with no line, the highest logical switch with no function, the highest special function with no switch -- and never into a slot that holds anything. The input is written with the global variable as its source, weight 100, both sides and nothing else; it keeps whatever name the input has. The special function is switched on.
  * **What is kept:** a correct input or logical switch already in the model is used as it is, and only the links that are missing are written. A link that is there but faulty -- an input with any of the warnings above, a logical switch with an AND switch, a delay or a duration, a logical switch that compares the global variable with another `x`, or a *Volume* function on one link but not the other -- is never changed: *Create* is then unavailable, the line under it says so, and the check above names the fault to fix by hand. A *Popup* on the global variable or a second *Volume* function that is on is not a link; *Create* stays available, and the check keeps warning about it afterwards.
  * **What it cannot:** *Create* is unavailable when no free slot of a needed kind is left, when the model's 64 input lines are all used (EdgeTX then inserts nothing), while the model is armed and while the arming state is not known (the same locks as *Test*, with the reason under it), and on a radio without EdgeTX's confirm dialog. Mixes are not read, so an empty input that a mix still uses is not recognised as in use.
  * **After *Yes*:** the arming state, the mode, the global variable and the model are read again, and nothing is written unless the model still asks for exactly the links the preview listed; otherwise the line under *Create* says the model changed. The links are written input first and special function last, and each is read back before the next. Then the check runs again on the model as it is now, and the line under *Create* says what was created and whether the check reads the chain complete -- that check, not the writes returning, is what says the chain was made. If a write does not take, the line names what was already created and what failed; nothing is removed, and *Create* then offers the rest. EdgeTX saves the model after the writes, and the chain acts at once on whatever the global variable holds: the *Normal Level* once the mode and global variable shown are saved and the suite drives them, `-1024` (the pot rules) while *Connected only* is on and the link is down, and otherwise the value the variable happens to hold -- for example when *Create* is pressed before the settings are saved. A chain made by hand in EdgeTX behaves the same. If the model is armed or its arming state is no longer known at *Yes*, nothing is written and the line under *Create* gives the lock's reason.
  * **No undo:** the suite never removes anything from the model. To take the chain out by hand, first write `-1024` to the global variable (or save *Mode* *Off* with the tool open), so the pot is not left overridden, then delete the three links in EdgeTX.

* **Test:** *Normal* and *Alarm* (each behind a play symbol) set the global variable to the *Normal Level* or the *Alert Level* shown (also before it is saved), speak the sample announcement, and put the earlier value back after 5 seconds -- or at once when the page is left, on *Reload* and when the model is armed, and within a second when the arming state can no longer be told. If the global variable already holds that value, nothing is written; if something else writes another value to it in those 5 seconds, that value is kept, and the suite's own master volume writes its value again after a test has put the earlier one back. Every value written is a write into the model, which EdgeTX saves with it. They are available only with the whole chain found, never while the model is armed, and never while the arming state is not known -- the link is up but the flight controller reports no arming flags; the reason stands under them while they are not, and the page locks and unlocks them on its own within a second as the arming flags arrive or go away. With the link down they are available: the suite cannot tell the arming state then, and the write changes only the radio's own volume. There is no way for the suite to know when the radio has finished speaking, so the 5 seconds are an estimate.
