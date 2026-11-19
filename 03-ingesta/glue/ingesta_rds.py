"""
PUNTO 3 - Ingesta automática: RDS MariaDB  ->  S3 zona raw.

Job de AWS Glue tipo "Python shell". Lo crea Terraform (infra/glue_jobs.tf) y es
el primer paso del workflow de Glue (infra/glue_workflow.tf), en paralelo con la
ingesta de URLs. Corre todos los días a la hora programada o a mano.

Cómo llega al RDS, que es privado:
  En AWS Academy un job de Glue no puede entrar a la VPC (las interfaces de red
  que crea nunca se conectan), así que no alcanza la base por JDBC. Por eso este
  job le ORDENA la extracción a la EC2 fuente, que sí está en la VPC, usando
  AWS Systems Manager Run Command:

     Glue (este job) --SSM Run Command--> EC2 fuente --mysql--> RDS MariaDB
                                              └--aws s3 cp--> s3://<bucket>/raw/rds/

  1. Envía a la EC2 dos comandos: bajar de S3 la última versión de
     03-ingesta/ec2/extraer_rds_s3.py y ejecutarla.
  2. Espera a que terminen e imprime lo que respondió la EC2.
  3. Si la EC2 falla, el job falla y el workflow se detiene (no se procesan
     datos incompletos).

Qué queda en S3 (una "foto" completa de cada tabla por día de ingesta):
  s3://<bucket>/raw/rds/<tabla>/fecha_ingesta=AAAA-MM-DD/<tabla>.csv

Argumentos (los pone Terraform en default_arguments):
  --DATALAKE          s3://<bucket>
  --INSTANCIA_FUENTE  id de la EC2 fuente (i-...)
  --REGION            us-east-1
"""
import sys
import time

import boto3


def leer_argumentos(argv):
    """['--CLAVE', 'valor', ...] -> {'CLAVE': 'valor'} (igual que Glue)."""
    args = {}
    for i, token in enumerate(argv):
        if token.startswith("--") and i + 1 < len(argv) and not argv[i + 1].startswith("--"):
            args[token[2:]] = argv[i + 1]
    return args


def main():
    args = leer_argumentos(sys.argv)
    bucket = args["DATALAKE"].replace("s3://", "").rstrip("/")
    instancia = args["INSTANCIA_FUENTE"]
    ssm = boto3.client("ssm", region_name=args.get("REGION", "us-east-1"))

    comandos = [
        f"aws s3 cp s3://{bucket}/scripts/03-ingesta/ec2/extraer_rds_s3.py /opt/fuente/extraer_rds_s3.py --only-show-errors",
        f"python3 /opt/fuente/extraer_rds_s3.py {bucket}",
    ]
    envio = ssm.send_command(
        InstanceIds=[instancia],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": comandos, "executionTimeout": ["600"]},
        Comment="Proyecto 2 - ingesta RDS a S3 raw",
    )
    comando_id = envio["Command"]["CommandId"]
    print(f"[ingesta_rds] SSM Run Command {comando_id} enviado a {instancia}")

    for _ in range(120):  # hasta ~10 minutos
        time.sleep(5)
        try:
            resultado = ssm.get_command_invocation(CommandId=comando_id, InstanceId=instancia)
        except ssm.exceptions.InvocationDoesNotExist:
            continue  # SSM aún no registra la invocación
        if resultado["Status"] in ("Pending", "InProgress", "Delayed"):
            continue
        print(resultado.get("StandardOutputContent", ""))
        if resultado["Status"] != "Success":
            print(resultado.get("StandardErrorContent", ""))
            raise RuntimeError(f"La EC2 no pudo extraer el RDS: estado {resultado['Status']}")
        print("[ingesta_rds] OK")
        return
    raise TimeoutError("La extracción del RDS tardó más de 10 minutos")


if __name__ == "__main__":
    main()
