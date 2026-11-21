@echo off
rem Crea la base de datos odaxfarma_compras con el script completo de la carpeta BD.
rem Requiere MySQL 8.0 instalado. Pide la contrasena del usuario root de MySQL.
cd /d "%~dp0"
set "MYSQL=C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
if not exist "%MYSQL%" (
  echo No se encontro MySQL 8.0 en:
  echo   %MYSQL%
  echo Instale MySQL Server 8.0 o corrija la ruta en este archivo.
  pause
  exit /b 1
)
echo ============================================================
echo  Se creara la base de datos odaxfarma_compras.
echo  ATENCION: si ya existe, se elimina y se vuelve a crear.
echo ============================================================
echo Ingrese la contrasena del usuario root de MySQL:
"%MYSQL%" -u root -p --default-character-set=utf8mb4 < "%~dp0BD\odaxfarma_compras_COMPLETO.sql"
if errorlevel 1 (
  echo.
  echo Hubo un error al crear la base de datos. Revise el mensaje anterior.
) else (
  echo.
  echo Base de datos creada correctamente. Ya puede abrir OdaxCompras.
)
pause
