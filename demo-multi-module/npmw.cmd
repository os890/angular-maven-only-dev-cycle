@echo off
rem npmw.cmd - Windows variant of npmw (not tested)
setlocal
set "BASE=%~dp0"
set "MODULE=%BASE%webapp"
set "NODE_DIR=%MODULE%\.tooling\node"
if not exist "%NODE_DIR%\node.exe" (
  call mvn -q -f "%MODULE%\pom.xml" frontend:install-node-and-npm || exit /b 1
)
set "PATH=%NODE_DIR%;%PATH%"
cd /d "%MODULE%\frontend"
"%NODE_DIR%\node.exe" "%NODE_DIR%\node_modules\npm\bin\npm-cli.js" %*
