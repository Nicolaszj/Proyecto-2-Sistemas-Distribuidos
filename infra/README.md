# infra/ · Toda la infraestructura con Terraform

Un solo `terraform apply` crea **todo** el proyecto en la cuenta de AWS Academy y sube el código del repo al
bucket. Un `terraform destroy` lo borra. Los archivos están separados por tema y cada uno dice en su encabezado a
qué punto del enunciado pertenece.

## Qué crea (≈ 60 recursos)

| Archivo | Recursos | Punto |
|---|---|---|
| `versions.tf` | Versión de Terraform, providers `aws`, `random`, `archive`, etiquetas comunes | — |
| `variables.tf` / `terraform.tfvars.example` | Parámetros: región, prefijo, IP del equipo, `crear_emr`, tamaños, horario | — |
| `locals.tf` | Nombres calculados: bucket, roles de AWS Academy, bases del catálogo, lista de preguntas | — |
| `datos_cuenta.tf` | *Lee* (no crea): cuenta, VPC por defecto, subredes a/b, tabla de rutas, AMI Amazon Linux 2023 | — |
| `red.tf` | 4 security groups (fuente, rds, app, emr_admin) | 2, 8 |
| `s3_datalake.tf` | Bucket (creado con la AWS CLI desde un `terraform_data`, ver restricciones), carpetas raw/trusted/refined, subida del código (`scripts/…`) y del dataset (`seed/…`) | 3, 4, 7 |
| `fuente_rds.tf` | Clave aleatoria, grupo de subredes, RDS MariaDB privado | 2 |
| `fuente_ec2.tf` | EC2 fuente de archivos con su `user_data` | 2, 3 |
| `glue_catalogo.tf` | Bases `retail_raw/trusted/refined`, clasificador CSV, 3 crawlers | 5 |
| `glue_jobs.tf` | 4 jobs (ingesta-rds vía SSM, ingesta-url, raw-a-trusted, trusted-a-refined) | 3, 4, 7 |
| `glue_workflow.tf` | Workflow + 4 triggers (programado y condicionales) | 3 |
| `athena.tf` | Workgroup con carpeta de resultados + 6 *saved queries* | 6 |
| `emr.tf` | Clúster EMR 7.10 (Hadoop, Hive, Spark, Hue, JupyterHub, Livy) con Glue como metastore | 5, 6, 7 |
| `api.tf` | Lambda + API Gateway HTTP (integración, 3 rutas, stage, permiso) | 8 |
| `app_streamlit.tf` | EC2 con el tablero Streamlit | 8 |
| `outputs.tf` | Lo que imprime al final: bucket, URLs de API, Streamlit, Hue, JupyterHub, ids | — |
| `plantillas/*.tftpl` | Scripts de arranque (`user_data`) de las dos EC2; Terraform les inyecta bucket, host y clave | 2, 3, 8 |

## Conceptos de Terraform que usamos (para explicarlo)

| Concepto | Dónde se ve | Qué hace |
|---|---|---|
| `provider` | `versions.tf` | Plugin que habla con la API de AWS. Las credenciales salen de CloudShell, no del código |
| `resource` | todos | Algo que Terraform **crea** y administra (bucket, RDS, job…) |
| `data` | `datos_cuenta.tf` | Algo que Terraform **lee** y no administra (VPC por defecto, AMI) |
| `variable` / `tfvars` | `variables.tf` | Parámetros; `validation` revisa que la IP sea un CIDR |
| `locals` | `locals.tf` | Valores calculados una vez y reusados (nombre del bucket, ARN de LabRole) |
| `output` | `outputs.tf` | Valores que se imprimen y que leen los scripts (`terraform output -raw api_url`) |
| Referencias | `aws_db_instance.mariadb.address` en `glue_jobs.tf` | Conectan recursos y definen el **orden**: primero el RDS, luego la conexión |
| `depends_on` | `fuente_ec2.tf` | Orden explícito: la EC2 arranca cuando el código ya está en S3 |
| `for_each` | `aws_s3_object.codigo`, `aws_athena_named_query.preguntas`, rutas de la API | Un recurso por elemento de una lista |
| `dynamic` | crawlers, reglas del SG emr_admin | Bloques repetidos generados desde una lista |
| `count` | `emr.tf` | `count = var.crear_emr ? 1 : 0`: el EMR existe solo cuando se pide |
| `templatefile()` | `fuente_ec2.tf`, `app_streamlit.tf` | Rellena las plantillas `user_data` con valores reales |
| `fileset()` + `filemd5()` | `s3_datalake.tf` | Sube todos los scripts del repo y los vuelve a subir si cambian |
| `archive_file` | `api.tf` | Empaqueta la Lambda en un `.zip` |
| `random_password` + `sensitive` | `fuente_rds.tf`, `outputs.tf` | Clave del RDS generada y oculta en la salida |

## Orden en que AWS va quedando listo (lo calcula Terraform con las referencias)

```
S3 bucket ─► subir código y dataset ─┬─► Glue jobs, crawlers, workflow, Athena
security groups ─► RDS (≈ 5 min) ────┤
                                     └─► EC2 fuente (carga el RDS y sube los CSV ≈ 4 min)
Athena + catálogo refined ─► Lambda ─► API Gateway ─► EC2 Streamlit (≈ 3 min instalando)
crear_emr = true ─► EMR (≈ 12-15 min)
```

## Restricciones de AWS Academy y cómo las resolvimos

- **No se pueden crear roles IAM** → se usan los existentes: `LabRole` (Glue, Lambda, crawlers),
  `LabInstanceProfile` (EC2), `EMR_DefaultRole` y `EMR_EC2_DefaultRole` (EMR). Sus ARN se arman con el número de
  cuenta en `locals.tf`, sin llamar a IAM.
- **Las credenciales caducan** cada sesión → nunca se guardan en el código; Terraform usa las de CloudShell.
- **CloudShell tiene 1 GB en $HOME** → `scripts/preparar_cloudshell.sh` pone los plugins en `/tmp`
  (`TF_DATA_DIR`) y deja el estado `terraform.tfstate` en `infra/` (persistente).
- **El crédito es limitado** → EMR solo con `crear_emr = true` y con apagado automático por inactividad.

- **El recurso `aws_s3_bucket` falla** porque una política de la organización (SCP) prohíbe lecturas que el
  provider hace siempre (por ejemplo `s3:GetBucketObjectLockConfiguration`). El bucket se crea con la AWS CLI desde
  un `terraform_data` que también lo borra en el `destroy`. Los buckets nuevos ya son privados y cifrados.
- **Glue no puede entrar a la VPC** (sus interfaces de red nunca se conectan), así que no lee el RDS privado por
  JDBC: el job `ingesta-rds` le ordena la extracción a la EC2 fuente con SSM Run Command.
- **Máximo 9 instancias EC2 encendidas** en la cuenta (las sobrantes se apagan solas). El proyecto usa 2 EC2 + 3 del
  EMR = 5: antes de desplegar, apagar o borrar las de otros laboratorios.
- **Las etiquetas no aceptan comas** en el valor (por eso `Equipo` usa guiones).

## Comandos

```bash
source ../scripts/preparar_cloudshell.sh      # una vez por sesión de CloudShell
cp terraform.tfvars.example terraform.tfvars  # y poner ip_administrador
terraform init
terraform plan                                # revisar: "Plan: N to add, 0 to change, 0 to destroy"
terraform apply
terraform output                              # ver URLs e ids
terraform apply -var crear_emr=true           # agrega el EMR
terraform apply -var crear_emr=false          # quita solo el EMR
../scripts/limpiar.sh                         # borra todo
```

> **Si se cierra la sesión del Learner Lab**, al volver: abrir CloudShell, `cd` al repo, `source
> scripts/preparar_cloudshell.sh`, `cd infra && terraform init` (los plugins de `/tmp` se borran) y seguir.
> El estado no se pierde. Las EC2 y el RDS que AWS Academy detuvo vuelven a encenderse al iniciar el lab.
