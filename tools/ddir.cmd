@echo off
rem ddir - Desktop Director CLI wrapper (PowerShell backend)
rem Add this folder to PATH, then call: ddir <command>
powershell.exe -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0ddir.ps1" %*
