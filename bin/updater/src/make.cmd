@echo off
setlocal
cd /d %~dp0

echo [1/5] Checking for pyinstaller...
pyinstaller --version >nul 2>&1
if errorlevel 1 (
    echo PyInstaller not found. Installing requirements...
    pip install -r requirements.txt || goto :error
)

echo [2/5] Compiling updater.py to standalone EXE...
python -m PyInstaller --onefile updater.py --name updater --windowed --icon=updater.ico || goto :error

echo [3/5] Moving updater.exe into parent folder...
if exist ..\updater.exe (
    del ..\updater.exe
)
move /Y dist\updater.exe ..\updater.exe >nul

echo [4/5] Cleaning up build tree...
rd /s /q build
rd /s /q dist
del /q updater.spec

echo [5/5] Build complete. updater.exe is ready at: ..\updater.exe
goto :eof

:error
echo Build failed.
exit /b 1
