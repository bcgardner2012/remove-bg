@echo off
rem One-time setup for the AI presets: builds the AI program and downloads the default models (~340 MB).
rem Needs the .NET SDK 8 or newer (https://dotnet.microsoft.com/download). The colour presets work without it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
rem Keep the window open when started by double-click or drag-and-drop (set BGREMOVE_NOPAUSE=1 to skip).
if not defined BGREMOVE_NOPAUSE echo %cmdcmdline% | find /i "%~nx0" >nul && pause
