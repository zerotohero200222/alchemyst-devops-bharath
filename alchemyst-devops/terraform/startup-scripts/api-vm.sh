#!/bin/bash

set -e

apt-get update
apt-get install -y nginx

cat > /etc/nginx/sites-available/iii-api <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://10.0.1.3:8000;
        proxy_http_version 1.1;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        proxy_read_timeout 300s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/iii-api /etc/nginx/sites-enabled/iii-api

rm -f /etc/nginx/sites-enabled/default

nginx -t

systemctl enable nginx
systemctl restart nginx
