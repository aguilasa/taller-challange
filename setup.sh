#!/usr/bin/env bash
set -euo pipefail

echo "Pre-fetching backend dependencies..."
(cd backend && mvn -q dependency:go-offline && mvn -q compile -DskipTests)

echo "Pre-fetching frontend dependencies..."
(cd frontend && npm install)

echo

echo "✓ Setup complete. On interview day run:"
echo "  Terminal 1: cd backend && mvn spring-boot:run"
echo "  Terminal 2: cd frontend && npm run dev"
