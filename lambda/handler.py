import json
import os
import uuid
import boto3
from datetime import datetime, timezone
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
bedrock = boto3.client("bedrock-runtime")

TABLE_NAME = os.environ["TABLE_NAME"]
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-5-haiku-20241022-v1:0")


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, cls=DecimalEncoder),
    }


def handler(event, context):
    route_key = event.get("routeKey", "")
    path_params = event.get("pathParameters") or {}
    item_id = path_params.get("id")

    routes = {
        "GET /items":              lambda: list_items(),
        "POST /items":             lambda: create_item(json.loads(event.get("body") or "{}")),
        "GET /items/{id}":         lambda: get_item(item_id),
        "DELETE /items/{id}":      lambda: delete_item(item_id),
        "POST /items/{id}/analyze": lambda: analyze_item(item_id),
    }

    fn = routes.get(route_key)
    if not fn:
        return respond(404, {"error": "Not found"})
    return fn()


def list_items():
    table = dynamodb.Table(TABLE_NAME)
    result = table.scan()
    return respond(200, result["Items"])


def create_item(body):
    table = dynamodb.Table(TABLE_NAME)
    now = datetime.now(timezone.utc).isoformat()
    item = {
        "item_id":          str(uuid.uuid4()),
        "name":             body["name"],
        "sku":              body["sku"],
        "quantity":         int(body.get("quantity", 0)),
        "reorder_threshold": int(body.get("reorder_threshold", 10)),
        "unit_cost":        str(body.get("unit_cost", "0.00")),
        "category":         body.get("category", "general"),
        "created_at":       now,
        "updated_at":       now,
    }
    table.put_item(Item=item)
    return respond(201, item)


def get_item(item_id):
    table = dynamodb.Table(TABLE_NAME)
    result = table.get_item(Key={"item_id": item_id})
    item = result.get("Item")
    if not item:
        return respond(404, {"error": "Item not found"})
    return respond(200, item)


def delete_item(item_id):
    table = dynamodb.Table(TABLE_NAME)
    table.delete_item(Key={"item_id": item_id})
    return respond(204, {})


def analyze_item(item_id):
    table = dynamodb.Table(TABLE_NAME)
    result = table.get_item(Key={"item_id": item_id})
    item = result.get("Item")
    if not item:
        return respond(404, {"error": "Item not found"})

    prompt = (
        "You are an inventory analyst. Analyze this item and respond with a JSON object only — no prose.\n\n"
        f"Item: {item['name']} (SKU: {item['sku']})\n"
        f"Category: {item['category']}\n"
        f"Current quantity: {item['quantity']}\n"
        f"Reorder threshold: {item['reorder_threshold']}\n"
        f"Unit cost: ${item['unit_cost']}\n\n"
        'Required format: {"status": "ok|low|critical", "recommendation": "<one sentence>", "reorder_quantity": <integer>}'
    )

    response = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 256,
            "messages": [{"role": "user", "content": prompt}],
        }),
        contentType="application/json",
        accept="application/json",
    )

    result_body = json.loads(response["body"].read())
    analysis_text = result_body["content"][0]["text"].strip()

    try:
        analysis = json.loads(analysis_text)
    except json.JSONDecodeError:
        analysis = {"recommendation": analysis_text}

    return respond(200, {"item_id": item_id, "analysis": analysis})
