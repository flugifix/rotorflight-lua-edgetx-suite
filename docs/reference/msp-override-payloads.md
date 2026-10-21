---
title: MSP override payloads
---

# MSP override payloads

`mixer_override` reads all 29 U16 input overrides with command 190. Command 191
writes **one** zero-based U8 `index` followed by one U16 `value`, rather than a
whole table. Signed commands retain their two's-complement wire representation.
The caller must supply an index from 0 through 28. OFF is 2501; passthrough is 2502.

`servo_override` retains command 192/read and 193/write. Writes contain U8
`servo_id` and U16 `action`; OFF is 2001. The new `servo_override_all` codec writes
command 196 with a single U16 `value`.

All three builders append an optional U16 timeout, in milliseconds, **only when
the caller supplies `timeout`**. It is clamped to 500–30000 ms; a `timeout` that is not a number makes the
builder return `nil` instead of the untimed, persistent form. Without that field
the legacy payload length is unchanged: three bytes per input/servo, two bytes
for the all-servo command. A serializer does not prove that firmware honors expiry.

API 12.10 firmware without timed-override support can accept a five-byte
per-output payload and leave the override permanent. Do not enable timeouts from
the API version or a successful five-byte write alone. Establish support for each
command independently. A caller can send OFF only and require both an ACK for the
valid five-byte form and an explicit protocol refusal for the invalid four-byte
form. A transport timeout is not that refusal, and servo support does not prove
mixer support. Command 196 support likewise does not prove command 191 support.

Callers own safe values, arming inhibition, refresh and acknowledged release of
every override on exit or failure. These modules add no timer, background work,
arming lock or automatic cleanup. Timed support is an extra bound, not a substitute
for explicit cleanup. Motor override 195 is unchanged.

Run `lua5.3 bin/msp/verify_msp_override_payloads.lua` for exact payload bytes,
release values, timeout bounds and read ordering. No radio, simulator or actuator
test is claimed by these offline protocol checks.
