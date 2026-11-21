@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

where py >nul 2>nul
if %errorlevel%==0 (
  py -3 "%SCRIPT_DIR%server\local_server.py" %*
  goto :done
)

where python >nul 2>nul
if %errorlevel%==0 (
  python "%SCRIPT_DIR%server\local_server.py" %*
  goto :done
)

echo [HATA] Python 3 bulunamadi. Lutfen Python 3 yukleyin.
pause
exit /b 1

:done
if errorlevel 1 pause
