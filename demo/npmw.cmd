@echo off
setlocal
set "BASE=%~dp0"
set "NODE_DIR=%BASE%.tooling\node"
if not exist "%NODE_DIR%\node.exe" (
  call mvn -q -f "%BASE%pom.xml" frontend:install-node-and-npm || exit /b 1
)
set "PATH=%NODE_DIR%;%PATH%"
cd /d "%BASE%frontend"
"%NODE_DIR%\node.exe" "%NODE_DIR%\node_modules\npm\bin\npm-cli.js" %*
