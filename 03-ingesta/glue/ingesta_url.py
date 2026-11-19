"""
PUNTO 3 - Ingesta automática: URLs públicas de internet  ->  S3 zona raw.

Job de AWS Glue tipo "Python shell" (no necesita Spark: son 3 descargas
pequeñas). Lo crea Terraform (infra/glue_jobs.tf) y lo dispara el workflow de
Glue junto con la ingesta del RDS.

Fuentes (APIs abiertas, sin llave):
  1. frankfurter        Tasas de cambio diarias GBP->USD y GBP->EUR del Banco
                        Central Europeo (dic-2010 a dic-2011). Sirven para
                        pasar las ventas (que están en libras) a dólares.
  2. worldbank_poblacion  Población total por país en 2011 (indicador SP.POP.TOTL).
  3. worldbank_pib        PIB per cápita en USD por país en 2011 (NY.GDP.PCAP.CD).

Qué escribe (el JSON exactamente como lo devuelve la API, sin tocarlo):
  s3://<bucket>/raw/url/<fuente>/fecha_ingesta=AAAA-MM-DD/<fuente>.json

Argumentos:
  --DATALAKE  s3://<bucket>   (o file:///ruta/local para probar en un PC)
"""
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone

FUENTES = {
    "frankfurter": "https://api.frankfurter.dev/v1/2010-12-01..2011-12-31?from=GBP&to=USD,EUR",
    "worldbank_poblacion": "https://api.worldbank.org/v2/country/all/indicator/SP.POP.TOTL"
                           "?date=2011&format=json&per_page=500",
    "worldbank_pib": "https://api.worldbank.org/v2/country/all/indicator/NY.GDP.PCAP.CD"
                     "?date=2011&format=json&per_page=500",
}


def leer_argumentos(argv):
    """Convierte ['--CLAVE', 'valor', ...] en {'CLAVE': 'valor'} (igual que Glue)."""
    args = {}
    for i, token in enumerate(argv):
        if token.startswith("--") and i + 1 < len(argv) and not argv[i + 1].startswith("--"):
            args[token[2:]] = argv[i + 1]
    return args


def descargar(url, intentos=4):
    """GET con reintentos. Valida que la respuesta sea JSON antes de devolverla."""
    for intento in range(1, intentos + 1):
        try:
            peticion = urllib.request.Request(url, headers={"User-Agent": "proyecto2-bigdata-eafit"})
            with urllib.request.urlopen(peticion, timeout=60) as r:
                cuerpo = r.read()
            json.loads(cuerpo)  # si no es JSON válido, lanza error y se reintenta
            return cuerpo
        except Exception as error:  # noqa: BLE001 - queremos reintentar cualquier fallo de red
            print(f"[ingesta_url] intento {intento} falló para {url}: {error}")
            if intento == intentos:
                raise
            time.sleep(5 * intento)


def guardar(datalake, clave, contenido):
    """Escribe en S3 (s3://bucket) o en disco (file:///ruta) según el prefijo."""
    if datalake.startswith("s3://"):
        import boto3  # disponible en Glue Python shell

        bucket = datalake[len("s3://"):].split("/")[0]
        boto3.client("s3").put_object(Bucket=bucket, Key=clave, Body=contenido,
                                      ContentType="application/json")
    else:
        ruta = os.path.join(datalake.replace("file://", ""), clave)
        os.makedirs(os.path.dirname(ruta), exist_ok=True)
        with open(ruta, "wb") as f:
            f.write(contenido)


def main():
    args = leer_argumentos(sys.argv)
    datalake = args["DATALAKE"].rstrip("/")
    fecha_ingesta = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for fuente, url in FUENTES.items():
        contenido = descargar(url)
        clave = f"raw/url/{fuente}/fecha_ingesta={fecha_ingesta}/{fuente}.json"
        guardar(datalake, clave, contenido)
        print(f"[ingesta_url] {fuente}: {len(contenido)} bytes -> {datalake}/{clave}")


if __name__ == "__main__":
    main()
