- **Tune Advisor applies its suggestions with Save (`app/pages/flight_tuning/tune_advisor/page.lua`,
  `lib/change_journal.lua`, `docs/pages/flight_tuning/tune_advisor.md`, `docs/reference/change-journal.md`)**:
  - Confirm the shown axis's writable changes, check fresh settings and profiles, write only changed fields
    while preserving every other reply byte, commit to EEPROM and verify by reading back.
  - Keep applied axes from offering another step on old flight data. Record each committed value in a
    per-board, append-only change journal for reference and manual undo.
