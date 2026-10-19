---
title: Standby screen
sidebar_label: Standby screen
---

# Standby screen

When enabled, the fullscreen dashboard uses one configurable standby surface while it waits for the flight controller. The Rotorflight logo, current connection reason, and Suite tool entry remain available.

The screen never pages, rotates, scrolls, or hides selected items. Layouts that do not fit the current radio and locale are rejected by the settings page. The widget retains its normal connection splash when the option is off and in non-fullscreen zones.

The standby surface does not replace flight state. An active-flight link loss, postflight view, or offline summary continues to use the existing dashboard behavior.

Configure it under *System* → *Settings* → *Dashboard* → *Standby screen*.

TX GPS reports the transmitter's built-in receiver. EdgeTX provides no reception timestamp, so an unavailable value makes no hardware or freshness claim. The optional read-only ELRS tile shows the active module's exact Packet Rate, Telemetry Ratio, Max Power ceiling, and Dynamic labels together with the completed snapshot age. Re-entering standby starts a bounded refresh; EdgeTX routes CRSF to the internal module when both module bays use CRSF.

Offline regressions verify the screen geometry and state routing. The final packaged screen and physical ELRS and internal-GPS timing remain to be checked.
