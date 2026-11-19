# PUNTO 8 - EC2 con el tablero Streamlit (consume la API de api.tf).
# El user_data instala Python 3.11 + Streamlit, copia app.py desde S3 y deja
# un servicio systemd escuchando en el puerto 8501.

resource "aws_instance" "streamlit" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.ec2_tipo_instancia
  subnet_id                   = data.aws_subnet.zona_a.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = local.perfil_instancia
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/plantillas/streamlit_user_data.sh.tftpl", {
    bucket  = local.bucket
    api_url = aws_apigatewayv2_api.api.api_endpoint
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.proyecto}-streamlit" }

  depends_on = [aws_s3_object.codigo]
}
