# Odax Farma – Gestión de Órdenes de Compra

Aplicativo cliente de escritorio que consume la base de datos `odaxfarma_compras`.
Proyecto del curso **Gestión de Datos e Información** – Universidad Católica de Santa María (UCSM).

- **Empresa:** Odax Farma S.R.L. (Arequipa) – contacto: Ing. Zoraida Condori
- **Integrantes:** Ayme Salas Alejandro Daniel, Mansilla Tito Daniel Felix, Ordoñez Paredes Paul Antonio, Vega Mamani Anthony Yerson
- **Lenguaje:** Python 3.11 + Tkinter (biblioteca estándar, **sin frameworks**)
- **Base de datos:** MySQL 8.0 con el conector oficial `mysql-connector-python` (conexión nativa, sin ORM)

## Arquitectura (tres capas)

```
vistas/  (interfaz Tkinter)  ->  datos/  (solo CALL a procedimientos)  ->  MySQL (procedimientos, triggers y vistas)
```

El aplicativo **no ejecuta INSERT, UPDATE ni DELETE**: toda operación llama a un procedimiento
almacenado. El usuario de conexión `odax_app` solo tiene permisos `SELECT` y `EXECUTE`.

## Estructura del proyecto

| Carpeta / archivo | Contenido |
|---|---|
| `main.py` | Punto de entrada |
| `vistas/` | Interfaz: ventana principal, ventana genérica de maestros, ventana genérica de documentos (cabecera + detalle), reportes |
| `datos/` | Acceso a datos: conexión, `ejecutar_sp()` y un módulo por tabla o documento |
| `sql/odaxfarma_compras_COMPLETO.sql` | **Script único**: crea la BD, procedimientos, triggers, reportes, datos de prueba y el usuario |
| `sql/00` … `sql/08` | Los mismos scripts por partes |
| `config.example.ini` | Plantilla de configuración de la conexión |
| `requirements.txt` | Dependencias |

## Instalación y ejecución

1. Instalar **MySQL 8.0** (8.0.16 o superior).
2. Crear la base de datos ejecutando como `root` el script único:
   - En MySQL Workbench: *File → Open SQL Script* → `sql/odaxfarma_compras_COMPLETO.sql` → *Execute*.
   - O en CMD: `mysql -u root -p --default-character-set=utf8mb4 < sql\odaxfarma_compras_COMPLETO.sql`
3. Copiar `config.example.ini` como `config.ini` (ya trae las credenciales de prueba).
4. Instalar y ejecutar:
   ```
   python -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt
   python main.py
   ```

## Credenciales de prueba

| Dato | Valor |
|---|---|
| Servidor | `localhost`, puerto `3306` |
| Base de datos | `odaxfarma_compras` |
| Usuario del aplicativo | `odax_app` |
| Contraseña | `OdaxApp2026!` |

El aplicativo no tiene inicio de sesión de usuarios: se conecta con la cuenta `odax_app` configurada en `config.ini`.

## Módulos

- **Maestros:** Proveedores y Productos (listar, buscar, insertar, modificar, anular y reactivar).
- **Documentos:** Requerimientos, Cotizaciones, Órdenes de compra (se generan desde la cotización),
  Pagos (se solicitan y luego se ejecutan) y Guías de remisión (admite entregas parciales).
- **Reportes:** 12 reportes como procedimientos almacenados (9 con JOIN), exportables a CSV.

## Reglas del negocio garantizadas en la base de datos

- Borrado lógico: los registros se anulan; los triggers bloquean el borrado físico.
- Productos de la cotización ⊆ requerimiento; de la orden ⊆ cotización; de la guía ⊆ orden.
- Lo recibido en todas las guías no supera lo ordenado.
- Cada pago va en la moneda de su cotización y la suma de pagos no supera el total de la orden.
- Solo los pagos **ejecutados** reducen el saldo; un pago ejecutado no se modifica ni se anula.
- Toda operación queda registrada en `tb_auditoria`.

## Base de datos (resumen)

12 tablas (11 del modelo + auditoría), 2 vistas, 62 procedimientos almacenados y 41 triggers.
Datos de prueba: documentos reales y orientativos de Odax Farma, más datos ficticios marcados
como tales en los scripts.
