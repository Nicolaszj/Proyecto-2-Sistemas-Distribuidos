"""
PUNTO 8 - API de resultados: API Gateway (HTTP API) -> esta Lambda -> Athena.

Terraform (infra/api.tf) empaqueta este archivo en un .zip, crea la función
Lambda (rol LabRole) y la expone en API Gateway con estas rutas:

  GET /salud               -> {"estado": "ok"}             (para probar rápido)
  GET /preguntas           -> lista de las 6 preguntas de negocio
  GET /preguntas/{id}      -> resultado de la pregunta {id} = p1 ... p6

Para responder una pregunta, la Lambda lanza en Athena un SELECT sobre la tabla
de la zona refined (retail_refined.<tabla>, la llenó el punto 7 y la catalogó
el crawler refined), espera el resultado y lo devuelve en JSON junto con la
consulta SQL usada y el id de ejecución de Athena (para mostrarlo en la demo).

Quién la consume: el tablero Streamlit (08-.../streamlit/app.py) y el script de
gráficas matplotlib (08-.../matplotlib/generar_graficas.py).

Variables de entorno (las pone Terraform):
  ATHENA_WORKGROUP   workgroup con la carpeta de resultados configurada
  REFINED_DB         base de datos Glue de la zona refined (retail_refined)
"""
import json
import os
import time

import boto3

athena = boto3.client("athena")

# Catálogo de preguntas: lo que muestra el tablero y cómo graficarlo.
PREGUNTAS = {
    "p1": {"tabla": "p1_top_paises_ingreso_usd", "orden": "ingreso_neto_usd DESC",
           "titulo": "Top 10 países por ingreso neto (USD)",
           "pregunta": "¿Cuáles son los 10 países con mayor ingreso neto en dólares?",
           "fuentes": ["EC2 ventas", "RDS clientes", "URL tasas de cambio"],
           "grafica": {"tipo": "barras", "x": "pais", "y": "ingreso_neto_usd"}},
    "p2": {"tabla": "p2_ingreso_mensual", "orden": "anio, mes",
           "titulo": "Ingreso neto mensual",
           "pregunta": "¿Cómo evolucionó el ingreso mes a mes y cuál fue el mes pico?",
           "fuentes": ["EC2 ventas", "URL tasas de cambio"],
           "grafica": {"tipo": "linea", "x": "periodo", "y": "ingreso_neto_usd"}},
    "p3": {"tabla": "p3_top_productos", "orden": "ingreso_neto_gbp DESC",
           "titulo": "Top 10 productos por ingreso neto",
           "pregunta": "¿Cuáles son los 10 productos que más ingreso neto generan?",
           "fuentes": ["EC2 ventas", "RDS productos", "URL tasas de cambio"],
           "grafica": {"tipo": "barras_h", "x": "descripcion", "y": "ingreso_neto_gbp"}},
    "p4": {"tabla": "p4_gasto_por_habitante", "orden": "usd_por_mil_habitantes DESC",
           "titulo": "Gasto por cada 1.000 habitantes (USD)",
           "pregunta": "¿En qué países se gasta más en la tienda por cada 1.000 habitantes?",
           "fuentes": ["EC2 ventas", "RDS clientes y países", "URL Banco Mundial", "URL tasas de cambio"],
           "grafica": {"tipo": "barras", "x": "pais", "y": "usd_por_mil_habitantes"}},
    "p5": {"tabla": "p5_devoluciones_por_region", "orden": "tasa_devolucion_pct DESC",
           "titulo": "Tasa de devolución por región comercial",
           "pregunta": "¿Qué región comercial devuelve más (en % del valor vendido)?",
           "fuentes": ["EC2 ventas", "RDS clientes y países"],
           "grafica": {"tipo": "barras", "x": "region_comercial", "y": "tasa_devolucion_pct"}},
    "p6": {"tabla": "p6_ventas_dia_hora", "orden": "dia_semana, hora",
           "titulo": "Facturas por día de la semana y hora",
           "pregunta": "¿Qué días de la semana y a qué horas se concentran las compras?",
           "fuentes": ["EC2 ventas"],
           "grafica": {"tipo": "calor", "x": "hora", "y": "dia", "valor": "facturas"}},
}

TIPOS_ENTEROS = {"tinyint", "smallint", "integer", "int", "bigint"}
TIPOS_DECIMALES = {"double", "float", "real", "decimal"}


def respuesta(codigo, cuerpo):
    return {"statusCode": codigo,
            "headers": {"Content-Type": "application/json; charset=utf-8"},
            "body": json.dumps(cuerpo, ensure_ascii=False, default=str)}


def convertir(valor, tipo):
    """Athena devuelve todo como texto; lo pasamos a número según el tipo de la columna."""
    if valor is None:
        return None
    if tipo in TIPOS_ENTEROS:
        return int(valor)
    if tipo in TIPOS_DECIMALES:
        return float(valor)
    if tipo == "boolean":
        return valor.lower() == "true"
    return valor


def consultar_athena(sql):
    """Lanza la consulta, espera (máx. ~25 s, el límite de API Gateway es 30 s) y lee filas."""
    inicio = time.time()
    ejecucion = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": os.environ["REFINED_DB"]},
        WorkGroup=os.environ["ATHENA_WORKGROUP"],
    )["QueryExecutionId"]
    while True:
        estado = athena.get_query_execution(QueryExecutionId=ejecucion)["QueryExecution"]["Status"]
        if estado["State"] in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        if time.time() - inicio > 25:
            raise TimeoutError(f"Athena no terminó a tiempo (id {ejecucion})")
        time.sleep(0.5)
    if estado["State"] != "SUCCEEDED":
        raise RuntimeError(estado.get("StateChangeReason", estado["State"]))

    paginas = athena.get_paginator("get_query_results").paginate(QueryExecutionId=ejecucion)
    columnas, filas = None, []
    for pagina in paginas:
        info = pagina["ResultSet"]["ResultSetMetadata"]["ColumnInfo"]
        columnas = columnas or [(c["Name"], c["Type"].lower()) for c in info]
        for fila in pagina["ResultSet"]["Rows"]:
            valores = [d.get("VarCharValue") for d in fila["Data"]]
            if valores == [n for n, _ in columnas]:  # la primera fila es el encabezado
                continue
            filas.append({n: convertir(v, t) for (n, t), v in zip(columnas, valores)})
    return {"athena_query_id": ejecucion, "tiempo_ms": int((time.time() - inicio) * 1000),
            "columnas": [n for n, _ in columnas], "filas": filas}


def lambda_handler(event, context):
    ruta = event.get("rawPath", "/")
    parametros = event.get("pathParameters") or {}
    try:
        if ruta.endswith("/salud"):
            return respuesta(200, {"estado": "ok", "base_refined": os.environ["REFINED_DB"]})
        if ruta.endswith("/preguntas"):
            return respuesta(200, [{"id": k, **{c: v[c] for c in ("titulo", "pregunta", "fuentes", "tabla")}}
                                   for k, v in PREGUNTAS.items()])
        identificador = parametros.get("id", "").lower()
        if identificador not in PREGUNTAS:
            return respuesta(404, {"error": f"Pregunta '{identificador}' no existe. Use p1 ... p6."})
        meta = PREGUNTAS[identificador]
        sql = f"SELECT * FROM {os.environ['REFINED_DB']}.{meta['tabla']} ORDER BY {meta['orden']}"
        resultado = consultar_athena(sql)
        return respuesta(200, {"id": identificador, **meta, "consulta_sql": sql, **resultado})
    except Exception as error:  # noqa: BLE001 - la API siempre responde JSON, nunca un 502 mudo
        print(f"[api] error: {error!r}")
        return respuesta(500, {"error": str(error),
                               "pista": "¿Ya corrió el workflow de Glue y el crawler refined?"})
