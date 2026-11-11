@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo PROJECT129 - Z88DK + SJASMPLUS TR-DOS BUILD
echo ============================================================
echo [BUILD] Script: tools\build_project129.ps1
echo [BUILD] Output: disk_A.trd
echo.

where zcc >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Z88DK zcc was not found in PATH.
    echo [ERROR] Install Z88DK and add its bin directory to PATH.
    goto :failed
)

if not exist "tools\sjasmplus.exe" (
    where sjasmplus >nul 2>nul
    if errorlevel 1 (
        echo [ERROR] SjASMPlus was not found.
        echo [ERROR] Put sjasmplus.exe in tools\ or add it to PATH.
        goto :failed
    )
)

if not exist "tools\build_project129.ps1" (
    echo [ERROR] tools\build_project129.ps1 was not found.
    goto :failed
)

if not exist "build" mkdir "build"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "tools\build_project129.ps1" -SjAsmPlus ".\tools\sjasmplus.exe"
if errorlevel 1 goto :failed

if not exist "disk_A.trd" (
    echo [ERROR] Build script returned success but disk_A.trd is missing.
    goto :failed
)

copy /y "disk_A.trd" "build\disk_A.trd" >nul
if errorlevel 1 goto :failed

echo.
echo [BUILD] SUCCESS
echo [BUILD] IMAGE=disk_A.trd
echo [BUILD] STAGE2=P129BOOT.C LOAD=#6000
echo [BUILD] Open disk_A.trd in Unreal Speccy.
echo [BUILD] At TR-DOS prompt run: RUN "BOOT"
echo.
pause
exit /b 0

:failed
echo.
echo [BUILD] FAILED. Do NOT run an older disk_A.trd.
echo [BUILD] Check the Z88DK and SjASMPlus output above.
echo.
pause
exit /b 1
