"""
Capa de acceso a datos – ejecución de procedimientos almacenados.

Todo el aplicativo se comunica con MySQL mediante la función ejecutar_sp():
no se escriben sentencias INSERT, UPDATE ni DELETE en Python. Cada operación
llama a un procedimiento almacenado, que valida las reglas del negocio.
"""
from mysql.connector import Error

from .conexion import obtener_conexion


class ErrorBD(Exception):
    """Error de base de datos con un mensaje entendible para el usuario."""


def traducir_error(e: Error) -> str:
    """Convierte un error de MySQL en un mensaje claro."""
    if e.errno == 1644:                      # SIGNAL de un procedimiento o trigger
        return e.msg
    if e.errno == 1062:
        return "Ya existe un registro con esa clave."
    if e.errno == 1451:
        return "No se puede: el registro está siendo usado por otros documentos."
    if e.errno == 1452:
        return "El registro relacionado no existe (revise el código ingresado)."
    if e.errno == 3819:
        return f"Dato no válido: no cumple la regla {e.msg.split(chr(39))[1] if chr(39) in e.msg else e.msg}."
    if e.errno in (1045, 2003):
        return "No hay conexión con la base de datos. Revise config.ini y que MySQL esté iniciado."
    return f"Error {e.errno}: {e.msg}"


def ejecutar_sp(nombre: str, parametros: tuple = ()) -> tuple[list, list]:
    """
    Ejecuta el procedimiento almacenado `nombre` con `parametros`.

    Devuelve (columnas, filas) del último resultado que entregue el
    procedimiento; si no devuelve filas, ambas listas quedan vacías.
    Confirma la transacción (COMMIT) si todo sale bien y la deshace
    (ROLLBACK) si ocurre un error.
    """
    try:
        cn = obtener_conexion()
    except Error as e:
        raise ErrorBD(traducir_error(e)) from e
    except FileNotFoundError as e:
        raise ErrorBD(str(e)) from e

    cur = cn.cursor()
    try:
        cur.callproc(nombre, parametros)
        columnas, filas = [], []
        for resultado in cur.stored_results():
            columnas = [d[0] for d in resultado.description]
            filas = resultado.fetchall()
        cn.commit()
        return columnas, filas
    except Error as e:
        cn.rollback()
        raise ErrorBD(traducir_error(e)) from e
    finally:
        cur.close()
        cn.close()
