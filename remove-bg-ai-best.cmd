@echo off
rem Most accurate AI (BiRefNet), renders and drawn art. Slow: ~20 s per image on CPU.
rem Drag images onto this file, or run: remove-bg-ai-best.cmd image.png [more images] [-Trim] [-Padding 8] [-OutDir folder] [-Preview]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0presets.ps1" -Preset ai-best %*
rem Keep the window open when started by double-click or drag-and-drop (set BGREMOVE_NOPAUSE=1 to skip).
if not defined BGREMOVE_NOPAUSE echo %cmdcmdline% | find /i "%~nx0" >nul && pause
