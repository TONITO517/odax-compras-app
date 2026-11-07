"""Prueba rápida de conexión desde la consola."""
from datos.conexion import probar_conexion

if __name__ == "__main__":
    ok, mensaje = probar_conexion()
    print(("[OK] " if ok else "[ERROR] ") + mensaje)
