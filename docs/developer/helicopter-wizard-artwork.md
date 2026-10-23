# Helicopter wizard artwork

The illustrations for the helicopter setup wizard's cards, prepared ahead of the cards that
will show them: nothing in the wizard draws them yet, and its existing drawings and live
feedback (the orientation model, the bench tests) are unchanged.

- Radio images: `src/rfsuite/app/pages/helicopter_setup/gfx/` -- `light/` and `dark/` hold 56
  illustrations each, and the three `heli-*.png` are the board-orientation views. Every image is
  a transparent 220 by 160 PNG. A card picks the variant that matches the current settings.
- Sources: `artwork/helicopter_setup/` -- the SVGs, the helicopter master and its layers, and
  the Configurator PR 491 snapshot they are drawn from. Its `README.md` describes the export
  (`node bin/wizard/export_artwork.mjs`, `--check` to verify) and the helicopter layer check
  (`python bin/wizard/build_helicopter_artwork.py`). Neither is needed to build the package.

The rate-curve and pulse-train images are fixed examples (the Trainer, Sport and 3D presets;
50/1520, 333/1520 and 560/760 microseconds). They are pictures for explanation, not a display
of the flight controller's live settings.
