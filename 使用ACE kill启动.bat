@echo off
set SCRIPT_PATH=%~dp0���ű�.ps1
powershell -Command "Start-Process powershell -ArgumentList \"-File\", \"\"\"%SCRIPT_PATH%\"\"\" -Verb RunAs"