#!/bin/bash
# Boot entire orbital verification stack
# BOB VOYAGER (ISS oracle) + Verification Server (proof validator) + ROWM Notebook (UI)

set -e

echo "╔════════════════════════════════════════════╗"
echo "║  ORBITAL VERIFICATION STACK BOOT           ║"
echo "║  BOB VOYAGER + sov-kernel-monster + ROWM   ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# ─ 1. Start BOB VOYAGER (ISS telemetry proxy)
echo "[1/3] Starting BOB VOYAGER (http://localhost:4299)..."
cd "$(dirname "$(find . -name "server.mjs" -path "*/bob-voyager/*" | head -1)")"
node server.mjs &
VOYAGER_PID=$!
sleep 2

# ─ 2. Start Verification Server (orbital invariant oracle)
echo "[2/3] Starting Verification Server (http://localhost:3333)..."
cd "$(dirname "$(pwd)")/sov-kernel-monster"
VOYAGER_URL=http://localhost:4299 node src/verification_server.mjs &
VERIFY_PID=$!
sleep 2

# ─ 3. Open ROWM Notebook
echo "[3/3] Opening ROWM Polymorphic Notebook..."
cd "$(dirname "$(pwd)")/rowm-polymorphic-notebook"
# On macOS:
# open index-app.html
# On Linux:
# xdg-open index-app.html
# On Windows (WSL):
explorer.exe index-app.html 2>/dev/null || xdg-open index-app.html 2>/dev/null || open index-app.html 2>/dev/null

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  ORBITAL STACK READY                       ║"
echo "║  BOB VOYAGER:        http://localhost:4299 ║"
echo "║  Verification:       http://localhost:3333 ║"
echo "║  ROWM Notebook:      $(pwd)/index-app.html ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "Press Ctrl+C to stop all services"
wait
