# PUNTO 3 (ingesta automática) - Orquestación con un Workflow de AWS Glue.
#
#   [inicio: todos los días a la hora de var.horario_pipeline, o a mano]
#        ├─► job ingesta-rds ─┐
#        └─► job ingesta-url ─┴─(ambos OK)─► job raw-a-trusted + crawler raw
#                                                  │ (OK)
#                                                  ├─► crawler trusted
#                                                  └─► job trusted-a-refined
#                                                          │ (OK)
#                                                          └─► crawler refined
#
# La EC2 sube sus archivos por su cuenta (cron cada 10 min), así que cuando el
# workflow corre, raw/ec2/ventas/ ya tiene los archivos más recientes.
# Para lanzarlo a mano:  aws glue start-workflow-run --name <proyecto>-pipeline

resource "aws_glue_workflow" "pipeline" {
  name        = "${var.proyecto}-pipeline"
  description = "Ingesta -> raw -> trusted -> refined, con catalogación en cada zona"
}

resource "aws_glue_trigger" "inicio" {
  name          = "${var.proyecto}-t1-inicio-diario"
  workflow_name = aws_glue_workflow.pipeline.name
  type          = "SCHEDULED"
  schedule      = var.horario_pipeline

  actions { job_name = aws_glue_job.ingesta_rds.name }
  actions { job_name = aws_glue_job.ingesta_url.name }
}

resource "aws_glue_trigger" "tras_ingesta" {
  name          = "${var.proyecto}-t2-tras-ingesta"
  workflow_name = aws_glue_workflow.pipeline.name
  type          = "CONDITIONAL"

  predicate {
    logical = "AND"
    conditions {
      job_name = aws_glue_job.ingesta_rds.name
      state    = "SUCCEEDED"
    }
    conditions {
      job_name = aws_glue_job.ingesta_url.name
      state    = "SUCCEEDED"
    }
  }

  actions { job_name = aws_glue_job.raw_a_trusted.name }
  actions { crawler_name = aws_glue_crawler.raw.name }
}

resource "aws_glue_trigger" "tras_trusted" {
  name          = "${var.proyecto}-t3-tras-trusted"
  workflow_name = aws_glue_workflow.pipeline.name
  type          = "CONDITIONAL"

  predicate {
    conditions {
      job_name = aws_glue_job.raw_a_trusted.name
      state    = "SUCCEEDED"
    }
  }

  actions { crawler_name = aws_glue_crawler.trusted.name }
  actions { job_name = aws_glue_job.trusted_a_refined.name }
}

resource "aws_glue_trigger" "tras_refined" {
  name          = "${var.proyecto}-t4-tras-refined"
  workflow_name = aws_glue_workflow.pipeline.name
  type          = "CONDITIONAL"

  predicate {
    conditions {
      job_name = aws_glue_job.trusted_a_refined.name
      state    = "SUCCEEDED"
    }
  }

  actions { crawler_name = aws_glue_crawler.refined.name }
}
