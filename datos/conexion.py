"""
Capa de acceso a datos – conexión con MySQL.

Este módulo es el único punto del aplicativo que abre conexiones con la base
de datos odaxfarma_compras. Lee los parámetros desde config.ini para no
escribir credenciales dentro del código.
"""
import configparser
import sys
from pathlib import Path

import mysql.connector
from mysql.connector import Error


def carpeta_base() -> Path:
    """Devuelve la carpeta del aplicativo (también funciona en el .exe)."""
    if getattr(sys, "frozen", False):          # ejecutable generado con PyInstaller
        return Path(sys.executable).parent
    return Path(__file__).resolve().parent.parent


def leer_configuracion() -> dict:
    """Lee la sección [mysql] de config.ini y devuelve los parámetros."""
    ruta = carpeta_base() / "config.ini"
    if not ruta.exists():
        raise FileNotFoundError(
            f"No se encontró {ruta}. Copie config.example.ini como config.ini "
            "y complete la contraseña.")
    cfg = configparser.ConfigParser()
    cfg.read(ruta, encoding="utf-8")
    s = cfg["mysql"]
    return {
        "host": s.get("host", "localhost"),
        "port": s.getint("port", 3306),
        "user": s["user"],
        "password": s["password"],
        "database": s["database"],
    }


def obtener_conexion():
    """Abre y devuelve una conexión nueva. Quien la usa debe cerrarla."""
    return mysql.connector.connect(
        **leer_configuracion(),
        charset="utf8mb4",
        collation="utf8mb4_0900_ai_ci",
        autocommit=False,
    )


def probar_conexion() -> tuple[bool, str]:
    """Intenta conectarse y devuelve (éxito, mensaje para mostrar)."""
    try:
        cn = obtener_conexion()
        cur = cn.cursor()
        cur.execute("SELECT VERSION(), DATABASE(), CURRENT_USER()")
        version, bd, usuario = cur.fetchone()
        cur.close()
        cn.close()
        return True, f"Conectado a {bd} como {usuario} (MySQL {version})"
    except FileNotFoundError as e:
        return False, str(e)
    except Error as e:
        return False, f"Error {e.errno}: {e.msg}"
