@echo off
setlocal enabledelayedexpansion

:: v1.0.0 (2026-02-12)
@echo off
cls

set BUILD_PATH=build\windows\x64\runner\Release
set INNO_SCRIPT=installer\windows\inno-setup.iss
set OUTPUT_DIR=dist

:: check tools
call :require flutter
if %ERRORLEVEL% neq 0 exit /b 1
call :require git
if %ERRORLEVEL% neq 0 exit /b 1
call :require iscc
if %ERRORLEVEL% neq 0 (
    echo Inno Setup Compiler iscc.exe not found in PATH
    echo Please install Inno Setup or add it to PATH
    exit /b 1
)

:: check if signtool is available (optional)
call :require signtool
if %ERRORLEVEL% equ 0 (
    set SIGNTOOL_AVAILABLE=1
    echo Code signing tool found
) else (
    set SIGNTOOL_AVAILABLE=0
    echo Warning: signtool not found - installers will not be signed
)

:: switch to main flutter dir
set SCRIPT_DIR=%~dp0
set WORK_DIR=%SCRIPT_DIR%..\..
cd /d "%WORK_DIR%" && echo %cd%

:: get current version
if not exist "pubspec.yaml" (
    echo Error: pubspec.yaml not found
    exit /b 1
)

for /f "tokens=2 delims=: " %%a in ('findstr /b "version:" pubspec.yaml') do (
    set fullVersion=%%a
)
for /f "tokens=1 delims=+" %%a in ("%fullVersion%") do (
    set VERSION=%%a
)
echo Version: %VERSION%

:: modify db.dart file for Windows
copy /y lib\model\db.dart lib\model\db.dart.bkp >nul
powershell -Command "(Get-Content lib\model\db.dart) -replace 'password: password,', '' -replace 'sqflite_sqlcipher/sqflite.dart', 'sqflite_common_ffi/sqflite_ffi.dart' | Set-Content lib\model\db.dart"

:: build
call flutter -v build windows
if %ERRORLEVEL% neq 0 (
    echo Flutter build failed
    move /y lib\model\db.dart.bkp lib\model\db.dart >nul
    exit /b 1
)

:: restore original file
move /y lib\model\db.dart.bkp lib\model\db.dart >nul

pushd "%WORK_DIR%\%BUILD_PATH%"
signtool sign /v /a /tr "http://timestamp.globalsign.com/tsa/r6advanced1" /td SHA256 /fd SHA256 "*.exe" "*.dll"
if %ERRORLEVEL% neq 0 exit /b 1
popd

:: copy SQLite library
if not exist "sqlcipher\windows\sqlite3.dll" (
    echo Error: SQLite library missing at sqlcipher\windows\sqlite3.dll
    exit /b 1
)
if not exist "%BUILD_PATH%" (
    echo Error: Build directory missing at %BUILD_PATH%
    exit /b 1
)   
copy /v sqlcipher\windows\sqlite3.dll "%BUILD_PATH%" >nul
if %ERRORLEVEL% neq 0 (
    echo Failed to copy SQLite library
    exit /b 1
)
copy /v installer\windows\vcruntime140_1.dll "%BUILD_PATH%" >nul
if %ERRORLEVEL% neq 0 (
    echo Failed to copy vcruntime library
    exit /b 1
)



:: create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: check if Inno Setup script exists
if not exist "%INNO_SCRIPT%" (
    echo Error: Inno Setup script not found at %INNO_SCRIPT%
    exit /b 1
)

:: copy Inno Setup script with version replaced
::set INNO_TEMP=inno-setup-%VERSION%.iss
::copy /y "%INNO_SCRIPT%" "%INNO_TEMP%" >nul

:: replace version placeholder in Inno script





:: run Inno Setup compiler
echo Compiling Inno Setup installer...
pushd "%WORK_DIR%\installer\windows"
if not exist "Las Notes" mkdir "Las Notes"
xcopy /v "%WORK_DIR%\%BUILD_PATH%" "Las Notes" /S >nul
powershell -Command "(Get-Content 'inno-setup.iss') -replace '__THE_VERSION__', '%VERSION%' | Set-Content 'inno-setup-2.iss'"
iscc  "inno-setup-2.iss" /O"." /F"lasnotes-windows-%VERSION%-setup"
set ISCC_RESULT=%ERRORLEVEL%


:: clean up temp file
:: del /f /q "%INNO_TEMP%" 2>nul

if %ISCC_RESULT% neq 0 (
    echo Inno Setup compilation failed
    exit /b 1
)

:: verify installer was created
set INSTALLER_NAME=lasnotes-windows-%VERSION%-setup.exe
if not exist "%INSTALLER_NAME%" (
    echo Error: Installer not found: %INSTALLER_NAME%
    exit /b 1
)

signtool sign /v /a /tr "http://timestamp.globalsign.com/tsa/r6advanced1" /td SHA256 /fd SHA256 "%INSTALLER_NAME%"
if %ERRORLEVEL% neq 0 exit /b 1

move /y %INSTALLER_NAME% "%WORK_DIR%/dist" >nul
del "inno-setup-2.iss" 2>nul
rmdir /s /q "Las Notes"
popd

:: finish
call flutter clean

:: git
git status
git add .
git status

exit /b 0

git commit -m "Release %VERSION% for Windows"
git status
set /p PUSH_RESPONSE="Git push? (Y/n): "
if /i not "%PUSH_RESPONSE%"=="n" (
    git push
)
git status

echo Done...
exit /b 0

:: function: require
:require
where %1 >nul 2>&1
if %ERRORLEVEL% neq 0 exit /b 1
exit /b 0
