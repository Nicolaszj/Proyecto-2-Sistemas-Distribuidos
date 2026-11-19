# Punto 2 · Fuentes de datos: RDS MariaDB, archivos en EC2 y URLs

> **Enunciado:** simular datos en RDS MariaDB, archivos en una instancia EC2 y URLs en Internet.

## Qué hicimos

Partimos de un solo archivo (el dataset *Online Retail*) y lo **repartimos** como estaría en una empresa:

```
datos/online-retail-dataset.csv.zip
            │  preparar_fuentes.py  (corre solo, dentro de la EC2 fuente, al arrancar)
   ┌────────┴─────────────────────────────┐
   ▼                                      ▼
/srv/ventas/ventas_AAAA_MM.csv      seed_mariadb.sql = esquema_mariadb.sql + INSERTs
(13 archivos, fuente EC2)                  │  mysql < seed_mariadb.sql
                                           ▼
                                  RDS MariaDB retaildb: countries, customers, products
```

- **RDS MariaDB** (`infra/fuente_rds.tf`): `db.t3.micro`, MariaDB 10.11, **privada** (no tiene IP pública; solo
  entra la EC2 fuente, que es la que hace la extracción hacia S3). Base `retaildb` con 3 tablas en inglés, como vendrían de un ERP.
- **EC2 fuente de archivos** (`infra/fuente_ec2.tf`): Amazon Linux 2023. Su `user_data`
  (`infra/plantillas/fuente_ec2_user_data.sh.tftpl`) baja el dataset y los scripts del bucket, corre
  `preparar_fuentes.py`, carga el RDS y deja los 13 CSV en `/srv/ventas`. Sin puertos abiertos: se entra con
  **Session Manager**.
- **URLs** (no hay que crear nada, son APIs públicas sin llave):
  - `https://api.frankfurter.dev/v1/2010-12-01..2011-12-31?from=GBP&to=USD,EUR`
  - `https://api.worldbank.org/v2/country/all/indicator/SP.POP.TOTL?date=2011&format=json&per_page=500`
  - `https://api.worldbank.org/v2/country/all/indicator/NY.GDP.PCAP.CD?date=2011&format=json&per_page=500`

## Archivos

| Archivo | Qué hace | Quién lo usa |
|---|---|---|
| `datos/online-retail-dataset.csv.zip` | Dataset original (7,6 MB comprimido) | Terraform lo sube a `s3://<bucket>/seed/` |
| `preparar_fuentes.py` | Reparte el dataset: CSV mensuales (sin país ni descripción) + SQL de los maestros. Solo librería estándar de Python | `user_data` de la EC2 fuente |
| `sql/esquema_mariadb.sql` | Crea `retaildb` y las tablas `countries`, `customers` (FK a countries) y `products` en UTF-8 | `preparar_fuentes.py` lo pone al inicio del SQL |

`preparar_fuentes.py` también define el **maestro de países** (`PAISES`): código ISO-3 de cada país (para cruzar con
el Banco Mundial) y la **región comercial** que le asigna la empresa (dato simulado, propio del negocio).

## Cómo verificarlo

En la consola: **EC2 → Instances → `retail-p2-fuente-archivos` → Connect → Session Manager → Connect**, y:

```bash
sudo tail -5 /var/log/fuente-setup.log           # debe terminar en FUENTE LISTA
ls -lh /srv/ventas                                # 13 archivos ventas_2010_12.csv … ventas_2011_12.csv
head -3 /srv/ventas/ventas_2011_01.csv            # InvoiceNo,StockCode,Quantity,InvoiceDate,UnitPrice,CustomerID
sudo mysql --defaults-extra-file=/opt/fuente/.my.cnf retaildb -e "
  SELECT 'customers' tabla, COUNT(*) filas FROM customers UNION ALL
  SELECT 'products', COUNT(*) FROM products UNION ALL SELECT 'countries', COUNT(*) FROM countries;
  SELECT * FROM countries LIMIT 5;"
```

Resultado esperado: `customers 4372`, `products 3958`, `countries 38`.

Para probarlo sin AWS: `python3 preparar_fuentes.py` (deja todo en `salida/`, que está en `.gitignore`).

## Evidencias

| Id | Captura |
|---|---|
| E01 | CloudShell: final de `terraform apply` con los *outputs* |
| E02 | Consola RDS: `retail-p2-mariadb` en estado *Available*, *Publicly accessible = No* |
| E03 | Session Manager en la EC2 fuente: `FUENTE LISTA` en el log y `ls -lh /srv/ventas` con los 13 archivos |
| E04 | Session Manager: conteos de las 3 tablas de MariaDB y `SELECT * FROM countries LIMIT 5` |
| E05 | Navegador con una de las URLs (Frankfurter o Banco Mundial) mostrando el JSON |
