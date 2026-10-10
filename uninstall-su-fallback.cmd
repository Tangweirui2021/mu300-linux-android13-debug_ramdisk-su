@echo off
rem Local variant of uninstall.cmd: runs uninstall-su-fallback.ps1, which falls back to /debug_ramdisk/su
rem when `su` is not in the adb shell's PATH (Android 13 + Magisk). See docs/f50-notes.md.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-su-fallback.ps1" %*
exit /b %ERRORLEVEL%
