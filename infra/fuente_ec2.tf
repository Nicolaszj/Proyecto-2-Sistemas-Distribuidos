# PUNTO 2 - Fuente 2: EC2 con archivos de ventas (simula el servidor del
# sistema de caja que deja un CSV por mes en /srv/ventas).
# PUNTO 3 - Esa misma EC2 sube sus archivos a S3 raw cada 10 minutos (cron).
#
# Al arrancar, el user_data (plantillas/fuente_ec2_user_data.sh.tftpl):
#   1. instala el cliente de MariaDB
#   2. baja de S3 el dataset y los scripts del repo
#   3. corre preparar_fuentes.py -> /srv/ventas/*.csv + seed_mariadb.sql
#   4. carga seed_mariadb.sql en el RDS
#   5. programa sincronizar_ventas_s3.sh en cron y lo corre una vez
# Se entra a la máquina con Session Manager (botón "Connect"), sin SSH.

resource "aws_instance" "fuente" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.ec2_tipo_instancia
  subnet_id              = data.aws_subnet.zona_a.id
  vpc_security_group_ids = [aws_security_group.fuente.id]
  iam_instance_profile   = local.perfil_instancia

  user_data = templatefile("${path.module}/plantillas/fuente_ec2_user_data.sh.tftpl", {
    bucket  = local.bucket
    db_host = aws_db_instance.mariadb.address
    db_user = aws_db_instance.mariadb.username
    db_pass = random_password.db.result
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  tags = { Name = "${var.proyecto}-fuente-archivos" }

  # Los scripts y el dataset deben estar en S3 antes de que arranque.
  depends_on = [aws_s3_object.codigo, aws_s3_object.dataset]
}
