# Punto 1 · Caso de estudio y preguntas de negocio

> **Enunciado:** crear un caso de estudio que procese datos de bases de datos, archivos y URLs, y plantear al
> menos 5 preguntas o hipótesis de negocio que se contestarán con esos datos.

## La empresa

Una tienda online del Reino Unido que vende artículos de regalo (decoración, cocina, fiestas, navidad) a
clientes minoristas y mayoristas de **38 países**. Se usa el dataset público **Online Retail** (UCI Machine
Learning Repository): **541.909 líneas de factura** entre el **1-dic-2010 y el 9-dic-2011**, con precios en
**libras esterlinas (GBP)**. Las facturas que empiezan por `C` son devoluciones (cantidad negativa).

La gerencia quiere entender **dónde, qué y cuándo vende**, cuánto se devuelve, y comparar países de forma justa
(en dólares y teniendo en cuenta el tamaño de cada país). Para eso necesita juntar información que hoy está en
tres sistemas distintos.

## Las tres fuentes (punto 2)

| Fuente | Sistema simulado | Contenido | Formato que llega a raw |
|---|---|---|---|
| **RDS MariaDB** `retaildb` | ERP con datos maestros | `customers` (4.372), `products` (3.958), `countries` (38, con ISO-3 y región comercial) | CSV (una foto diaria por tabla) |
| **EC2** `/srv/ventas` | servidor del sistema de caja | 13 archivos `ventas_AAAA_MM.csv`: factura, código de producto, cantidad, fecha, precio, cliente | CSV (un archivo por mes) |
| **URL** | APIs públicas | Frankfurter: tasa GBP→USD y GBP→EUR por día · Banco Mundial: población 2011 y PIB per cápita 2011 por país | JSON tal cual lo devuelve la API |

Las ventas **no traen país ni descripción** (como un exporte real de caja): para cualquier pregunta por país o
producto hay que cruzar EC2 con RDS, y para hablar en dólares o por habitante hay que cruzar con las URLs.

## Preguntas de negocio e hipótesis

| # | Pregunta | Hipótesis inicial | Cómo se mide | Fuentes |
|---|---|---|---|---|
| **P1** | ¿Cuáles son los 10 países con mayor **ingreso neto en dólares**? | El Reino Unido domina, pero hay mercados europeos (Países Bajos, Irlanda, Alemania, Francia) relevantes. | Σ(cantidad × precio × tasa GBP→USD del día), ventas menos devoluciones | EC2 + RDS (clientes) + URL (tasas) |
| **P2** | ¿Cómo evolucionó el **ingreso mes a mes** y cuál fue el **mes pico**? | Hay estacionalidad navideña: el pico está entre septiembre y noviembre. | Ingreso neto GBP y USD por mes, número de facturas y ticket promedio | EC2 + URL (tasas) |
| **P3** | ¿Cuáles son los 10 **productos** que más ingreso neto generan? | Los artículos decorativos baratos de alta rotación lideran en ingreso. | Ingreso neto y unidades netas por código de producto | EC2 + RDS (productos) + URL (tasas) |
| **P4** | ¿En qué países se **gasta más por cada 1.000 habitantes**? | Al normalizar por población, países pequeños y cercanos superan a mercados grandes. | Ingreso USD ÷ población 2011 × 1.000 (con el PIB per cápita como contexto) | EC2 + RDS (clientes, países) + URL (Banco Mundial, tasas) |
| **P5** | ¿Qué **región comercial** **devuelve** más, en % del valor vendido? | El mercado local (Reino Unido e Irlanda) devuelve más por su volumen y cercanía. | Valor devuelto ÷ valor vendido × 100 por región comercial | EC2 + RDS (clientes, países) |
| **P6** | ¿Qué **días y horas** concentran las compras? | Las compras se concentran al mediodía de días hábiles (clientes mayoristas en horario de oficina). | Facturas e ingreso bruto por día de la semana × hora | EC2 |

Las respuestas con datos reales quedan en `refined/` (punto 7), se ven en el tablero (punto 8) y las
conclusiones se registran en el informe.

## Diccionario de datos de la zona trusted (resultado del punto 4)

| Tabla | Columna | Tipo | Descripción |
|---|---|---|---|
| `ventas` | `factura` | string | Número de factura; `C…` = devolución |
| | `codigo_producto` | string | Código de inventario en mayúsculas |
| | `cantidad` | int | Unidades (negativas en devoluciones) |
| | `precio_unitario_gbp` | double | Precio por unidad en libras |
| | `importe_gbp` | double | `cantidad × precio_unitario_gbp` |
| | `id_cliente` | int | Cliente (llave hacia `clientes`) |
| | `fecha_hora`, `fecha`, `hora`, `dia_semana` | timestamp, date, int, int | Momento de la venta; `dia_semana` 1 = lunes … 7 = domingo |
| | `es_devolucion` | boolean | `true` si la factura empieza por `C` |
| | `anio`, `mes` | int | Particiones de la tabla |
| `clientes` | `id_cliente`, `pais` | int, string | País de cada cliente (RDS) |
| `productos` | `codigo_producto`, `descripcion` | string | Descripción más usada de cada código (RDS) |
| `paises` | `pais`, `iso3`, `region_comercial`, `poblacion`, `pib_per_capita_usd` | string, string, string, bigint, double | Maestro de países (RDS) + Banco Mundial (URL) |
| `tasas_cambio` | `fecha`, `gbp_usd`, `gbp_eur`, `es_tasa_publicada` | date, double, double, boolean | Una fila por día; fines de semana con la última tasa publicada (URL) |

## Evidencias de este punto

Este punto es de diseño: la evidencia es este documento y las tablas de preguntas. Las capturas empiezan en el
punto 2.
