@echo off
rem AI: any background - scenes, rooms, furniture. Renders and photos.
rem Drag images onto this file, or run: remove-bg-ai.cmd image.png [more images] [-Trim] [-Padding 8] [-OutDir folder] [-Preview]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0presets.ps1" -Preset ai %*
rem Keep the window open when started by double-click or drag-and-drop (set BGREMOVE_NOPAUSE=1 to skip).
if not defined BGREMOVE_NOPAUSE echo %cmdcmdline% | find /i "%~nx0" >nul && pause
