@echo off
setlocal enableextensions
set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%Istar-Pack.ps1"
if not exist "%PS1%" ( echo [ERROR] ... & pause & exit /b 1 )
where pwsh.exe >nul 2>nul
if %errorlevel%==0 ( set "PS_EXE=pwsh.exe" ) else ( set "PS_EXE=powershell.exe" )
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
if %errorlevel% neq 0 ( pause )