locals {
  project     = "inventory"
  environment = var.environment
  region      = var.region

  common_tags = {
    project     = local.project
    environment = local.environment
    owner       = "jordann6"
    managed_by  = "terraform"
  }
}

# --- DynamoDB -----------------------------------------------------------------

resource "aws_dynamodb_table" "inventory" {
  name         = "${local.project}-${local.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "item_id"

  attribute {
    name = "item_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

# --- IAM Role for Lambda ------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "role-${local.project}-lambda-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "lambda_dynamo" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.inventory.arn]
  }
}

data "aws_iam_policy_document" "lambda_bedrock" {
  statement {
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:${var.region}::foundation-model/${var.bedrock_model_id}"]
  }
}

resource "aws_iam_policy" "lambda_dynamo" {
  name   = "policy-${local.project}-lambda-dynamo-${local.environment}"
  policy = data.aws_iam_policy_document.lambda_dynamo.json
  tags   = local.common_tags
}

resource "aws_iam_policy" "lambda_bedrock" {
  name   = "policy-${local.project}-lambda-bedrock-${local.environment}"
  policy = data.aws_iam_policy_document.lambda_bedrock.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamo.arn
}

resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_bedrock.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda Function ----------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "inventory" {
  function_name    = "lambda-${local.project}-api-${local.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      TABLE_NAME       = aws_dynamodb_table.inventory.name
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }

  tags = local.common_tags
}

# --- API Gateway v2 (HTTP API) ------------------------------------------------

resource "aws_apigatewayv2_api" "inventory" {
  name          = "api-${local.project}-${local.environment}"
  protocol_type = "HTTP"
  tags          = local.common_tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.inventory.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.inventory.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "items_list" {
  api_id    = aws_apigatewayv2_api.inventory.id
  route_key = "GET /items"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "items_create" {
  api_id    = aws_apigatewayv2_api.inventory.id
  route_key = "POST /items"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "item_get" {
  api_id    = aws_apigatewayv2_api.inventory.id
  route_key = "GET /items/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "item_delete" {
  api_id    = aws_apigatewayv2_api.inventory.id
  route_key = "DELETE /items/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "item_analyze" {
  api_id    = aws_apigatewayv2_api.inventory.id
  route_key = "POST /items/{id}/analyze"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.inventory.id
  name        = "$default"
  auto_deploy = true
  tags        = local.common_tags
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.inventory.execution_arn}/*/*"
}
