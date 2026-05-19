#!/usr/bin/env bash
# caller-vm startup script
# Installs Node.js + caller-worker, then starts it as a systemd service.
# III_URL is set to ws://<api-vm-internal-ip>:49134 so it connects to the
# iii engine on api-vm over the private subnet.
set -euo pipefail
exec > /var/log/startup.log 2>&1

echo "[startup] === caller-vm bootstrap starting $(date) ==="

###############################################################################
# 1. Get the api-vm internal IP from instance metadata
###############################################################################
API_VM_IP=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/api_vm_ip")

echo "[startup] api-vm internal IP: $API_VM_IP"
echo "[startup] III_URL will be: ws://$API_VM_IP:49134"

# Wait until the iii engine is reachable before starting the worker.
echo "[startup] Waiting for iii engine at $API_VM_IP:49134 ..."
for i in $(seq 1 30); do
  if nc -z "$API_VM_IP" 49134 2>/dev/null; then
    echo "[startup] iii engine is up."
    break
  fi
  echo "[startup]   attempt $i/30, sleeping 10s..."
  sleep 10
done

###############################################################################
# 2. System packages
###############################################################################
apt-get update -qq
apt-get install -y -qq curl git netcat-openbsd

###############################################################################
# 3. Node.js 20
###############################################################################
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y -qq nodejs

###############################################################################
# 4. Clone / copy caller-worker source
#    In a real deployment this would be: git clone <your-repo> /opt/caller-worker
#    For this submission the source is baked into the startup script.
###############################################################################
mkdir -p /opt/caller-worker/src

# --- package.json ---
cat > /opt/caller-worker/package.json << 'PKGJSON'
{
  "name": "caller-worker",
  "version": "0.1.0",
  "type": "module",
  "description": "Calls inference::run_inference in the Python worker and returns the result",
  "scripts": {
    "dev": "tsx watch src/worker.ts",
    "start": "tsx src/worker.ts"
  },
  "dependencies": {
    "iii-sdk": "0.11.0"
  },
  "devDependencies": {
    "@types/node": "^25.2.2",
    "tsx": "^4.0.0",
    "typescript": "^5.0.0"
  },
  "license": "Apache-2.0"
}
PKGJSON

# --- tsconfig.json ---
cat > /opt/caller-worker/tsconfig.json << 'TSCJSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "outDir": "./dist"
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
TSCJSON

# --- src/worker.ts ---
cat > /opt/caller-worker/src/worker.ts << 'WORKEREOF'
import { Logger, registerWorker } from 'iii-sdk';

const iii = registerWorker(process.env.III_URL ?? 'ws://localhost:49134');
const logger = new Logger();

iii.registerFunction(
  'inference::get_response',
  async (payload: { messages: Record<string, any> } & Record<string, any>) => {
    logger.info('inference::get_response called in TypeScript', payload);

    const result = await iii.trigger({
      function_id: 'inference::run_inference',
      payload,
    });

    return {
      ...result,
      success:
        "Connected two workers across VMs — interoperating seamlessly over the private subnet.",
    };
  },
);

iii.registerFunction(
  'http::run_inference_over_http',
  async (payload: { body: { messages: Record<string, any> } & Record<string, any> }) => {
    const result = await iii.trigger({
      function_id: 'inference::get_response',
      payload: payload.body,
    });
    logger.info('Running http inference...');
    return {
      status_code: 200,
      body: { result },
      headers: { 'Content-Type': 'application/json' },
    };
  },
);

iii.registerTrigger({
  type: 'http',
  function_id: 'http::run_inference_over_http',
  config: { api_path: '/v1/chat/completions', http_method: 'POST' },
});

logger.info('Caller worker started — listening for calls');
WORKEREOF

###############################################################################
# 5. npm install
###############################################################################
cd /opt/caller-worker
npm install --silent

###############################################################################
# 6. systemd unit
###############################################################################
cat > /etc/systemd/system/caller-worker.service << SVCEOF
[Unit]
Description=iii Caller Worker (TypeScript)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/caller-worker
ExecStart=/usr/bin/npx tsx src/worker.ts
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=III_URL=ws://${API_VM_IP}:49134
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable caller-worker
systemctl start caller-worker

echo "[startup] caller-worker service started"
echo "[startup] === caller-vm bootstrap complete $(date) ==="
