@echo off
rem Lanzador del aplicativo: abre OdaxCompras.exe desde esta misma carpeta,
rem sin depender de rutas de la computadora donde se copie la carpeta.
cd /d "%~dp0"
start "" "%~dp0OdaxCompras.exe"
