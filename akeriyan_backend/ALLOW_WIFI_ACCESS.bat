
@echo off
REM ============================================================
REM  Elder Wand - allow your phone to reach the backend over WiFi
REM  Right-click this file -> "Run as administrator", click Yes.
REM  One-time setup. Opens inbound TCP port 8000 + marks the
REM  current network as Private (home network).
REM ============================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Please RIGHT-CLICK this file and choose "Run as administrator".
    echo.
    pause
    exit /b
)

echo Removing any old rule...
netsh advfirewall firewall delete rule name="Elder Wand Backend 8000" >nul 2>&1

echo Adding firewall rule for port 8000...
netsh advfirewall firewall add rule name="Elder Wand Backend 8000" dir=in action=allow protocol=TCP localport=8000 profile=any

echo Marking current network as Private...
powershell -NoProfile -Command "Get-NetConnectionProfile | ForEach-Object { Set-NetConnectionProfile -InterfaceAlias $_.InterfaceAlias -NetworkCategory Private -ErrorAction SilentlyContinue }"

echo.
echo ============================================================
echo  DONE. Your phone can now reach the backend over WiFi at:
echo     http://192.168.1.35:8000
echo  Set that as the Backend URL in the app and tap CONNECT.
echo ============================================================
echo.
pause
