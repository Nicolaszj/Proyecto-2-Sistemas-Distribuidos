"""
PUNTO 8 - Visualización con matplotlib (reporte estático en PNG).

Pide a la API (API Gateway -> Lambda -> Athena) el resultado de las 6
preguntas de negocio y dibuja una gráfica por pregunta, más un tablero con
las 6 juntas. Sirve como evidencia para el informe.

Uso (PC con Python, o AWS CloudShell):
    pip install matplotlib
    python generar_graficas.py --api https://xxxx.execute-api.us-east-1.amazonaws.com
Salida: carpeta graficas/ con p1.png ... p6.png y tablero.png
"""
import argparse
import json
import os
import urllib.request

import matplotlib

matplotlib.use("Agg")  # sin ventana: solo guarda archivos
import matplotlib.pyplot as plt  # noqa: E402

DIAS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]


def pedir(api, ruta):
    with urllib.request.urlopen(f"{api.rstrip('/')}{ruta}", timeout=40) as r:
        return json.loads(r.read().decode("utf-8"))


def columna(datos, nombre):
    return [f[nombre] for f in datos["filas"]]


def dibujar(ax, pid, d):
    """Una gráfica por pregunta, según su forma."""
    if pid == "p1":
        ax.bar(columna(d, "pais"), [v / 1e6 for v in columna(d, "ingreso_neto_usd")], color="#2563eb")
        ax.set_ylabel("millones de USD")
        ax.tick_params(axis="x", rotation=45)
    elif pid == "p2":
        ax.plot(columna(d, "periodo"), [v / 1e6 for v in columna(d, "ingreso_neto_usd")], marker="o", color="#059669")
        ax.set_ylabel("millones de USD")
        ax.tick_params(axis="x", rotation=45)
    elif pid == "p3":
        etiquetas = [t[:28] for t in columna(d, "descripcion")][::-1]
        ax.barh(etiquetas, [v / 1e3 for v in columna(d, "ingreso_neto_gbp")][::-1], color="#7c3aed")
        ax.set_xlabel("miles de GBP")
    elif pid == "p4":
        ax.bar(columna(d, "pais"), columna(d, "usd_por_mil_habitantes"), color="#ea580c")
        ax.set_ylabel("USD por 1.000 habitantes")
        ax.tick_params(axis="x", rotation=45)
    elif pid == "p5":
        ax.bar(columna(d, "region_comercial"), columna(d, "tasa_devolucion_pct"), color="#dc2626")
        ax.set_ylabel("% devuelto del valor vendido")
        ax.tick_params(axis="x", rotation=45)
    elif pid == "p6":
        matriz = [[0] * 24 for _ in DIAS]
        for f in d["filas"]:
            matriz[f["dia_semana"] - 1][f["hora"]] = f["facturas"]
        im = ax.imshow([fila[6:21] for fila in matriz], aspect="auto", cmap="Blues")
        ax.set_yticks(range(7), DIAS)
        ax.set_xticks(range(15), [str(h) for h in range(6, 21)])
        ax.set_xlabel("hora del día")
        plt.colorbar(im, ax=ax, label="facturas")
    for etiqueta in ax.get_xticklabels():
        etiqueta.set_horizontalalignment("right" if pid in ("p1", "p2", "p4", "p5") else "center")
    ax.set_title(f"{pid.upper()}. {d['titulo']}", fontsize=11)
    ax.grid(axis="y", alpha=0.3)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--api", default=os.environ.get("API_URL"), required=not os.environ.get("API_URL"))
    p.add_argument("--salida", default="graficas")
    a = p.parse_args()
    os.makedirs(a.salida, exist_ok=True)

    resultados = {}
    for pregunta in pedir(a.api, "/preguntas"):
        pid = pregunta["id"]
        resultados[pid] = pedir(a.api, f"/preguntas/{pid}")
        figura, ax = plt.subplots(figsize=(9, 5.5))
        dibujar(ax, pid, resultados[pid])
        figura.tight_layout()
        figura.savefig(os.path.join(a.salida, f"{pid}.png"), dpi=130)
        plt.close(figura)
        print(f"{pid}: {len(resultados[pid]['filas'])} filas -> {a.salida}/{pid}.png")

    figura, ejes = plt.subplots(2, 3, figsize=(20, 11))
    for ax, (pid, d) in zip(ejes.flat, resultados.items()):
        dibujar(ax, pid, d)
    figura.suptitle("Proyecto 2 · Analítica de ventas retail (fuente: API Gateway → Athena → refined)", fontsize=15)
    figura.tight_layout()
    figura.savefig(os.path.join(a.salida, "tablero.png"), dpi=110)
    print(f"tablero -> {a.salida}/tablero.png")


if __name__ == "__main__":
    main()
