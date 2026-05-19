# Automated Multi-VM Microservice Infrastructure on Google Cloud Platform

# Overview

This project demonstrates a production-style multi-VM microservice deployment on Google Cloud Platform using:

- Terraform Infrastructure as Code (IaC)
- Google Compute Engine (GCE)
- Private VPC networking
- NGINX reverse proxy
- Node.js Express API
- FastAPI inference service
- Startup-script automation
- Systemd service persistence

The infrastructure automatically provisions:

- VPC network
- public/private subnets
- firewall rules
- NAT gateway
- Compute Engine VMs
- internal service communication
- automated API deployment

Architecture:

```text
Internet
   ↓
api-vm (NGINX Reverse Proxy)
   ↓
caller-vm (Node.js Express API)
   ↓
inference-vm (FastAPI Inference Service)
