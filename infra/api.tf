# PUNTO 8 - API expuesta con Amazon API Gateway (HTTP API) + AWS Lambda.
#
#   Streamlit / matplotlib / navegador
#        │  GET https://<id>.execute-api.us-east-1.amazonaws.com/preguntas/p1
#        ▼
#   API Gateway (rutas /salud, /preguntas, /preguntas/{id})
#        ▼
#   Lambda (08-visualizacion-y-api/api/lambda_function.py)
#        ▼
#   Athena -> tablas retail_refined.* -> S3 refined/

data "archive_file" "api" {
  type        = "zip"
  source_file = "${local.raiz}/08-visualizacion-y-api/api/lambda_function.py"
  output_path = "${path.module}/.construccion/api_lambda.zip"
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.proyecto}-api-consultas"
  description      = "Responde las preguntas de negocio consultando Athena (zona refined)"
  role             = local.rol_lab
  runtime          = "python3.12"
  handler          = "lambda_function.lambda_handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      ATHENA_WORKGROUP = aws_athena_workgroup.retail.name
      REFINED_DB       = aws_glue_catalog_database.refined.name
    }
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.proyecto}-api"
  protocol_type = "HTTP"
  description   = "API de resultados del Proyecto 2"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "rutas" {
  for_each  = toset(["GET /salud", "GET /preguntas", "GET /preguntas/{id}"])
  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "defecto" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

# Permiso para que API Gateway pueda invocar la Lambda.
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "PermitirApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
