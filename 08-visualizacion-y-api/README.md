# Punto 8 · Visualización y aplicación expuesta con API Gateway + Streamlit

> **Enunciado:** realizar alguna aplicación de visualización de datos (matplotlib, dash, powerBI, grafana, etc.) y
> alguna aplicación expuesta mediante API Gateway con Streamlit de Python.

## Qué hicimos

```
Navegador ──► Streamlit (EC2 :8501) ──┐
matplotlib (PC/CloudShell) ───────────┼──► API Gateway (HTTP API) ──► Lambda ──► Athena ──► retail_refined (S3 refined/)
curl / navegador ─────────────────────┘     /salud  /preguntas  /preguntas/{p1..p6}
```

1. **API** (`api/lambda_function.py`, `infra/api.tf`): **API Gateway** HTTP API con 3 rutas `GET`, integrada con
   una **Lambda** (Python 3.12, rol `LabRole`). Para `/preguntas/{id}` la Lambda lanza en Athena
   `SELECT * FROM retail_refined.<tabla> ORDER BY …`, espera el resultado, convierte los tipos y responde JSON con
   la pregunta, las fuentes, las filas, **el SQL usado y el id de ejecución de Athena** (trazabilidad para la demo).
2. **Streamlit** (`streamlit/app.py`, `infra/app_streamlit.tf`): tablero en una EC2 (servicio systemd en el puerto
   8501). Llama a la API, y por cada pregunta muestra la **respuesta en una frase**, una gráfica (Altair: barras,
   línea o mapa de calor), la tabla y un desplegable con el SQL y el id de Athena.
3. **matplotlib** (`matplotlib/generar_graficas.py`): también consume la API y genera `p1.png … p6.png` y un
   `tablero.png` con las 6 gráficas, para el informe.

**¿Por qué Streamlit no está "detrás" de API Gateway?** Streamlit mantiene la página viva con **WebSockets** y API
Gateway HTTP no los reenvía (la página se queda "Connecting…"). La arquitectura correcta es la que usamos: API
Gateway expone los **datos** como servicio y Streamlit es un **cliente** de esa API. Cualquier otro cliente
(matplotlib, curl, Power BI, otra app) usa la misma API.

## Archivos

| Archivo | Qué hace |
|---|---|
| `api/lambda_function.py` | Rutas, catálogo de preguntas (`PREGUNTAS`), consulta a Athena y conversión de tipos |
| `streamlit/app.py` | Tablero. Variable de entorno `API_URL` (la pone Terraform en el servicio systemd) |
| `streamlit/requirements.txt` | streamlit, pandas, altair, requests |
| `matplotlib/generar_graficas.py` | Gráficas estáticas a partir de la API |
| `../infra/api.tf` | Lambda (empaquetada con `archive_file`), API HTTP, integración, rutas, stage `$default`, permiso |
| `../infra/app_streamlit.tf` + `plantillas/streamlit_user_data.sh.tftpl` | EC2 con Python 3.11 + Streamlit como servicio |

## Cómo verificarlo

```bash
scripts/probar_api.sh                                     # llama /salud, /preguntas y p1…p6
cd infra && terraform output streamlit_url                # abrir en el navegador (tarda ~3 min tras crearse la EC2)
# Gráficas matplotlib (en CloudShell o en el PC):
pip install matplotlib
python3 ../08-visualizacion-y-api/matplotlib/generar_graficas.py --api "$(terraform output -raw api_url)"
```

En el PC (PowerShell), el tablero también corre local apuntando a la misma API:

```powershell
cd 08-visualizacion-y-api\streamlit
pip install -r requirements.txt
$env:API_URL = "https://<id>.execute-api.us-east-1.amazonaws.com"
streamlit run app.py
```

## Evidencias

| Id | Captura |
|---|---|
| E25 | API Gateway → `retail-p2-api` → *Routes*, y el navegador/curl con `…/preguntas/p1` en JSON |
| E26 | Tablero Streamlit en la URL pública: P1 con gráfica, tabla y respuesta en una frase |
| E27 | Tablero Streamlit: P6 (mapa de calor) con el desplegable "¿De dónde salió este resultado?" abierto |
| E28 | `tablero.png` generado con matplotlib |
