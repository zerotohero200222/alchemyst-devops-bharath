#!/usr/bin/env bash
# api-vm startup script
# Runs once on first boot (GCP startup-script metadata).
# Installs: iii engine, nginx reverse proxy.
# The iii engine listens on :49134 (WS, internal only) and :3111 (HTTP, localhost).
# nginx listens on :80 and proxies to :3111.
set -euo pipefail
exec > /var/log/startup.log 2>&1

echo "[startup] === api-vm bootstrap starting $(date) ==="

###############################################################################
# 1. System packages
###############################################################################
apt-get update -qq
apt-get install -y -qq curl git nginx unzip jq

###############################################################################
# 2. Install Node.js 20 (needed for iii CLI which is Node-based)
###############################################################################
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y -qq nodejs

###############################################################################
# 3. Install the iii CLI
#    Primary: official install script. Fallback: npm global install.
###############################################################################
if curl -fsSL https://iii.dev/install.sh -o /tmp/iii-install.sh 2>/dev/null; then
  bash /tmp/iii-install.sh
else
  npm install -g iii-cli 2>/dev/null || npm install -g iii 2>/dev/null || true
fi

# Ensure iii is on PATH for all users
export PATH="$PATH:/usr/local/bin:/root/.local/bin:$(npm root -g)/.bin"
ln -sf "$(which iii 2>/dev/null || echo /usr/local/bin/iii)" /usr/local/bin/iii 2>/dev/null || true

echo "[startup] iii version: $(iii --version 2>/dev/null || echo 'installed (version check failed)')"

###############################################################################
# 4. Write the iii engine config
#    Only engine workers run here. inference-worker and caller-worker run
#    on their own VMs and connect via ws://THIS_VM_IP:49134.
###############################################################################
mkdir -p /opt/iii/data

cat > /opt/iii/config.yaml << 'IIICONFIG'
# iii engine configuration for api-vm
# Workers (inference-worker, caller-worker) run remotely and self-register.
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii
      exporter: memory
      memory_max_spans: 10000
      metrics_enabled: true
      metrics_exporter: memory
      logs_enabled: true
      logs_exporter: memory
      logs_console_output: true
      sampling_ratio: 1.0

  - name: iii-queue
    config:
      adapter:
        name: builtin

  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: /opt/iii/data/state_store.db

  - name: iii-http
    config:
      port: 3111
      # Bind to all interfaces so nginx (on the same host) can reach it.
      # nginx handles external exposure; nothing else in the VPC forwards :3111.
      host: 0.0.0.0
      default_timeout: 60000
      concurrency_request_limit: 1024
      cors:
        allowed_origins:
          - '*'
        allowed_methods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
IIICONFIG

###############################################################################
# 5. systemd unit — iii engine
###############################################################################
cat > /etc/systemd/system/iii-engine.service << 'SVCEOF'
[Unit]
Description=iii Distributed Worker Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iii
ExecStart=/usr/local/bin/iii start --config /opt/iii/config.yaml
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable iii-engine
systemctl start iii-engine

echo "[startup] iii engine service started"

###############################################################################
# 6. nginx — reverse proxy :80 → iii-http :3111
###############################################################################
cat > /etc/nginx/sites-available/iii-api << 'NGINXEOF'
server {
    listen 80 default_server;
    server_name _;

    # Forward all traffic to the iii HTTP API.
    location / {
        proxy_pass         http://127.0.0.1:3111;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       $host;
        proxy_set_header   X-Real-IP  $remote_addr;
        proxy_read_timeout 300s;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/iii-api /etc/nginx/sites-enabled/iii-api
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl enable nginx && systemctl restart nginx

echo "[startup] nginx started"

###############################################################################
# 7. Write internal IP to a well-known file so other VMs can read it from
#    GCP metadata (they query: curl -H 'Metadata-Flavor: Google'
#    http://metadata.google.internal/computeMetadata/v1/instance/attributes/api_vm_ip)
###############################################################################
INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
echo "$INTERNAL_IP" > /opt/iii/internal_ip.txt
echo "[startup] Internal IP: $INTERNAL_IP"

echo "[startup] === api-vm bootstrap complete $(date) ==="
