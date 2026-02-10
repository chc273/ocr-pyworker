#!/bin/bash
# Setup script for DeepSeek-OCR-2 on vast.ai serverless
# 1. Installs model server deps
# 2. Starts the model server on port 18000
# 3. Sets up PyWorker venv and runs worker.py

export PIP_ROOT_USER_ACTION=ignore
export HF_HOME=/workspace/hf_cache
export WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
export WORKER_PORT="${WORKER_PORT:-3000}"
export USE_SSL="${USE_SSL:-true}"
export REPORT_ADDR="${REPORT_ADDR:-https://run.vast.ai}"

mkdir -p /var/log/portal /app "$WORKSPACE_DIR"

exec &> >(tee -a "$WORKSPACE_DIR/setup.log")
echo "=== setup.sh started at $(date) ==="
echo "CONTAINER_ID=$CONTAINER_ID"
echo "PYWORKER_REPO=$PYWORKER_REPO"

# Ensure basic tools are available (runtime images may lack git/wget)
if ! which git > /dev/null 2>&1 || ! which wget > /dev/null 2>&1; then
    echo "Installing git and wget..."
    apt-get update -qq && apt-get install -y -qq git wget curl > /dev/null 2>&1
fi

# Install model server deps only once
if [ ! -f "$WORKSPACE_DIR/.deps_ok" ]; then
    echo "Installing model server dependencies..."
    pip install transformers==4.46.3 tokenizers==0.20.3 PyMuPDF einops easydict addict Pillow numpy fastapi 'uvicorn[standard]' 2>&1 | tail -5
    touch "$WORKSPACE_DIR/.deps_ok"
    echo "Dependencies installed."
fi

# Download server code
if [ ! -f /app/ocr_server.py ]; then
    wget -q -O /app/ocr_server.py "https://gist.githubusercontent.com/chc273/d585dec4e063689d23eb4786b8106857/raw/ocr_server.py"
fi

# Start model server in background
echo "Starting OCR model server on port 18000..."
nohup python3 /app/ocr_server.py > /var/log/portal/ocr_server.log 2>&1 &
echo "Model server PID: $!"

# --- PyWorker Setup ---
SERVER_DIR="$WORKSPACE_DIR/vast-pyworker"
ENV_PATH="$WORKSPACE_DIR/worker-env"
PYWORKER_LOG="$WORKSPACE_DIR/pyworker.log"

# Install uv if needed
if ! which uv > /dev/null 2>&1; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    [ -f ~/.local/bin/env ] && source ~/.local/bin/env
fi

# Clone PYWORKER_REPO
if [ ! -d "$SERVER_DIR" ]; then
    echo "Cloning $PYWORKER_REPO..."
    git clone "${PYWORKER_REPO:-https://github.com/chc273/ocr-pyworker}" "$SERVER_DIR"
fi

# Create venv and install deps
if [ ! -d "$ENV_PATH" ]; then
    echo "Creating venv..."
    uv venv --python-preference only-managed "$ENV_PATH" -p 3.10
    source "$ENV_PATH/bin/activate"
    echo "Installing PyWorker requirements..."
    uv pip install -r "$SERVER_DIR/requirements.txt"
    echo "Installing vastai-sdk..."
    uv pip install vastai-sdk
else
    source "$ENV_PATH/bin/activate"
fi

# SSL setup
if [ "$USE_SSL" = true ]; then
    echo "Setting up SSL..."
    cat << 'SSLEOF' > /etc/openssl-san.cnf
    [req]
    default_bits       = 2048
    distinguished_name = req_distinguished_name
    req_extensions     = v3_req
    [req_distinguished_name]
    countryName         = US
    stateOrProvinceName = CA
    organizationName    = Vast.ai Inc.
    commonName          = vast.ai
    [v3_req]
    basicConstraints = CA:FALSE
    keyUsage         = nonRepudiation, digitalSignature, keyEncipherment
    subjectAltName   = @alt_names
    [alt_names]
    IP.1   = 0.0.0.0
SSLEOF
    openssl req -newkey rsa:2048 -subj "/C=US/ST=CA/CN=pyworker.vast.ai/" \
        -nodes -sha256 -keyout /etc/instance.key -out /etc/instance.csr \
        -config /etc/openssl-san.cnf 2>/dev/null
    curl -s --header 'Content-Type: application/octet-stream' \
        --data-binary @/etc/instance.csr \
        -X POST "https://console.vast.ai/api/v0/sign_cert/?instance_id=$CONTAINER_ID" > /etc/instance.crt
    echo "SSL setup done."
fi

# Populate /etc/environment
if ! grep -q "VAST" /etc/environment 2>/dev/null; then
    env -0 | grep -zEv "^(HOME=|SHLVL=)|CONDA" | while IFS= read -r -d '' line; do
        name=${line%%=*}
        value=${line#*=}
        printf '%s="%s"\n' "$name" "$value"
    done > /etc/environment 2>/dev/null || true
fi

touch ~/.no_auto_tmux 2>/dev/null || true

# Run PyWorker
echo "Starting PyWorker..."
cd "$SERVER_DIR"
export REPORT_ADDR WORKER_PORT USE_SSL
python3 -m "worker" 2>&1 | tee -a "$PYWORKER_LOG"
