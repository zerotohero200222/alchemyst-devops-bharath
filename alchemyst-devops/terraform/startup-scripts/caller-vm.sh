#!/bin/bash

set -e

apt-get update

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

mkdir -p /opt/caller-worker

cat > /opt/caller-worker/server.js <<'INNER_EOF'
import express from "express";
import axios from "axios";

const app = express();

app.use(express.json());

app.get("/healthz", (req, res) => {
  res.send("OK");
});

app.post("/generate", async (req, res) => {
  try {
    const response = await axios.post(
      "http://10.0.1.2:8001/generate",
      req.body
    );

    res.json(response.data);
  } catch (err) {
    res.status(500).json({
      error: err.message
    });
  }
});

app.listen(8000, "0.0.0.0", () => {
  console.log("Caller worker listening on 8000");
});
INNER_EOF

cat > /opt/caller-worker/package.json <<'INNER_EOF'
{
  "type": "module",
  "dependencies": {
    "axios": "^1.6.0",
    "express": "^4.18.2"
  }
}
INNER_EOF

cd /opt/caller-worker

npm install

cat > /etc/systemd/system/caller-api.service <<'INNER_EOF'
[Unit]
Description=Caller API
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/caller-worker
ExecStart=/usr/bin/env node /opt/caller-worker/server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
INNER_EOF

systemctl daemon-reload
systemctl enable caller-api
systemctl restart caller-api
