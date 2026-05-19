#!/usr/bin/env bash
# inference-vm startup script
# Installs Python 3.11, downloads the GGUF model, and starts inference-worker.
# NOTE: The model download (gemma-3-270m Q8, ~270 MB) and pip install will
# take 5-15 minutes on first boot depending on instance and bandwidth.
set -euo pipefail
exec > /var/log/startup.log 2>&1

echo "[startup] === inference-vm bootstrap starting $(date) ==="

###############################################################################
# 1. Get the api-vm internal IP from instance metadata
###############################################################################
API_VM_IP=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/api_vm_ip")

echo "[startup] api-vm internal IP: $API_VM_IP"
echo "[startup] III_URL will be: ws://$API_VM_IP:49134"

# Wait until the iii engine is reachable before attempting worker startup.
echo "[startup] Waiting for iii engine at $API_VM_IP:49134 ..."
for i in $(seq 1 60); do
  if nc -z "$API_VM_IP" 49134 2>/dev/null; then
    echo "[startup] iii engine is up."
    break
  fi
  echo "[startup]   attempt $i/60, sleeping 15s..."
  sleep 15
done

###############################################################################
# 2. System packages
###############################################################################
apt-get update -qq
apt-get install -y -qq \
  python3.11 python3.11-venv python3-pip \
  curl git netcat-openbsd build-essential \
  libgomp1   # OpenMP required by llama.cpp / torch

###############################################################################
# 3. Create virtualenv and install dependencies
###############################################################################
python3.11 -m venv /opt/inference-worker/.venv
source /opt/inference-worker/.venv/bin/activate

# gguf wheel + torch CPU-only (smaller, no GPU on free tier)
pip install --quiet --upgrade pip
pip install --quiet \
  "iii-sdk==0.11.0" \
  "transformers>=4.40.0" \
  "torch>=2.2.0" \
  "accelerate>=0.29.0" \
  "gguf>=0.9.0" \
  "watchfiles"

echo "[startup] Python dependencies installed"

###############################################################################
# 4. Write inference_worker.py
###############################################################################
mkdir -p /opt/inference-worker
cat > /opt/inference-worker/inference_worker.py << 'PYEOF'
import os
from typing import Any, Dict, List

from iii import InitOptions, Logger, register_worker
from transformers import AutoModelForCausalLM, AutoTokenizer

iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="inference-worker"),
)
logger = Logger()

# ---------------------------------------------------------------------------
# Model loading — happens once at process start.
# gemma-3-270m Q8 GGUF is ~270 MB; fits comfortably in 4 GB RAM.
# ---------------------------------------------------------------------------
MODEL_ID   = "ggml-org/gemma-3-270m-GGUF"
GGUF_FILE  = "gemma-3-270m-Q8_0.gguf"

logger.info(f"Loading model {MODEL_ID} / {GGUF_FILE} ...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, gguf_file=GGUF_FILE)
model     = AutoModelForCausalLM.from_pretrained(MODEL_ID, gguf_file=GGUF_FILE)

# Patch in the Gemma-3 chat template (not always bundled with the GGUF tokenizer)
tokenizer.chat_template = (
    "{{ bos_token }}"
    "{%- if messages[0]['role'] == 'system' -%}"
    "    {%- set first_user_prefix = messages[0]['content'] + '\n\n' -%}"
    "    {%- set loop_messages = messages[1:] -%}"
    "{%- else -%}"
    "    {%- set first_user_prefix = '' -%}"
    "    {%- set loop_messages = messages -%}"
    "{%- endif -%}"
    "{%- for message in loop_messages -%}"
    "    {%- if (message['role'] == 'assistant') -%}"
    "        {%- set role = 'model' -%}"
    "    {%- else -%}"
    "        {%- set role = message['role'] -%}"
    "    {%- endif -%}"
    "    {{ '<start_of_turn>' + role + '\n' + (first_user_prefix if loop.first else '') }}"
    "    {%- if message['content'] is string -%}"
    "        {{ message['content'] | trim }}"
    "    {%- endif -%}"
    "    {{ '<end_of_turn>\n' }}"
    "{%- endfor -%}"
    "{%- if add_generation_prompt -%}"
    "    {{ '<start_of_turn>model\n' }}"
    "{%- endif -%}"
)

logger.info("Model loaded — inference worker ready")

# ---------------------------------------------------------------------------
# RPC handler
# ---------------------------------------------------------------------------
def run_inference_handler(
    payload: Dict[str, Any]
) -> Dict[str, Any]:
    messages: List[Dict[str, Any]] = payload.get("messages", [])
    max_new_tokens: int            = payload.get("max_new_tokens", 512)

    text   = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    inputs = tokenizer(text, return_tensors="pt").to(model.device)

    output = model.generate(
        **inputs,
        max_new_tokens=max_new_tokens,
        do_sample=False,         # deterministic for reproducibility
    )
    response = tokenizer.decode(
        output[0][inputs["input_ids"].shape[-1]:],
        skip_special_tokens=True,
    )

    logger.info(f"Inference complete, response length: {len(response)}")
    return {"response": response, "model": MODEL_ID}


iii.register_function("inference::run_inference", run_inference_handler)
logger.info("inference-worker registered and listening")
PYEOF

###############################################################################
# 5. systemd unit
###############################################################################
cat > /etc/systemd/system/inference-worker.service << SVCEOF
[Unit]
Description=iii Inference Worker (Python / GGUF)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/inference-worker
ExecStart=/opt/inference-worker/.venv/bin/python inference_worker.py
Restart=on-failure
RestartSec=15
# Large model load — give it 5 minutes before systemd considers it failed.
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal
Environment=III_URL=ws://${API_VM_IP}:49134
Environment=HF_HOME=/opt/inference-worker/.cache/huggingface
Environment=PATH=/opt/inference-worker/.venv/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable inference-worker
systemctl start inference-worker

echo "[startup] inference-worker service started (model download may take a few minutes)"
echo "[startup] === inference-vm bootstrap complete $(date) ==="
