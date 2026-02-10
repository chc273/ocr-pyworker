#!/bin/bash
# Setup script for DeepSeek-OCR-2 model server on vast.ai
# This is run by the onstart-cmd. It:
# 1. Installs model server deps
# 2. Starts the model server on port 18000
# 3. Downloads and runs start_server.sh to set up the PyWorker
set -e

export PIP_ROOT_USER_ACTION=ignore
export HF_HOME=/workspace/hf_cache

mkdir -p /var/log/portal /app

# Install deps only once
if [ ! -f /workspace/.deps_ok ]; then
    echo "Installing dependencies..."
    pip install transformers==4.46.3 tokenizers==0.20.3 PyMuPDF einops easydict addict Pillow numpy fastapi 'uvicorn[standard]' 2>&1 | tail -5
    pip install flash-attn==2.7.3 --no-build-isolation 2>&1 | tail -5
    touch /workspace/.deps_ok
    echo "Dependencies installed."
fi

# Download server code
if [ ! -f /app/ocr_server.py ]; then
    wget -q -O /app/ocr_server.py "https://gist.githubusercontent.com/chc273/d585dec4e063689d23eb4786b8106857/raw/ocr_server.py"
fi

# Start model server in background
echo "Starting OCR model server on port 18000..."
nohup python3 /app/ocr_server.py > /var/log/portal/ocr_server.log 2>&1 &

# Now start the PyWorker (this downloads start_server.sh and runs it, blocking)
echo "Starting PyWorker..."
wget -qO- https://raw.githubusercontent.com/vast-ai/pyworker/main/start_server.sh | bash
