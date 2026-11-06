#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="citybike:v1"
PORT=4173

cleanup() {
  docker rm -f citybike-stage 2>/dev/null || true
  sleep 1
}
trap cleanup EXIT

echo "=== STAGE 1: LOCAL BUILD & SMOKE CHECK ==="
docker build -t "$IMAGE_TAG" .
cleanup
docker run -d --name citybike-stage -p "$PORT:$PORT" "$IMAGE_TAG"
sleep 2
curl -fsS "http://localhost:$PORT/health" | grep -q '"ok":true'
echo "✓ Local health check passed"

echo "=== STAGE 2: DEVELOPMENT ENVIRONMENT ==="
cleanup
docker run -d --name citybike-stage -p "$PORT:$PORT" -e APP_ENV=development "$IMAGE_TAG"
sleep 2
curl -fsS "http://localhost:$PORT/health" | grep -q '"environment":"development"'
echo "✓ Dev environment verified"

echo "=== STAGE 3: QA ENVIRONMENT ==="
cleanup
docker run -d --name citybike-stage -p "$PORT:$PORT" -e APP_ENV=qa "$IMAGE_TAG"
sleep 2
curl -fsS "http://localhost:$PORT/api/stations" | grep -q '"stations"'
echo "✓ QA station route verified"

echo "=== STAGE 4: STAGING ENVIRONMENT ==="
cleanup
docker run -d --name citybike-stage -p "$PORT:$PORT" -e APP_ENV=staging "$IMAGE_TAG"
sleep 2
curl -fsS "http://localhost:$PORT/health" | grep -q '"environment":"staging"'
echo "✓ Staging environment verified"

echo "=== STAGE 5: PRODUCTION DEPLOYMENT ==="
cleanup
export PROD_API_KEY="citybike-secret-key-2026"
docker run -d --name citybike-stage -p "$PORT:$PORT" \
  -e APP_ENV=production \
  -e PROD_API_KEY="$PROD_API_KEY" \
  "$IMAGE_TAG"
sleep 2
HEALTH=$(curl -fsS "http://localhost:$PORT/health")
echo "$HEALTH" | grep -q '"environment":"production"'
echo "$HEALTH" | grep -q '"secureKeyConfigured":true'
echo "✓ Production deployment verified with PROD_API_KEY"

echo "============================================="
echo "🎉 ALL 5 ENVIRONMENTS SUCCESSFULLY PROMOTED!"
echo "============================================="
