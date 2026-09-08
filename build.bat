@echo off
REM Cross-compiles Gokapi (and the gokapi-cli companion tool) for Windows and
REM Linux, and copies an example configuration file next to the binaries.
REM
REM Usage: build.bat
REM
REM Requires only a Go toolchain - no CGO / C compiler needed, since Gokapi
REM is CGO-free (modernc.org/sqlite is a pure-Go SQLite implementation).

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

set "OUT_DIR=dist"
set "GOPACKAGE=github.com/forceu/gokapi"

for /f "delims=" %%I in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') do set "BUILD_TIME=%%I"

set LDFLAGS=-s -w -X '%GOPACKAGE%/internal/environment.Builder=Build Script' -X '%GOPACKAGE%/internal/environment.BuildTime=%BUILD_TIME%'

echo Running go generate (version numbers, WASM modules, minified assets)...
call go generate ./...
if errorlevel 1 goto :error

echo Cleaning %OUT_DIR%\...
if exist "%OUT_DIR%" rd /s /q "%OUT_DIR%"
mkdir "%OUT_DIR%"

REM Targets to build. Add more lines to build for more platforms,
REM e.g. "call :build windows arm64 cmd/gokapi gokapi"
call :build linux   amd64 cmd/gokapi gokapi
if errorlevel 1 goto :error
call :build linux   arm64 cmd/gokapi gokapi
if errorlevel 1 goto :error
call :build windows amd64 cmd/gokapi gokapi
if errorlevel 1 goto :error

call :build linux   amd64 cmd/cli-uploader gokapi-cli
if errorlevel 1 goto :error
call :build linux   arm64 cmd/cli-uploader gokapi-cli
if errorlevel 1 goto :error
call :build windows amd64 cmd/cli-uploader gokapi-cli
if errorlevel 1 goto :error

echo Copying example configuration...
copy /y gokapi.env.example "%OUT_DIR%\gokapi.env.example" >nul

echo.
echo Done. Binaries and example config are in .\%OUT_DIR%\:
dir "%OUT_DIR%"

goto :eof

:build
set "GOOS=%~1"
set "GOARCH=%~2"
set "PKG=%GOPACKAGE%/%~3"
set "NAME=%~4"
set "EXT="
if "%GOOS%"=="windows" set "EXT=.exe"
set "OUT=%OUT_DIR%\%NAME%-%GOOS%-%GOARCH%%EXT%"
echo Building %OUT%...
set "CGO_ENABLED=0"
go build -ldflags "%LDFLAGS%" -o "%OUT%" "%PKG%"
set "GOOS="
set "GOARCH="
exit /b %ERRORLEVEL%

:error
echo.
echo Build failed.
exit /b 1
