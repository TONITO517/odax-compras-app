"""
Capa de interfaz – módulo Reportes.

A la izquierda se elige el reporte; a la derecha se ingresan sus
parámetros, se genera y se muestra el resultado. Las columnas de la tabla
se crean según lo que devuelva el procedimiento. El resultado se puede
exportar a CSV para abrirlo en Excel.
"""
import csv
import re
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from datos import combos, reportes
from datos.repositorio import ErrorBD
from .vista_documento import SEPARADOR, codigo_de

FORMATO_FECHA = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class VentanaReportes(tk.Toplevel):
    def __init__(self, padre):
        super().__init__(padre)
        self.title("Reportes")
        self.geometry("1250x700")
        self.reporte = None
        self.controles = []           # [(tipo, StringVar)]
        self.columnas = []
        self.filas = []

        panel = ttk.Frame(self, padding=8)
        panel.pack(side="left", fill="y")
        ttk.Label(panel, text="Reportes disponibles", font=("Segoe UI", 10, "bold")).pack(anchor="w")
        self.lista = tk.Listbox(panel, width=42, height=20, exportselection=False)
        for r in reportes.REPORTES:
            self.lista.insert("end", r["nombre"])
        self.lista.pack(fill="y", expand=True, pady=4)
        self.lista.bind("<<ListboxSelect>>", self._al_elegir)

        derecha = ttk.Frame(self, padding=8)
        derecha.pack(side="left", fill="both", expand=True)
        self.lbl_titulo = ttk.Label(derecha, text="Elija un reporte de la lista",
                                    font=("Segoe UI", 12, "bold"))
        self.lbl_titulo.pack(anchor="w")
        self.lbl_desc = ttk.Label(derecha, text="", foreground="gray", wraplength=850)
        self.lbl_desc.pack(anchor="w", pady=(2, 6))

        self.marco_param = ttk.LabelFrame(derecha, text="Parámetros", padding=8)
        self.marco_param.pack(fill="x")

        botones = ttk.Frame(derecha)
        botones.pack(fill="x", pady=6)
        ttk.Button(botones, text="Generar reporte", command=self.generar).pack(side="left")
        ttk.Button(botones, text="Exportar a CSV (Excel)", command=self.exportar).pack(side="left", padx=6)
        ttk.Button(botones, text="Cerrar", command=self.destroy).pack(side="left")
        self.lbl_total = ttk.Label(botones, text="", foreground="#1F3864")
        self.lbl_total.pack(side="left", padx=12)

        marco_tabla = ttk.Frame(derecha)
        marco_tabla.pack(fill="both", expand=True)
        self.tabla = ttk.Treeview(marco_tabla, show="headings")
        barra_y = ttk.Scrollbar(marco_tabla, orient="vertical", command=self.tabla.yview)
        barra_x = ttk.Scrollbar(marco_tabla, orient="horizontal", command=self.tabla.xview)
        self.tabla.configure(yscrollcommand=barra_y.set, xscrollcommand=barra_x.set)
        barra_y.pack(side="right", fill="y")
        barra_x.pack(side="bottom", fill="x")
        self.tabla.pack(fill="both", expand=True)

    # ------------------------------------------------------- parámetros
    def _al_elegir(self, _evento):
        seleccion = self.lista.curselection()
        if not seleccion:
            return
        self.reporte = reportes.REPORTES[seleccion[0]]
        self.lbl_titulo.configure(text=self.reporte["nombre"])
        self.lbl_desc.configure(text=self.reporte["descripcion"] + f"   [procedimiento: {self.reporte['sp']}]")
        self._crear_parametros()
        self._limpiar_resultado()

    def _crear_parametros(self):
        for w in self.marco_param.winfo_children():
            w.destroy()
        self.controles = []
        if not self.reporte["parametros"]:
            ttk.Label(self.marco_param, text="Este reporte no necesita parámetros.").grid(row=0, column=0)
            return
        for i, (tipo, etiqueta) in enumerate(self.reporte["parametros"]):
            ttk.Label(self.marco_param, text=etiqueta + ":").grid(row=0, column=i * 2, sticky="e", padx=4)
            var = tk.StringVar()
            if tipo in ("requerimiento", "orden", "producto", "tabla"):
                try:
                    if tipo == "tabla":
                        valores = reportes.TABLAS_AUDITADAS
                    else:
                        fuente = {"requerimiento": combos.requerimientos, "orden": combos.ordenes,
                                  "producto": combos.productos}[tipo]
                        valores = [f"{a}{SEPARADOR}{b}" for a, b in fuente()]
                except ErrorBD as e:
                    messagebox.showerror("Error", str(e), parent=self)
                    valores = []
                w = ttk.Combobox(self.marco_param, textvariable=var, values=[""] + valores,
                                 state="readonly", width=40)
            else:
                w = ttk.Entry(self.marco_param, textvariable=var, width=14)
                if tipo == "entero":
                    var.set("10")
            w.grid(row=0, column=i * 2 + 1, sticky="w", padx=4)
            self.controles.append((tipo, var))
        ttk.Label(self.marco_param, text="Fechas con formato AAAA-MM-DD; vacío = sin límite.",
                  foreground="gray").grid(row=1, column=0, columnspan=8, sticky="w", pady=(4, 0))

    def _leer_parametros(self):
        valores = []
        for tipo, var in self.controles:
            texto = var.get().strip()
            if not texto:
                valores.append(None)
            elif tipo == "fecha":
                if not FORMATO_FECHA.match(texto):
                    raise ValueError(f"La fecha '{texto}' no tiene el formato AAAA-MM-DD.")
                valores.append(texto)
            elif tipo == "entero":
                if not texto.isdigit():
                    raise ValueError("La cantidad debe ser un número entero.")
                valores.append(int(texto))
            elif tipo == "tabla":
                valores.append(texto)
            else:
                valores.append(codigo_de(texto))
        return tuple(valores)

    # ---------------------------------------------------------- resultado
    def _limpiar_resultado(self):
        self.tabla.delete(*self.tabla.get_children())
        self.tabla.configure(columns=())
        self.columnas, self.filas = [], []
        self.lbl_total.configure(text="")

    def generar(self):
        if not self.reporte:
            messagebox.showwarning("Reporte", "Elija un reporte de la lista.", parent=self)
            return
        try:
            parametros = self._leer_parametros()
            columnas, filas = reportes.ejecutar(self.reporte["sp"], parametros)
        except ValueError as e:
            messagebox.showwarning("Parámetros", str(e), parent=self)
            return
        except ErrorBD as e:
            messagebox.showerror("No se pudo generar", str(e), parent=self)
            return
        self._limpiar_resultado()
        self.columnas = list(columnas)
        self.filas = [["" if v is None else str(v) for v in f] for f in filas]
        self.tabla.configure(columns=self.columnas)
        for i, col in enumerate(self.columnas):
            largo = max([len(col)] + [len(f[i]) for f in self.filas[:200]])
            self.tabla.heading(col, text=col.replace("_", " ").capitalize())
            self.tabla.column(col, width=min(max(70, largo * 8), 380))
        for f in self.filas:
            self.tabla.insert("", "end", values=f)
        self.lbl_total.configure(text=f"{len(self.filas)} fila(s)")

    def exportar(self):
        if not self.filas:
            messagebox.showwarning("Exportar", "Primero genere un reporte con resultados.", parent=self)
            return
        nombre = self.reporte["sp"].replace("sp_rep_", "reporte_") + ".csv"
        ruta = filedialog.asksaveasfilename(parent=self, defaultextension=".csv", initialfile=nombre,
                                            filetypes=[("CSV (Excel)", "*.csv")])
        if not ruta:
            return
        with open(ruta, "w", newline="", encoding="utf-8-sig") as archivo:
            escritor = csv.writer(archivo, delimiter=";")
            escritor.writerow(self.columnas)
            escritor.writerows(self.filas)
        messagebox.showinfo("Exportar", f"Reporte guardado en:\n{ruta}", parent=self)


def abrir(padre):
    VentanaReportes(padre)
