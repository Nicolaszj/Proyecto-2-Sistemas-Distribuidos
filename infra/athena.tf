# PUNTO 6 - Consultas SQL con Amazon Athena.
#
# Workgroup propio: obliga a guardar los resultados en
# s3://<bucket>/athena-results/ (así no hay que configurar nada la primera vez).
# Las 6 consultas de 06-consultas-sql/sql/ quedan como "Saved queries" listas
# para ejecutar en la consola, con ${db} reemplazado por retail_trusted.

resource "aws_athena_workgroup" "retail" {
  name          = "${var.proyecto}-wg"
  description   = "Consultas del Proyecto 2 (Athena + API)"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "${local.datalake}/athena-results/"
    }
  }
}

resource "aws_athena_named_query" "preguntas" {
  for_each  = toset(local.preguntas)
  name      = each.value
  workgroup = aws_athena_workgroup.retail.id
  database  = aws_glue_catalog_database.trusted.name
  description = trimprefix(
    trimspace(split("\n", file("${local.raiz}/06-consultas-sql/sql/${each.value}.sql"))[0]), "-- "
  )
  query = trimsuffix(trimspace(replace(
    file("${local.raiz}/06-consultas-sql/sql/${each.value}.sql"), "$${db}", local.db_trusted
  )), ";")
}
