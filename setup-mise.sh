#!/usr/bin/env bash
set -euo pipefail

echo "Installing tools via mise..."
mise install

JAVA_HOME="$(mise where java@17 2>/dev/null || mise where java 2>/dev/null)"
export JAVA_HOME
export PATH="${JAVA_HOME}/bin:${PATH}"

MAVEN="$(mise which mvn 2>/dev/null || echo mvn)"

echo "Pre-fetching backend dependencies..."
(cd backend && "${MAVEN}" -q dependency:go-offline && "${MAVEN}" -q compile -DskipTests)

echo "Pre-fetching frontend dependencies..."
(cd frontend && mise exec -- npm install)

echo

echo "✓ Setup complete. On interview day run:"
echo "  Terminal 1: cd backend && ${MAVEN} spring-boot:run"
echo "  Terminal 2: cd frontend && mise exec -- npm run dev"
