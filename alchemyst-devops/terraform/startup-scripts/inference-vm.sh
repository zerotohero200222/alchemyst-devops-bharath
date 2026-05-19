#!/bin/bash

set -e

apt-get update

apt-get install -y python3-pip python3-venv

mkdir -p /opt/inference-worker

cat > /opt/inference-worker/api.py <<'INNER_EOF'
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class PromptRequest(BaseModel):
    prompt: str

@app.get("/healthz")
def health():
    return "OK"

@app.post("/generate")
def generate(req: PromptRequest):
    return {
        "response": f"Inference response for: {req.prompt}"
    }
INNER_EOF

cd /opt/inference-worker

python3 -m venv venv

source venv/bin/activate

pip install fastapi uvicorn

cat > /etc/systemd/system/inference-api.service <<'INNER_EOF'
[Unit]
Description=Inference API
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/inference-worker
ExecStart=/opt/inference-worker/venv/bin/uvicorn api:app --host 0.0.0.0 --port 8001
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
INNER_EOF

systemctl daemon-reload
systemctl enable inference-api
systemctl restart inference-api
