@echo off
rem Runs every preset on each image and opens a side-by-side comparison. Keep the result you like best.
rem Drag images onto this file, or run: remove-bg-compare.cmd image.png [more images] [-Trim] [-OutDir folder]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compare-presets.ps1" -Open %*
rem Keep the window open when started by double-click or drag-and-drop (set BGREMOVE_NOPAUSE=1 to skip).
if not defined BGREMOVE_NOPAUSE echo %cmdcmdline% | find /i "%~nx0" >nul && pause
