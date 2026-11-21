@echo off
rem =====================================================================
rem  Construye OdaxCompras.exe con PyInstaller y arma la carpeta
rem  EJECUTABLE de la entrega en ..\ENTREGA_FINAL\EJECUTABLE
rem  Uso: doble clic o ejecutar desde CMD en la carpeta del proyecto.
rem =====================================================================
cd /d "%~dp0"

echo [1/5] Activando el entorno virtual...
if not exist ".venv\Scripts\activate.bat" (
  echo No se encontro la carpeta .venv. Cree el entorno virtual primero.
  pause
  exit /b 1
)
call ".venv\Scripts\activate.bat"

echo [2/5] Instalando PyInstaller...
python -m pip install --quiet pyinstaller==6.10.0
if errorlevel 1 (
  echo Error al instalar PyInstaller. Revise su conexion a internet.
  pause
  exit /b 1
)

echo [3/5] Generando OdaxCompras.exe (puede tardar 1 o 2 minutos)...
pyinstaller --noconfirm --clean --onefile --windowed --name OdaxCompras --collect-all mysql.connector main.py
if errorlevel 1 (
  echo Error al generar el ejecutable. Revise los mensajes anteriores.
  pause
  exit /b 1
)

echo [4/5] Armando la carpeta EJECUTABLE...
for %%I in ("%~dp0..") do set "BASE=%%~fI"
set "DEST=%BASE%\ENTREGA_FINAL\EJECUTABLE"
if exist "%DEST%" rmdir /s /q "%DEST%"
mkdir "%DEST%\BD"
copy /y "dist\OdaxCompras.exe" "%DEST%\" >nul
copy /y "config.example.ini" "%DEST%\config.ini" >nul
copy /y "sql\odaxfarma_compras_COMPLETO.sql" "%DEST%\BD\" >nul
copy /y "distribucion\Iniciar OdaxCompras.bat" "%DEST%\" >nul
copy /y "distribucion\Instalar base de datos.bat" "%DEST%\" >nul
copy /y "distribucion\LEEME - INSTRUCCIONES.txt" "%DEST%\" >nul

echo [5/5] Creando el acceso directo (ruta relativa a la carpeta)...
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%DEST%\OdaxCompras.lnk'); $s.TargetPath='%SystemRoot%\explorer.exe'; $s.Arguments='OdaxCompras.exe'; $s.WorkingDirectory=''; $s.Description='Odax Farma - Gestion de Ordenes de Compra'; $s.Save()"

echo.
echo Listo. Carpeta generada en:
echo   %DEST%
explorer "%DEST%"
pause
