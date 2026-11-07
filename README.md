# Odax Farma – Gestión de Órdenes de Compra

Aplicativo cliente de escritorio para la base de datos `odaxfarma_compras`
(proyecto del curso Gestión de Datos e Información – UCSM).

- **Lenguaje:** Python 3.11 + Tkinter (sin frameworks)
- **Base de datos:** MySQL 8.0, conector oficial `mysql-connector-python`
- **Arquitectura:** interfaz (`vistas/`) → acceso a datos (`datos/`) → procedimientos almacenados y triggers en MySQL

## Cómo ejecutarlo
1. Crear la base de datos con los scripts de la carpeta `sql/` en orden (01, 02, 05).
2. Crear el usuario del aplicativo (ver `sql/00_usuario_app.sql`).
3. Copiar `config.example.ini` como `config.ini` y poner la contraseña.
4. Instalar dependencias y ejecutar:
   ```
   python -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt
   python main.py
   ```
