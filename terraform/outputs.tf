output "api_endpoint" {
  description = "HTTP API invoke URL — append /items to start calling the API."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "table_name" {
  description = "DynamoDB table name."
  value       = aws_dynamodb_table.inventory.name
}

output "lambda_function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.inventory.function_name
}

output "lambda_execution_role_arn" {
  description = "IAM execution role ARN."
  value       = aws_iam_role.lambda_exec.arn
}
