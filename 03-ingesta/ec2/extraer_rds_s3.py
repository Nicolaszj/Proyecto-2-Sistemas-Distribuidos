#!/usr/bin/env python3
"""
PUNTO 3 - Ingesta automática: RDS MariaDB -> S3 zona raw.

Corre DENTRO de la EC2 fuente, que está en la misma VPC que el RDS privado.
No se ejecuta a mano ni con cron: lo ordena el job de Glue `ingesta-rds`
(03-ingesta/glue/ingesta_rds.py) mediante SSM Run Command, como primer paso del
workflow de Glue. Así el workflow sigue orquestando todo el proceso.

¿Por qué no lee Glue directamente el RDS por JDBC? En AWS Academy las interfaces
de red que Glue crea en la VPC nunca se conectan (quedan en estado "available"),
así que un job de Glue no alcanza una base privada. La EC2 sí la alcanza.

Qué hace por cada tabla (customers, products, countries):
  1. SELECT * con el cliente de MariaDB (credenciales en /opt/fuente/.my.cnf).
  2. Convierte la salida a CSV con encabezado (comillas dobles, escape con \\,
     igual que lo lee Spark en el punto 4).
  3. Lo sube a s3://<bucket>/raw/rds/<tabla>/fecha_ingesta=AAAA-MM-DD/<tabla>.csv
Solo usa la librería estándar de Python + mysql + aws cli (ya están en la EC2).
"""
import csv
import io
import re
import subprocess
import sys
from datetime import datetime, timezone

TABLAS = ["customers", "products", "countries"]
MY_CNF = "/opt/fuente/.my.cnf"
CONFIG = "/opt/fuente/config.env"
ESCAPES = {"n": "\n", "t": "\t", "0": "\0", "\\": "\\"}


def leer_bucket():
    with open(CONFIG) as f:
        for linea in f:
            if linea.startswith("BUCKET="):
                return linea.strip().split("=", 1)[1]
    raise SystemExit("No se encontró BUCKET en " + CONFIG)


def consultar(tabla):
    """Devuelve (columnas, filas) de una tabla usando el modo --batch de mysql."""
    salida = subprocess.run(
        ["mysql", f"--defaults-extra-file={MY_CNF}", "--batch", "-e", f"SELECT * FROM {tabla}", "retaildb"],
        check=True, capture_output=True, text=True).stdout
    lineas = salida.rstrip("\n").split("\n")

    def campo(valor):
        if valor == "NULL":  # así marca mysql --batch los nulos
            return ""
        return re.sub(r"\\(.)", lambda m: ESCAPES.get(m.group(1), m.group(1)), valor)

    columnas = lineas[0].split("\t")
    filas = [[campo(v) for v in linea.split("\t")] for linea in lineas[1:] if linea]
    return columnas, filas


def a_csv(columnas, filas):
    buffer = io.StringIO()
    escritor = csv.writer(buffer, quoting=csv.QUOTE_MINIMAL, doublequote=False,
                          escapechar="\\", lineterminator="\n")
    escritor.writerow(columnas)
    escritor.writerows(filas)
    return buffer.getvalue()


def main():
    bucket = leer_bucket() if len(sys.argv) < 2 else sys.argv[1]
    fecha = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for tabla in TABLAS:
        columnas, filas = consultar(tabla)
        destino = f"s3://{bucket}/raw/rds/{tabla}/fecha_ingesta={fecha}/{tabla}.csv"
        subprocess.run(["aws", "s3", "cp", "-", destino, "--only-show-errors"],
                       input=a_csv(columnas, filas), text=True, check=True)
        print(f"[extraer_rds] {tabla}: {len(filas)} filas -> {destino}")


if __name__ == "__main__":
    main()
