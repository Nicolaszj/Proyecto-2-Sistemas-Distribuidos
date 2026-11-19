# PUNTOS 5, 6 y 7 - Clúster Amazon EMR (Hadoop, Hive, Spark, Hue, JupyterHub).
#
# Solo existe si crear_emr = true (cobra por hora). Configuración clave:
#   hive-site / spark-hive-site -> Hive y Spark usan el AWS Glue Data Catalog
#     como metastore: ven las tablas de los crawlers y lo que creen en Hive
#     aparece en Glue y en Athena.
#   jupyter-s3-conf -> los notebooks de JupyterHub se guardan en el bucket.
#   auto_termination_policy -> se apaga solo tras var.emr_apagado_inactivo_segundos sin trabajo.
#
# Los trabajos se envían como "steps" con scripts/emr_ejecutar_pasos.sh.

locals {
  glue_como_metastore = {
    "hive.metastore.client.factory.class" = "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
  }
}

resource "aws_emr_cluster" "spark" {
  count         = var.crear_emr ? 1 : 0
  name          = "${var.proyecto}-emr"
  release_label = var.emr_version
  applications  = ["Hadoop", "Hive", "Spark", "Hue", "JupyterHub", "Livy"]

  service_role = local.emr_rol_servicio
  log_uri      = "${local.datalake}/emr-logs/"

  termination_protection            = false
  keep_job_flow_alive_when_no_steps = true

  auto_termination_policy {
    idle_timeout = var.emr_apagado_inactivo_segundos
  }

  ec2_attributes {
    subnet_id                         = data.aws_subnet.zona_a.id
    instance_profile                  = local.emr_perfil_nodos
    key_name                          = var.key_name
    additional_master_security_groups = aws_security_group.emr_admin.id
  }

  master_instance_group {
    instance_type = var.emr_tipo_instancia
    ebs_config {
      size                 = 32
      type                 = "gp3"
      volumes_per_instance = 1
    }
  }

  core_instance_group {
    instance_type  = var.emr_tipo_instancia
    instance_count = var.emr_nodos_core
    ebs_config {
      size                 = 32
      type                 = "gp3"
      volumes_per_instance = 1
    }
  }

  configurations_json = jsonencode([
    { Classification = "hive-site", Properties = local.glue_como_metastore },
    { Classification = "spark-hive-site", Properties = local.glue_como_metastore },
    {
      Classification = "jupyter-s3-conf"
      Properties = {
        "s3.persistence.enabled" = "true"
        "s3.persistence.bucket"  = local.bucket
      }
    },
  ])

  tags = { Name = "${var.proyecto}-emr" }

  # Si el clúster se apagó solo por inactividad, Terraform lo verá terminado;
  # basta con volver a correr "terraform apply" para crear uno nuevo.
}
