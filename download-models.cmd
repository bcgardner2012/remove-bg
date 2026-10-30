@echo off
rem Downloads AI models into models\. Run without arguments to list them, e.g.:
rem   download-models.cmd BiRefNet-general-epoch_244
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0download-models.ps1" %*
rem Keep the window open when started by double-click or drag-and-drop (set BGREMOVE_NOPAUSE=1 to skip).
if not defined BGREMOVE_NOPAUSE echo %cmdcmdline% | find /i "%~nx0" >nul && pause
