# Lo que Terraform imprime al final de "apply" (y con "terraform output").
# Los scripts de scripts/ leen estos valores, así nadie copia IDs a mano.

output "bucket_datalake" {
  description = "Bucket S3 del datalake"
  value       = aws_s3_bucket.datalake.bucket
}

output "rds_endpoint" {
  description = "Host del RDS MariaDB (privado: solo Glue y la EC2 fuente)"
  value       = aws_db_instance.mariadb.address
}

output "rds_clave" {
  description = "Clave del usuario admin del RDS (ver con: terraform output -raw rds_clave)"
  value       = random_password.db.result
  sensitive   = true
}

output "ec2_fuente_id" {
  description = "EC2 fuente de archivos (entrar con: aws ssm start-session --target <id>)"
  value       = aws_instance.fuente.id
}

output "glue_workflow" {
  description = "Workflow que orquesta ingesta -> raw -> trusted -> refined"
  value       = aws_glue_workflow.pipeline.name
}

output "athena_workgroup" {
  description = "Workgroup de Athena (elegirlo en la consola para ver las Saved queries)"
  value       = aws_athena_workgroup.retail.name
}

output "api_url" {
  description = "URL base de la API en API Gateway"
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "streamlit_url" {
  description = "Tablero Streamlit (tarda ~3 min en instalarse tras crear la EC2)"
  value       = "http://${aws_instance.streamlit.public_dns}:8501"
}

output "emr_cluster_id" {
  description = "Id del clúster EMR (vacío si crear_emr = false)"
  value       = try(aws_emr_cluster.spark[0].id, "")
}

output "emr_hue_url" {
  description = "Hue en el nodo master del EMR"
  value       = try("http://${aws_emr_cluster.spark[0].master_public_dns}:8888", "")
}

output "emr_jupyterhub_url" {
  description = "JupyterHub en el nodo master del EMR (usuario jovyan / clave jupyter)"
  value       = try("https://${aws_emr_cluster.spark[0].master_public_dns}:9443", "")
}
