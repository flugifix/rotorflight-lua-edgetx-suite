# Rotorflight EdgeTX Suite Updater & Installer

A standalone utility for Windows, macOS, and Linux to easily install, update, and manage the Rotorflight Lua suite on EdgeTX transmitters and SD cards.

## Features

- **SD Card Auto-Detection**: Automatically identifies connected EdgeTX radios and drives.
- **GitHub Release Integration**: Downloads and installs official releases and pre-releases from GitHub.
- **Multi-Language Support**: Installs language-specific packs (`de`, `en`, `fr`, etc.).
- **User Settings Preservation**: Preserves `preferences.ini` and custom user dashboards during updates.
- **Offline / Local Mode**: Supports manual installation from locally downloaded `.zip` files.

## Running from Source

```bash
cd src
pip install -r requirements.txt
python updater.py
```

## Building Standalone Executables

### Windows (.exe)
Run `make.cmd` from `src/` or run the VS Code task **"Updater: Build Tool"**.
The compiled binary will be placed at `bin/updater/updater.exe`.

### Linux / macOS
```bash
cd src
pip install -r requirements.txt
pyinstaller --onefile --noconsole --name updater updater.py
```
