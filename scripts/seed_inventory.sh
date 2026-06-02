#!/usr/bin/env bash
set -euo pipefail

API_URL="${1:?Usage: seed_inventory.sh <api-url>}"

echo "==> Creating inventory items..."

curl -sf -X POST "$API_URL/items" \
  -H "Content-Type: application/json" \
  -d '{"name":"Widget A","sku":"WGT-001","quantity":45,"reorder_threshold":20,"unit_cost":"4.99","category":"hardware"}' | jq .

curl -sf -X POST "$API_URL/items" \
  -H "Content-Type: application/json" \
  -d '{"name":"Gadget B","sku":"GDG-002","quantity":8,"reorder_threshold":25,"unit_cost":"12.50","category":"electronics"}' | jq .

ITEM_ID=$(
  curl -sf -X POST "$API_URL/items" \
    -H "Content-Type: application/json" \
    -d '{"name":"Component C","sku":"CMP-003","quantity":3,"reorder_threshold":15,"unit_cost":"2.25","category":"hardware"}' \
  | jq -r '.item_id'
)

echo ""
echo "==> Listing all items..."
curl -sf "$API_URL/items" | jq 'length'

echo ""
echo "==> Running Bedrock analysis on low-stock item ($ITEM_ID)..."
curl -sf -X POST "$API_URL/items/$ITEM_ID/analyze" | jq .
