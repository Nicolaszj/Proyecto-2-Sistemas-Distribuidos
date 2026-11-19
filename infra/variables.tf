# Parámetros del despliegue. Los valores se ponen en terraform.tfvars
# (copiar terraform.tfvars.example). Solo ip_administrador es obligatorio.

variable "region" {
  description = "Región de AWS (AWS Academy trabaja en us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "proyecto" {
  description = "Prefijo de todos los nombres (bucket, jobs, instancias...)"
  type        = string
  default     = "retail-p2"
}

variable "ip_administrador" {
  description = "IP pública del PC desde donde se abre Hue/JupyterHub/SSH del EMR, en formato CIDR (ej. 181.50.10.20/32)"
  type        = string

  validation {
    condition     = can(cidrhost(var.ip_administrador, 0))
    error_message = "Debe ser un CIDR, por ejemplo 181.50.10.20/32."
  }
}

variable "crear_emr" {
  description = "true = crea el clúster EMR (cobra por hora: crearlo solo para la demo de Hive/Spark y luego volver a false)"
  type        = bool
  default     = false
}

variable "emr_version" {
  description = "Versión de Amazon EMR (la del laboratorio del curso)"
  type        = string
  default     = "emr-7.10.0"
}

variable "emr_tipo_instancia" {
  description = "Tipo de EC2 para los nodos del EMR (si AWS Academy no tiene capacidad, probar m4.xlarge)"
  type        = string
  default     = "m5.xlarge"
}

variable "emr_nodos_core" {
  description = "Cantidad de nodos core (workers) del EMR"
  type        = number
  default     = 2
}

variable "emr_apagado_inactivo_segundos" {
  description = "El EMR se apaga solo si pasa este tiempo sin trabajo (protege el crédito del lab)"
  type        = number
  default     = 7200
}

variable "db_clase" {
  description = "Tamaño de la instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_version" {
  description = "Versión del motor MariaDB en RDS"
  type        = string
  default     = "10.11"
}

variable "ec2_tipo_instancia" {
  description = "Tipo de EC2 para la fuente de archivos y para el tablero Streamlit"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Par de llaves EC2 que ya trae AWS Academy (vockey) para SSH al EMR"
  type        = string
  default     = "vockey"
}

variable "horario_pipeline" {
  description = "Cuándo corre solo el workflow de Glue (expresión cron de AWS, en UTC). 11:00 UTC = 6:00 a.m. Colombia"
  type        = string
  default     = "cron(0 11 * * ? *)"
}
