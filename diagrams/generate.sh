#!/bin/bash
# Generate all architecture diagrams
# Usage: ./diagrams/generate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="/tmp/diagrams-venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    pip install -q -r "$SCRIPT_DIR/requirements.txt"
else
    source "$VENV_DIR/bin/activate"
fi

echo "Generating diagrams..."
python3 "$SCRIPT_DIR/architecture.py"
python3 "$SCRIPT_DIR/credential-flow.py"
python3 "$SCRIPT_DIR/pipeline.py"
python3 "$SCRIPT_DIR/data-flow.py"
echo ""
echo "Done! Diagrams generated:"
ls -lh "$SCRIPT_DIR"/*.png
