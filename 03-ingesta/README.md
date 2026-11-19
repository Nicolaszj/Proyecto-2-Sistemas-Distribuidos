# Punto 3 · Ingesta automática hacia el datalake (S3, zona raw)

> **Enunciado:** ingesta de datos hacia el datalake (AWS S3) en las zonas correctas. Deberá ser un proceso automático.

## Qué hicimos

Cada fuente tiene su propio mecanismo de ingesta, y todo queda en la **zona raw** sin transformar:

| Fuente | Mecanismo | Cuándo corre | Destino en S3 |
|---|---|---|---|
| RDS MariaDB | **Glue job** `retail-p2-ingesta-rds` (Python shell) que ordena a la EC2 fuente, por **SSM Run Command**, extraer las tablas con `extraer_rds_s3.py` | Workflow de Glue: diario 6:00 a.m. (Colombia) o a mano | `raw/rds/<tabla>/fecha_ingesta=AAAA-MM-DD/<tabla>.csv` |
| Archivos EC2 | **cron** en la EC2 con `aws s3 sync` | cada 10 minutos | `raw/ec2/ventas/ventas_AAAA_MM.csv` |
| URLs | **Glue job** `retail-p2-ingesta-url` (Python shell) | Workflow de Glue, en paralelo con la del RDS | `raw/url/<fuente>/fecha_ingesta=AAAA-MM-DD/<fuente>.json` |

**Orquestación** (`infra/glue_workflow.tf`): el **Glue Workflow** `retail-p2-pipeline` encadena todo el proceso
con *triggers*; cuando termina la ingesta, sigue solo con la preparación (punto 4), la analítica (punto 7) y los
crawlers (punto 5):

```
t1 (programado, diario) ─► ingesta-rds ─┐
                        └► ingesta-url ─┴─(las dos OK)─► t2: raw-a-trusted + crawler raw
t3 (raw-a-trusted OK) ─► crawler trusted + trusted-a-refined
t4 (trusted-a-refined OK) ─► crawler refined
```

### Decisiones de diseño

- **Raw es inmutable y conserva el formato original** (CSV y JSON). Si mañana cambia una regla de limpieza, se
  reprocesa desde raw sin volver a las fuentes.
- **Fotos por fecha de ingesta** (`fecha_ingesta=AAAA-MM-DD`) para las fuentes que se leen completas (RDS y URL):
  se guarda la historia y la preparación toma la más reciente. Correr dos veces el mismo día sobrescribe esa foto
  (proceso idempotente).
- **La EC2 empuja sus archivos** (S3 no puede "entrar" a leer una EC2). `aws s3 sync` solo sube lo nuevo o
  modificado: si el sistema de caja deja un archivo nuevo, en ≤ 10 min está en raw.
- **Credenciales fuera del código:** la clave del RDS solo existe dentro de la EC2 fuente (`/opt/fuente/.my.cnf`,
  permisos 600). Glue y la EC2 escriben en S3 con el rol `LabRole`, sin llaves.
- **Por qué Glue no lee el RDS por JDBC:** lo probamos en el Learner Lab y no funciona. El job de Glue crea sus
  interfaces de red en la VPC, pero quedan en estado `available`, nunca se conectan, y el driver responde
  *Communications link failure*. Como el RDS es privado, la solución es que el job de Glue le **ordene** la
  extracción a la EC2 fuente, que sí está en la VPC, con **SSM Run Command**. El workflow sigue controlando todo:
  si la EC2 falla, el job falla y no se procesa nada.

```
Glue job ingesta-rds ──SSM Run Command──► EC2 fuente ──mysql──► RDS MariaDB (privado)
                                              └──aws s3 cp──► s3://<bucket>/raw/rds/<tabla>/fecha_ingesta=…/
```

## Archivos

| Archivo | Qué hace | Lo crea / ejecuta |
|---|---|---|
| `glue/ingesta_rds.py` | Job Python shell: envía por SSM a la EC2 los comandos para bajar y ejecutar `extraer_rds_s3.py`, espera y falla si la EC2 falla | `infra/glue_jobs.tf` → job `ingesta-rds` |
| `ec2/extraer_rds_s3.py` | En la EC2: `SELECT *` de `customers`, `products`, `countries`, lo convierte a CSV con encabezado y lo sube a raw | lo ejecuta el job `ingesta-rds` vía SSM |
| `glue/ingesta_url.py` | Descarga los 3 JSON con reintentos, valida que sean JSON y los guarda en raw | `infra/glue_jobs.tf` → job `ingesta-url` |
| `ec2/sincronizar_ventas_s3.sh` | `aws s3 sync /srv/ventas → raw/ec2/ventas/` | cron de la EC2 (`/etc/cron.d/sincronizar-ventas`) |
| `../scripts/ejecutar_pipeline.sh` | Lanza el workflow a mano y muestra el avance | CloudShell |

## Cómo verificarlo

```bash
cd ~/Proyecto-2-Sistemas-Distribuidos
scripts/ejecutar_pipeline.sh                       # termina con "PIPELINE OK"
BUCKET=$(cd infra && terraform output -raw bucket_datalake)
aws s3 ls s3://$BUCKET/raw/ --recursive | grep -v '\$folder' | head -40
```

Dentro de la EC2 fuente (Session Manager):

```bash
cat /etc/cron.d/sincronizar-ventas
sudo tail -4 /var/log/sincronizar-ventas.log
# Demo de ingesta automática: llega un archivo nuevo y en ≤ 10 min está en S3
sudo cp /srv/ventas/ventas_2011_12.csv /srv/ventas/ventas_2011_12_demo.csv
sudo /opt/fuente/sincronizar_ventas_s3.sh          # o esperar al cron
```

> Después de la demo, borrar el archivo de prueba de la EC2 y de S3 para no duplicar ventas
> (`sudo rm /srv/ventas/ventas_2011_12_demo.csv` y `aws s3 rm s3://$BUCKET/raw/ec2/ventas/ventas_2011_12_demo.csv`).

## Evidencias

| Id | Captura |
|---|---|
| E06 | EC2 fuente: `cat /etc/cron.d/sincronizar-ventas` y el final de `/var/log/sincronizar-ventas.log` |
| E07 | Consola S3: carpetas `raw/rds/`, `raw/ec2/ventas/` y `raw/url/` con sus archivos |
| E08 | Glue → Workflows → `retail-p2-pipeline` → *History* → *View run details*: el grafo completo en verde |
| E09 | Glue → ETL jobs: `retail-p2-ingesta-rds` y `retail-p2-ingesta-url` en *Succeeded* |
