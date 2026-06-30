@echo off
echo Starting Caltex AutoPro Server...
echo.

:: Try python first
python caltexautopro.py 2>nul
if %ERRORLEVEL% EQU 0 goto :done

:: Try py launcher
py caltexautopro.py 2>nul
if %ERRORLEVEL% EQU 0 goto :done

:: Try full path
"C:\Users\Sel\AppData\Local\Programs\Python\Python314\python.exe" caltexautopro.py 2>nul
if %ERRORLEVEL% EQU 0 goto :done

echo ERROR: Python not found. Please disable App Execution Aliases:
echo   Settings ^> Apps ^> App execution aliases ^> Turn OFF Python and Python3
echo.
pause

:done
