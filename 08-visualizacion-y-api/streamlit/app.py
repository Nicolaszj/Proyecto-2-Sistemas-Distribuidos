"""
PUNTO 8 - Tablero Streamlit que consume la API publicada en API Gateway.

Flujo:  navegador -> Streamlit (EC2, puerto 8501) -> API Gateway -> Lambda -> Athena -> S3 refined

Terraform (infra/app_streamlit.tf) crea la EC2, copia este archivo y lo deja
corriendo como servicio (systemd) con la variable de entorno API_URL apuntando
al endpoint de API Gateway. Para correrlo en un PC:

    pip install -r requirements.txt
    API_URL=https://xxxx.execute-api.us-east-1.amazonaws.com streamlit run app.py
    (en PowerShell:  $env:API_URL="https://..." ; streamlit run app.py)

Por qué Streamlit no va "detrás" de API Gateway: Streamlit necesita WebSockets
para refrescar la página y API Gateway HTTP no los reenvía. Por eso API Gateway
expone los DATOS (la API) y Streamlit es el cliente que los muestra.
"""
import os

import altair as alt
import pandas as pd
import requests
import streamlit as st

API_URL = os.environ.get("API_URL", "").rstrip("/")

st.set_page_config(page_title="Proyecto 2 · Retail Big Data", page_icon="📊", layout="wide")


@st.cache_data(ttl=600, show_spinner=False)
def llamar_api(url, ruta):
    """GET a la API. Se guarda en caché 10 min para no relanzar Athena en cada clic."""
    r = requests.get(f"{url}{ruta}", timeout=35)
    datos = r.json()
    if r.status_code != 200:
        raise RuntimeError(datos.get("error", r.text))
    return datos


def respuesta_en_una_frase(pid, df):
    """La respuesta a la pregunta de negocio, en palabras."""
    if df.empty:
        return "Sin datos."
    if pid == "p1":
        f = df.iloc[0]
        return f"**{f.pais}** lidera con **US$ {f.ingreso_neto_usd:,.0f}**; le siguen {', '.join(df.pais.iloc[1:4])}."
    if pid == "p2":
        f = df.loc[df.ingreso_neto_usd.idxmax()]
        return (f"El mes pico fue **{f.periodo}** con **US$ {f.ingreso_neto_usd:,.0f}** "
                f"({int(f.facturas):,} facturas). La temporada navideña (sep–nov) concentra el crecimiento.")
    if pid == "p3":
        f = df.iloc[0]
        return f"El producto que más ingreso deja es **{f.descripcion}** (£ {f.ingreso_neto_gbp:,.0f}, {int(f.unidades_netas):,} unidades netas)."
    if pid == "p4":
        f = df.iloc[0]
        return (f"**{f.pais}** es donde más se gasta por habitante: **US$ {f.usd_por_mil_habitantes:,.2f} "
                f"por cada 1.000 habitantes**.")
    if pid == "p5":
        f = df.iloc[0]
        return (f"**{f.region_comercial}** tiene la mayor tasa de devolución: **{f.tasa_devolucion_pct:.2f} %** "
                f"del valor vendido.")
    if pid == "p6":
        f = df.loc[df.facturas.idxmax()]
        por_dia = df.groupby("dia").facturas.sum().sort_values(ascending=False)
        return (f"El pico es el **{f.dia} a las {int(f.hora)}:00** ({int(f.facturas)} facturas). "
                f"Día con más compras: **{por_dia.index[0]}**. No hay ventas los sábados.")
    return ""


def grafica(meta, df):
    g = meta["grafica"]
    if g["tipo"] == "barras":
        return alt.Chart(df).mark_bar().encode(
            x=alt.X(g["x"], sort="-y", title=None), y=alt.Y(g["y"], title=g["y"]), tooltip=list(df.columns))
    if g["tipo"] == "barras_h":
        return alt.Chart(df).mark_bar().encode(
            y=alt.Y(g["x"], sort="-x", title=None), x=alt.X(g["y"], title=g["y"]), tooltip=list(df.columns))
    if g["tipo"] == "linea":
        return alt.Chart(df).mark_line(point=True).encode(
            x=alt.X(g["x"], title="mes"), y=alt.Y(g["y"], title=g["y"]), tooltip=list(df.columns))
    if g["tipo"] == "calor":
        orden_dias = df.sort_values("dia_semana")["dia"].unique().tolist()
        return alt.Chart(df).mark_rect().encode(
            x=alt.X(f"{g['x']}:O", title="hora del día"), y=alt.Y(f"{g['y']}:N", sort=orden_dias, title=None),
            color=alt.Color(f"{g['valor']}:Q", title="facturas"), tooltip=list(df.columns))
    return None


# ------------------------------------------------------------------ interfaz
st.title("📊 Proyecto 2 · Analítica de ventas retail en AWS")
st.caption("Datos: ventas (archivos en EC2) + maestros (RDS MariaDB) + tasas de cambio y población (URLs públicas) "
           "→ Datalake S3 (raw → trusted → refined) → Athena → API Gateway → este tablero.")

with st.sidebar:
    st.header("Conexión")
    url = st.text_input("URL de la API (API Gateway)", API_URL, help="Sale del output api_url de Terraform")
    if not url:
        st.warning("Escriba la URL de la API para empezar.")
        st.stop()
    try:
        salud = llamar_api(url, "/salud")
        st.success(f"API en línea · base {salud['base_refined']}")
        preguntas = llamar_api(url, "/preguntas")
    except Exception as error:  # noqa: BLE001
        st.error(f"No se pudo llamar a la API: {error}")
        st.stop()
    st.header("Preguntas de negocio")
    opciones = {p["id"]: f"{p['id'].upper()} · {p['titulo']}" for p in preguntas}
    pid = st.radio("Elija una", list(opciones), format_func=opciones.get, label_visibility="collapsed")
    if st.button("🔄 Volver a consultar Athena"):
        llamar_api.clear()

try:
    with st.spinner("Consultando Athena a través de la API…"):
        datos = llamar_api(url, f"/preguntas/{pid}")
except Exception as error:  # noqa: BLE001
    st.error(f"La API respondió con error: {error}")
    st.stop()

df = pd.DataFrame(datos["filas"], columns=datos["columnas"])
st.subheader(f"{pid.upper()}. {datos['pregunta']}")
st.markdown("Fuentes cruzadas: " + " · ".join(f"`{f}`" for f in datos["fuentes"]))
st.info(respuesta_en_una_frase(pid, df))

col_grafica, col_tabla = st.columns([3, 2])
with col_grafica:
    figura = grafica(datos, df)
    if figura is not None:
        st.altair_chart(figura.properties(height=420), width="stretch")
with col_tabla:
    st.dataframe(df, width="stretch", hide_index=True, height=420)

with st.expander("¿De dónde salió este resultado?"):
    st.markdown(f"- Tabla refined: `{datos['tabla']}`\n"
                f"- Id de ejecución en Athena: `{datos['athena_query_id']}` ({datos['tiempo_ms']} ms)")
    st.code(datos["consulta_sql"], language="sql")
