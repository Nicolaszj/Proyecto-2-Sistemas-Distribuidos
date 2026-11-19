#!/usr/bin/env python3
"""
PUNTO 2 - Simulación de las fuentes de datos.

Toma el dataset público "Online Retail" (UCI, ~541 mil líneas de factura de una
tienda online del Reino Unido, dic-2010 a dic-2011) y lo reparte como lo tendría
una empresa real en sus sistemas:

    ┌──────────────────────────────┐
    │ online-retail-dataset.csv    │
    └──────────────┬───────────────┘
                   │  este script
       ┌───────────┴─────────────────────────┐
       ▼                                     ▼
  Archivos en la EC2 (/srv/ventas)      Base de datos RDS MariaDB (retaildb)
  ventas_AAAA_MM.csv  (1 por mes)       customers, products, countries
  = exportes del sistema de caja        = datos maestros del ERP

Los archivos de ventas NO traen país ni descripción del producto (solo códigos),
igual que un exporte real de caja. Por eso, para responder las preguntas de
negocio hay que cruzar las ventas (EC2) con los maestros (RDS) y con los datos
públicos de internet (tasas de cambio y población), que llegan por URL (punto 3).

Solo usa la librería estándar de Python para poder correr en la EC2 sin instalar
nada. Lo ejecuta automáticamente el user_data de la EC2 (infra/plantillas/
fuente_ec2_user_data.sh.tftpl), pero también se puede correr en cualquier PC:

    python3 preparar_fuentes.py --zip datos/online-retail-dataset.csv.zip \
        --salida-archivos ./salida/ventas --salida-sql ./salida/seed_mariadb.sql
"""
import argparse
import csv
import io
import os
import zipfile
from collections import Counter, defaultdict
from datetime import datetime

# Columnas que conserva el "exporte de caja" que queda en la EC2.
COLUMNAS_VENTAS = ["InvoiceNo", "StockCode", "Quantity", "InvoiceDate", "UnitPrice", "CustomerID"]

# Maestro de países de la empresa: nombre tal como viene en el dataset,
# código ISO-3166 alfa-3 (sirve para cruzar con el Banco Mundial) y la región
# comercial que la empresa le asigna (dato simulado, propio del negocio).
PAISES = {
    "United Kingdom": ("GBR", "Reino Unido e Irlanda"),
    "EIRE": ("IRL", "Reino Unido e Irlanda"),
    "Channel Islands": ("CHI", "Reino Unido e Irlanda"),
    "France": ("FRA", "Europa Occidental"),
    "Germany": ("DEU", "Europa Occidental"),
    "Netherlands": ("NLD", "Europa Occidental"),
    "Belgium": ("BEL", "Europa Occidental"),
    "Switzerland": ("CHE", "Europa Occidental"),
    "Austria": ("AUT", "Europa Occidental"),
    "Portugal": ("PRT", "Europa Occidental"),
    "Spain": ("ESP", "Europa Occidental"),
    "Italy": ("ITA", "Europa Occidental"),
    "Malta": ("MLT", "Europa Occidental"),
    "Greece": ("GRC", "Europa Occidental"),
    "Cyprus": ("CYP", "Europa Occidental"),
    "European Community": ("", "Europa Occidental"),
    "Norway": ("NOR", "Países Nórdicos"),
    "Sweden": ("SWE", "Países Nórdicos"),
    "Finland": ("FIN", "Países Nórdicos"),
    "Denmark": ("DNK", "Países Nórdicos"),
    "Iceland": ("ISL", "Países Nórdicos"),
    "Poland": ("POL", "Europa del Este"),
    "Lithuania": ("LTU", "Europa del Este"),
    "Czech Republic": ("CZE", "Europa del Este"),
    "Australia": ("AUS", "Asia-Pacífico"),
    "Japan": ("JPN", "Asia-Pacífico"),
    "Hong Kong": ("HKG", "Asia-Pacífico"),
    "Singapore": ("SGP", "Asia-Pacífico"),
    "Israel": ("ISR", "Medio Oriente y África"),
    "United Arab Emirates": ("ARE", "Medio Oriente y África"),
    "RSA": ("ZAF", "Medio Oriente y África"),
    "Lebanon": ("LBN", "Medio Oriente y África"),
    "Bahrain": ("BHR", "Medio Oriente y África"),
    "Saudi Arabia": ("SAU", "Medio Oriente y África"),
    "USA": ("USA", "Américas"),
    "Canada": ("CAN", "Américas"),
    "Brazil": ("BRA", "Américas"),
    "Unspecified": ("", "Sin especificar"),
}


def leer_dataset(ruta_zip):
    """Devuelve un iterador de filas (dict) del CSV que está dentro del zip."""
    with zipfile.ZipFile(ruta_zip) as z:
        nombre = [n for n in z.namelist() if n.endswith(".csv")][0]
        with z.open(nombre) as f:
            texto = io.TextIOWrapper(f, encoding="latin-1", newline="")
            for fila in csv.DictReader(texto):
                yield fila


def escribir_archivos_ventas(filas, carpeta):
    """Un CSV por mes: ventas_2010_12.csv, ventas_2011_01.csv, ..."""
    os.makedirs(carpeta, exist_ok=True)
    abiertos = {}
    try:
        for fila in filas:
            fecha = datetime.strptime(fila["InvoiceDate"], "%m/%d/%Y %H:%M")
            nombre = "ventas_{:%Y_%m}.csv".format(fecha)
            if nombre not in abiertos:
                f = open(os.path.join(carpeta, nombre), "w", newline="", encoding="utf-8")
                w = csv.writer(f)
                w.writerow(COLUMNAS_VENTAS)
                abiertos[nombre] = (f, w)
            abiertos[nombre][1].writerow([fila[c] for c in COLUMNAS_VENTAS])
    finally:
        for f, _ in abiertos.values():
            f.close()
    return sorted(abiertos)


def sql_texto(valor):
    """Convierte un texto en literal SQL de MariaDB (escapa \\ y ')."""
    if valor is None or valor == "":
        return "NULL"
    return "'" + valor.replace("\\", "\\\\").replace("'", "\\'") + "'"


def insertar_por_lotes(salida, tabla, columnas, filas, lote=500):
    for i in range(0, len(filas), lote):
        valores = ",\n".join("(" + ", ".join(f) + ")" for f in filas[i:i + lote])
        salida.write("INSERT INTO {} ({}) VALUES\n{};\n".format(tabla, ", ".join(columnas), valores))


def escribir_sql_mariadb(filas, ruta_sql, ruta_esquema):
    """Genera el script con el esquema + los INSERT de los 3 maestros."""
    paises_por_cliente = defaultdict(Counter)
    descripciones = defaultdict(Counter)
    for fila in filas:
        cliente = fila["CustomerID"].strip()
        if cliente:
            paises_por_cliente[int(float(cliente))][fila["Country"].strip()] += 1
        codigo = fila["StockCode"].strip().upper()
        descripcion = fila["Description"].strip()
        if descripcion and not descripcion.startswith("?"):
            descripciones[codigo][descripcion] += 1
        else:
            descripciones[codigo]  # el código existe aunque no tenga descripción

    # Si un cliente compró desde 2 países, se queda con el más frecuente.
    clientes = sorted((c, cnt.most_common(1)[0][0]) for c, cnt in paises_por_cliente.items())
    # Cada producto se queda con su descripción más usada.
    productos = sorted((c, cnt.most_common(1)[0][0] if cnt else "") for c, cnt in descripciones.items())

    os.makedirs(os.path.dirname(os.path.abspath(ruta_sql)), exist_ok=True)
    with open(ruta_esquema, encoding="utf-8") as f:
        esquema = f.read()
    with open(ruta_sql, "w", encoding="utf-8") as salida:
        salida.write(esquema + "\n")
        insertar_por_lotes(salida, "countries", ["country", "iso3", "sales_region"],
                           [[sql_texto(p), sql_texto(i), sql_texto(r)] for p, (i, r) in sorted(PAISES.items())])
        insertar_por_lotes(salida, "customers", ["customer_id", "country"],
                           [[str(c), sql_texto(p)] for c, p in clientes])
        insertar_por_lotes(salida, "products", ["stock_code", "description"],
                           [[sql_texto(c), sql_texto(d)] for c, d in productos])
    return len(clientes), len(productos)


def main():
    aqui = os.path.dirname(os.path.abspath(__file__))
    p = argparse.ArgumentParser(description="Reparte el dataset Online Retail en las fuentes EC2 y RDS")
    p.add_argument("--zip", default=os.path.join(aqui, "datos", "online-retail-dataset.csv.zip"))
    p.add_argument("--salida-archivos", default=os.path.join(aqui, "salida", "ventas"))
    p.add_argument("--salida-sql", default=os.path.join(aqui, "salida", "seed_mariadb.sql"))
    p.add_argument("--esquema", default=os.path.join(aqui, "sql", "esquema_mariadb.sql"))
    a = p.parse_args()

    filas = list(leer_dataset(a.zip))
    print("Filas leídas del dataset:", len(filas))
    archivos = escribir_archivos_ventas(filas, a.salida_archivos)
    print("Archivos de ventas (fuente EC2):", len(archivos), "->", a.salida_archivos)
    n_cli, n_prod = escribir_sql_mariadb(filas, a.salida_sql, a.esquema)
    print("Script MariaDB (fuente RDS):", a.salida_sql)
    print("  countries:", len(PAISES), "| customers:", n_cli, "| products:", n_prod)


if __name__ == "__main__":
    main()
