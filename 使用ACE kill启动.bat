@echo off
set SCRIPT_PATH=%~dp0主脚本.ps1
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ""%SCRIPT_PATH%""' -Verb RunAs"