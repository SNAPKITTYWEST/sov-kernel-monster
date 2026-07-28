#!/bin/bash
# Boot entire orbital verification stack
# BOB VOYAGER + Ahmad Orchestrator (sov-kernel-monster) + optional ROWM UI

set -e

echo "╔════════════════════════════════════════════╗"
echo "║  ORBITAL VERIFICATION STACK BOOT           ║"
echo "║  BOB VOYAGER + Ahmad Orchestrator + ROWM   ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# ─ 1. Start BOB VOYAGER (ISS telemetry proxy)
echo "[1/3] Starting BOB VOYAGER (http://localhost:4299)..."
cd "$(dirname "$(find . -name "server.mjs" -path "*/bob-voyager/*" | head -1)")"
node server.mjs &
VOYAGER_PID=$!
sleep 2

# ─ 2. Start Ahmad Orchestrator (sov-kernel-monster)
echo "[2/3] Starting Ahmad Orchestrator (http://localhost:5555)..."
cd "$(dirname "$(pwd)")/sov-kernel-monster"
VOYAGER_URL=http://localhost:4299 node src/ahmad-orchestrator.mjs &
AHMAD_PID=$!
sleep 2

# ─ 3. Optionally open ROWM Notebook (UI only)
echo "[3/3] Starting web server for ROWM Notebook (http://localhost:8000)..."
cd "$(dirname "$(pwd)")/rowm-polymorphic-notebook"
python3 -m http.server 8000 &
WEB_PID=$!
sleep 1
echo "Opening ROWM Notebook..."
explorer.exe http://localhost:8000/index-app.html 2>/dev/null || xdg-open http://localhost:8000/index-app.html 2>/dev/null || open http://localhost:8000/index-app.html 2>/dev/null

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  ORBITAL STACK READY                       ║"
echo "║  BOB VOYAGER:        http://localhost:4299 ║"
echo "║  Ahmad Orchestrator: http://localhost:5555 ║"
echo "║  ROWM Notebook UI:   http://localhost:8000 ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "Verification running in headless mode at :5555"
echo "Press Ctrl+C to stop all services"
wait
