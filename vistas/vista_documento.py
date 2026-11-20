"""
Capa de interfaz – ventana genérica de documentos (cabecera + detalle).

Una sola clase sirve para Requerimientos, Cotizaciones, Órdenes, Pagos y
Guías. Cada módulo le indica:
  * las columnas de la lista (en el orden en que las devuelve sp_..._listar),
  * los campos de la cabecera,
  * las funciones de la capa de datos (listar, insertar, modificar, anular),
  * opcionalmente, la configuración del detalle de productos y botones extra.
"""
import tkinter as tk
from datetime import date
from tkinter import messagebox, ttk

from datos.repositorio import ErrorBD

SEPARADOR = " | "          # en los combos se muestra "CÓDIGO | descripción"


def codigo_de(texto):
    """Extrae el código de un valor de combo ("COD | descripción" -> "COD")."""
    return texto.split(SEPARADOR)[0].strip()


class VentanaDocumento(tk.Toplevel):
    def __init__(self, padre, titulo, columnas, campos, datos, detalle=None, acciones=None):
        """
        columnas: [(nombre, etiqueta, ancho), ...] tal como las devuelve el procedimiento de listado.
        campos:   [{nombre, etiqueta, tipo, clave, solo_nuevo, opcional, combo, opciones, defecto}, ...]
                  tipo: "texto" | "fecha" | "numero" | "combo" (desde la BD) | "opciones" (lista fija)
        datos:    módulo de la capa de datos con listar, insertar(d), modificar(d), anular(clave).
        detalle:  {titulo, columnas, listar(clave), productos(clave), campos[(nombre, etiqueta, columna)],
                   guardar(clave, codigo, d), quitar(clave, codigo)}  (opcional)
        acciones: [(texto del botón, funcion(ventana)), ...]  (opcional)
        """
        super().__init__(padre)
        self.title(titulo)
        self.geometry("1180x760")
        self.columnas = columnas
        self.nombres_columnas = [c[0] for c in columnas]
        self.campos = campos
        self.datos = datos
        self.detalle = detalle
        self.acciones = acciones or []
        self.clave_actual = None                     # None = registrando un documento nuevo
        self.variables = {c["nombre"]: tk.StringVar() for c in campos}
        self.entradas = {}

        self._crear_busqueda()
        self._crear_lista()
        self._crear_cabecera()
        if self.detalle:
            self._crear_detalle()
        self.nuevo()
        self.cargar()

    # ================================================================ UI
    def _crear_busqueda(self):
        marco = ttk.Frame(self, padding=(8, 8, 8, 4))
        marco.pack(fill="x")
        ttk.Label(marco, text="Buscar:").pack(side="left")
        self.texto_busqueda = tk.StringVar()
        entrada = ttk.Entry(marco, textvariable=self.texto_busqueda, width=40)
        entrada.pack(side="left", padx=6)
        entrada.bind("<Return>", lambda _e: self.cargar())
        self.ver_anulados = tk.BooleanVar(value=False)
        ttk.Checkbutton(marco, text="Mostrar anulados", variable=self.ver_anulados,
                        command=self.cargar).pack(side="left", padx=6)
        ttk.Button(marco, text="Buscar", command=self.cargar).pack(side="left")

    def _crear_lista(self):
        marco = ttk.Frame(self, padding=(8, 0))
        marco.pack(fill="both", expand=True)
        self.lista = ttk.Treeview(marco, columns=self.nombres_columnas, show="headings", height=7)
        for nombre, etiqueta, ancho in self.columnas:
            self.lista.heading(nombre, text=etiqueta)
            self.lista.column(nombre, width=ancho)
        self.lista.tag_configure("anulado", foreground="gray")
        barra = ttk.Scrollbar(marco, orient="vertical", command=self.lista.yview)
        self.lista.configure(yscrollcommand=barra.set)
        self.lista.pack(side="left", fill="both", expand=True)
        barra.pack(side="right", fill="y")
        self.lista.bind("<<TreeviewSelect>>", self._al_seleccionar)

    def _crear_cabecera(self):
        marco = ttk.LabelFrame(self, text="Datos del documento", padding=8)
        marco.pack(fill="x", padx=8, pady=6)
        for i, c in enumerate(self.campos):
            fila, col = divmod(i, 3)
            ttk.Label(marco, text=c["etiqueta"] + ":").grid(row=fila, column=col * 2, sticky="e", padx=4, pady=3)
            var = self.variables[c["nombre"]]
            if c["tipo"] in ("combo", "opciones"):
                w = ttk.Combobox(marco, textvariable=var, state="readonly", width=c.get("ancho", 30))
                if c["tipo"] == "opciones":
                    w.configure(values=c["opciones"])
            else:
                w = ttk.Entry(marco, textvariable=var, width=c.get("ancho", 32))
            w.grid(row=fila, column=col * 2 + 1, sticky="w", padx=4, pady=3)
            self.entradas[c["nombre"]] = w

        botones = ttk.Frame(marco)
        botones.grid(row=20, column=0, columnspan=6, pady=(8, 0))
        ttk.Button(botones, text="Nuevo", command=self.nuevo).pack(side="left", padx=4)
        ttk.Button(botones, text="Guardar", command=self.guardar).pack(side="left", padx=4)
        ttk.Button(botones, text="Anular", command=self.anular).pack(side="left", padx=4)
        for texto, funcion in self.acciones:
            ttk.Button(botones, text=texto, command=lambda f=funcion: f(self)).pack(side="left", padx=4)
        ttk.Button(botones, text="Cerrar", command=self.destroy).pack(side="left", padx=4)
        self.lbl_modo = ttk.Label(marco, text="", foreground="#1F3864")
        self.lbl_modo.grid(row=21, column=0, columnspan=6, pady=(4, 0))

    def _crear_detalle(self):
        cfg = self.detalle
        marco = ttk.LabelFrame(self, text=cfg["titulo"], padding=8)
        marco.pack(fill="both", expand=True, padx=8, pady=(0, 8))
        nombres = [c[0] for c in cfg["columnas"]]
        self.lista_detalle = ttk.Treeview(marco, columns=nombres, show="headings", height=6)
        for nombre, etiqueta, ancho in cfg["columnas"]:
            self.lista_detalle.heading(nombre, text=etiqueta)
            self.lista_detalle.column(nombre, width=ancho)
        self.lista_detalle.pack(fill="both", expand=True)
        self.lista_detalle.bind("<<TreeviewSelect>>", self._al_seleccionar_detalle)

        controles = ttk.Frame(marco)
        controles.pack(fill="x", pady=(6, 0))
        ttk.Label(controles, text="Producto:").pack(side="left")
        self.var_producto = tk.StringVar()
        self.combo_producto = ttk.Combobox(controles, textvariable=self.var_producto,
                                           state="readonly", width=48)
        self.combo_producto.pack(side="left", padx=4)
        self.variables_detalle = {}
        for nombre, etiqueta, _columna in cfg["campos"]:
            ttk.Label(controles, text=etiqueta + ":").pack(side="left", padx=(8, 0))
            var = tk.StringVar()
            ttk.Entry(controles, textvariable=var, width=10).pack(side="left", padx=4)
            self.variables_detalle[nombre] = var
        ttk.Button(controles, text="Agregar / actualizar", command=self.guardar_detalle).pack(side="left", padx=6)
        ttk.Button(controles, text="Quitar", command=self.quitar_detalle).pack(side="left")

    # ========================================================== utilidades
    def mostrar_error(self, e):
        messagebox.showerror("No se pudo completar", str(e), parent=self)

    def _campo_clave(self):
        return next(c for c in self.campos if c.get("clave"))

    def _refrescar_combos(self):
        """Vuelve a pedir a la BD las opciones de los combos de la cabecera."""
        for c in self.campos:
            if c["tipo"] == "combo":
                try:
                    pares = c["combo"]()
                except ErrorBD as e:
                    self.mostrar_error(e)
                    pares = []
                self.entradas[c["nombre"]].configure(values=[f"{a}{SEPARADOR}{b}" for a, b in pares])

    def _fila_a_diccionario(self, valores):
        return dict(zip(self.nombres_columnas, valores))

    # ============================================================ listado
    def cargar(self):
        """Pide la lista al procedimiento sp_..._listar y la muestra."""
        try:
            _cols, filas = self.datos.listar(self.texto_busqueda.get().strip(), self.ver_anulados.get())
        except ErrorBD as e:
            self.mostrar_error(e)
            return
        self.lista.delete(*self.lista.get_children())
        for f in filas:
            valores = ["" if v is None else str(v) for v in f]
            tag = ("anulado",) if valores[-1] != "ACTIVO" else ()
            self.lista.insert("", "end", values=valores, tags=tag)

    def seleccionar(self, clave):
        """Selecciona en la lista el documento con esa clave y lo carga en el formulario."""
        for item in self.lista.get_children():
            if str(self.lista.item(item, "values")[0]) == str(clave):
                self.lista.selection_set(item)
                self.lista.see(item)
                self._llenar_formulario(self.lista.item(item, "values"))
                return

    def _al_seleccionar(self, _evento):
        seleccion = self.lista.selection()
        if seleccion:
            self._llenar_formulario(self.lista.item(seleccion[0], "values"))

    def _llenar_formulario(self, valores):
        fila = self._fila_a_diccionario(valores)
        for c in self.campos:
            self.variables[c["nombre"]].set(fila.get(c["nombre"], ""))
            bloqueado = c.get("clave") or c.get("solo_nuevo")
            self.entradas[c["nombre"]].configure(state="disabled" if bloqueado else
                                                 ("readonly" if c["tipo"] in ("combo", "opciones") else "normal"))
        self.clave_actual = fila[self._campo_clave()["nombre"]]
        self.lbl_modo.configure(text=f"Modo: modificar {self.clave_actual} ({fila.get('estado', '')})")
        self.cargar_detalle()

    # ========================================================== cabecera
    def nuevo(self):
        self.clave_actual = None
        self._refrescar_combos()
        for c in self.campos:
            if c["tipo"] == "fecha":
                valor = date.today().isoformat()
            else:
                valor = c.get("defecto", "")
            self.variables[c["nombre"]].set(valor)
            self.entradas[c["nombre"]].configure(
                state="readonly" if c["tipo"] in ("combo", "opciones") else "normal")
        self.lista.selection_remove(self.lista.selection())
        self.lbl_modo.configure(text="Modo: nuevo documento (guárdelo para poder agregar productos)")
        self.cargar_detalle()

    def _leer_formulario(self):
        d = {}
        for c in self.campos:
            valor = self.variables[c["nombre"]].get().strip()
            if c["tipo"] == "combo":
                valor = codigo_de(valor)
            d[c["nombre"]] = valor or None
        return d

    def guardar(self):
        d = self._leer_formulario()
        faltan = [c["etiqueta"] for c in self.campos if not c.get("opcional") and d[c["nombre"]] is None]
        if faltan:
            messagebox.showwarning("Faltan datos", "Complete: " + ", ".join(faltan), parent=self)
            return
        clave = d[self._campo_clave()["nombre"]]
        try:
            if self.clave_actual is None:
                self.datos.insertar(d)
                messagebox.showinfo("Listo", f"Documento {clave} registrado.", parent=self)
            else:
                self.datos.modificar(d)
                messagebox.showinfo("Listo", f"Documento {clave} modificado.", parent=self)
        except ErrorBD as e:
            self.mostrar_error(e)
            return
        self._refrescar_combos()
        self.cargar()
        self.seleccionar(clave)

    def anular(self):
        if self.clave_actual is None:
            messagebox.showwarning("Seleccione", "Seleccione un documento de la lista.", parent=self)
            return
        if not messagebox.askyesno("Confirmar", f"¿Desea anular el documento {self.clave_actual}?", parent=self):
            return
        try:
            self.datos.anular(self.clave_actual)
        except ErrorBD as e:
            self.mostrar_error(e)
            return
        self.cargar()
        self.nuevo()

    # ============================================================ detalle
    def cargar_detalle(self):
        if not self.detalle:
            return
        self.lista_detalle.delete(*self.lista_detalle.get_children())
        self.var_producto.set("")
        for var in self.variables_detalle.values():
            var.set("")
        if self.clave_actual is None:
            self.combo_producto.configure(values=[])
            return
        try:
            _cols, filas = self.detalle["listar"](self.clave_actual)
            pares = self.detalle["productos"](self.clave_actual)
        except ErrorBD as e:
            self.mostrar_error(e)
            return
        for f in filas:
            self.lista_detalle.insert("", "end", values=["" if v is None else str(v) for v in f])
        self.combo_producto.configure(values=[f"{a}{SEPARADOR}{b}" for a, b in pares])

    def _al_seleccionar_detalle(self, _evento):
        seleccion = self.lista_detalle.selection()
        if not seleccion:
            return
        valores = self.lista_detalle.item(seleccion[0], "values")
        fila = dict(zip([c[0] for c in self.detalle["columnas"]], valores))
        self.var_producto.set(f"{valores[0]}{SEPARADOR}{valores[1]}")
        for nombre, _etiqueta, columna in self.detalle["campos"]:
            self.variables_detalle[nombre].set(fila.get(columna, ""))

    def guardar_detalle(self):
        if self.clave_actual is None:
            messagebox.showwarning("Primero la cabecera",
                                   "Guarde o seleccione un documento antes de agregar productos.", parent=self)
            return
        codigo = codigo_de(self.var_producto.get())
        d = {n: v.get().strip() or None for n, v in self.variables_detalle.items()}
        if not codigo or any(v is None for v in d.values()):
            messagebox.showwarning("Faltan datos", "Elija el producto y complete los valores.", parent=self)
            return
        try:
            self.detalle["guardar"](self.clave_actual, codigo, d)
        except ErrorBD as e:
            self.mostrar_error(e)
            return
        clave = self.clave_actual
        self.cargar()
        self.seleccionar(clave)

    def quitar_detalle(self):
        seleccion = self.lista_detalle.selection()
        if self.clave_actual is None or not seleccion:
            messagebox.showwarning("Seleccione", "Seleccione un producto del detalle.", parent=self)
            return
        codigo = self.lista_detalle.item(seleccion[0], "values")[0]
        if not messagebox.askyesno("Confirmar", f"¿Quitar el producto {codigo} del documento?", parent=self):
            return
        try:
            self.detalle["quitar"](self.clave_actual, codigo)
        except ErrorBD as e:
            self.mostrar_error(e)
            return
        clave = self.clave_actual
        self.cargar()
        self.seleccionar(clave)
