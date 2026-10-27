---
title: Filters
sidebar_label: Filters
sidebar_position: 10
---

# Filters

Configures the gyro filters that remove vibration noise: two lowpass filters, two static notches, dynamic notches that track noise peaks, and an RPM filter preset. These settings are global rather than part of a PID profile.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Filters*

Read-only while the model is armed.

## Settings

| Setting | What it does |
| --- | --- |
| Lowpass 1 Filter type | Selects NONE, 1ST or 2ND: no filter, first-order or second-order lowpass filtering of the gyro signal. |
| Lowpass 1 Cutoff | Static cutoff frequency of the first lowpass filter. Range: 0 to 4000 Hz. |
| Lowpass 1 dyn.: Min cutoff | Lower limit of the first lowpass cutoff as it follows main rotor RPM. Range: 0 to 4000 Hz. |
| Max cutoff | Upper limit of that dynamic lowpass cutoff. Range: 0 to 4000 Hz. |
| Lowpass 2 Filter type | Selects NONE, 1ST or 2ND for the second lowpass filter. |
| Lowpass 2 Cutoff | Cutoff frequency of the second lowpass filter. Range: 0 to 4000 Hz. |
| Notch 1: Center | Center frequency of the first static notch, where attenuation is strongest. Range: 0 to 4000 Hz. |
| Notch 1: Cutoff | Lower edge of the first notch's frequency band. Range: 0 to 4000 Hz. |
| Notch 2: Center | Center frequency of the second static notch, where attenuation is strongest. Range: 0 to 4000 Hz. |
| Notch 2: Cutoff | Lower edge of the second notch's frequency band. Range: 0 to 4000 Hz. |
| Dynamic Filters: Notch Count | Number of notches that automatically track noise peaks in the gyro signal. Range: 0 to 8. |
| Dynamic Filters: Notch Q | Notch width: higher Q makes the notch narrower and more selective. Range: 0.0 to 10.0. |
| Min | Lowest frequency tracked by dynamic notches. Range: 10 to 200 Hz. |
| Max | Highest frequency tracked by dynamic notches. Range: 100 to 500 Hz. |
| RPM filter Type | CUSTOM, LOW, MEDIUM or HIGH preset strength; stronger filtering removes more vibration but adds delay. Shown on MSP API 12.08 and later. |
| RPM filter Min. Frequency | Minimum filter frequency; set slightly below the main rotor frequency at the lowest flying RPM. Range: 1 to 100 Hz. Shown on MSP API 12.08 and later. |

## Saving

Save writes the whole filter configuration, commits it once to EEPROM, and reports success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the configuration without a reboot.

## Related

- [Rotorflight documentation: Gyro tab](https://doc.rotorflight.org/configurator/tabs/gyro/)
- [Rotorflight documentation: RPM filters](https://doc.rotorflight.org/setup/rpm-filters/)

*Documented against RFSuite 0.2.1.*
