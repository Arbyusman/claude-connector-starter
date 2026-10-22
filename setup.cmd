@echo off
rem One-command setup. Double-click or run: setup.cmd [-FigmaToken figd_xxx] [-SkipDocling] [-WithDesktop]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
pause
