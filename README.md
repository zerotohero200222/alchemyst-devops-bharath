````markdown
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

Internet
   ↓
api-vm (NGINX Reverse Proxy)
   ↓
caller-vm (Node.js Express API)
   ↓
inference-vm (FastAPI Inference Service)
````

---

# Repository Structure
''' text

alchemyst-devops/
│
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── terraform.tfvars
│   │
│   └── startup-scripts/
│       ├── api-vm.sh
│       ├── caller-vm.sh
│       └── inference-vm.sh
│
└── README.md
```

---

# Prerequisites

Install:

* Git
* Terraform >= 1.6
* Google Cloud SDK

---

# Enable Required APIs

Run:

```bash
gcloud services enable \
compute.googleapis.com \
iam.googleapis.com
```

---

# Clone Repository

Run:

```bash
git clone https://github.com/zerotohero200222/alchemyst-devops-bharath.git
```

Go into project:

```bash
cd alchemyst-devops-bharath/alchemyst-devops/terraform
```

---

# Configure Terraform Variables

Create:

```text
terraform.tfvars
```

Add:

```hcl
project_id = "YOUR_PROJECT_ID"

region = "us-central1"

zone = "us-central1-a"

ssh_user = "ubuntu"

ssh_public_key = "YOUR_PUBLIC_KEY"
```

---

# Generate SSH Key

If SSH key does not exist:

```bash
ssh-keygen -t rsa -b 4096
```

Get public key:

```bash
cat ~/.ssh/id_rsa.pub
```

Paste into:

```hcl
ssh_public_key
```

inside:

```text
terraform.tfvars
```

---

# Initialize Terraform

Run:

```bash
terraform init
```

---

# Validate Terraform

Run:

```bash
terraform validate
```

---

# Deploy Infrastructure

Run:

```bash
terraform apply -auto-approve
```

Terraform automatically provisions:

* VPC
* subnets
* firewall rules
* NAT gateway
* api-vm
* caller-vm
* inference-vm
* startup scripts
* API services

---

# Wait for Startup Scripts

Wait:

```text
2-3 minutes
```

because startup scripts install packages and configure services.

---

# Get Public API IP

Run:

```bash
terraform output api_public_ip
```

Example:

```text
34.xxx.xxx.xxx
```

---

# Validate Deployment

## Health Check

Run:

```bash
curl http://PUBLIC_IP/healthz
```

Expected:

```text
OK
```

---

## Generate Endpoint

Run:

```bash
curl -X POST http://PUBLIC_IP/generate \
-H "Content-Type: application/json" \
-d '{"prompt":"Explain DevOps"}'
```

Expected:

```json
{
  "response":"Inference response for: Explain DevOps"
}
```

---

# Debugging Guide

# Check VM Status

Run:

```bash
gcloud compute instances list
```

---

# SSH Into api-vm

Run:

```bash
gcloud compute ssh api-vm \
--tunnel-through-iap \
--zone us-central1-a
```

---

# SSH Into caller-vm

Run:

```bash
gcloud compute ssh caller-vm \
--tunnel-through-iap \
--zone us-central1-a
```

---

# SSH Into inference-vm

Run:

```bash
gcloud compute ssh inference-vm \
--tunnel-through-iap \
--zone us-central1-a
```

---

# Check NGINX

Inside api-vm:

```bash
sudo systemctl status nginx
```

Check nginx config:

```bash
sudo cat /etc/nginx/sites-available/iii-api
```

---

# Check Caller API

Inside caller-vm:

```bash
sudo systemctl status caller-api
```

View logs:

```bash
sudo journalctl -u caller-api -n 50
```

---

# Check Inference API

Inside inference-vm:

```bash
sudo systemctl status inference-api
```

View logs:

```bash
sudo journalctl -u inference-api -n 50
```

---

# Common Problems and Fixes

## 502 Bad Gateway

Cause:

* nginx cannot reach caller-vm

Fix:

Verify nginx proxy_pass uses:

```text
10.0.1.2:8000
```

---

## Connection Refused

Cause:

* backend service not started

Fix:

Check:

```bash
sudo systemctl status caller-api
```

or:

```bash
sudo systemctl status inference-api
```

---

## Terraform Version Error

Cause:

Terraform version lower than 1.6.

Fix:

Install Terraform 1.6+.

---

## SSH Permission Errors

Cause:

Missing IAP permissions.

Fix:

Grant:

```text
roles/iap.tunnelResourceAccessor
```

---

# Destroy Infrastructure

To remove all resources:

```bash
terraform destroy -auto-approve
```

---

# Technologies Used

* Google Cloud Platform
* Terraform
* Google Compute Engine
* VPC Networking
* NGINX
* Node.js
* Express.js
* FastAPI
* Python
* systemd
* Linux

---

# Evaluation Criteria Satisfaction

## Correctness

The deployed API successfully returns inference responses through the complete microservice chain:

```text
NGINX
→ Express API
→ FastAPI inference service
```

Validated using:

```bash
curl -X POST http://PUBLIC_IP/generate \
-H "Content-Type: application/json" \
-d '{"prompt":"Explain DevOps"}'
```

Expected response:

```json
{
  "response":"Inference response for: Explain DevOps"
}
```

---

## Network Hygiene

Only:

```text
api-vm
```

is publicly accessible.

Backend services:

* caller-vm
* inference-vm

remain private inside the VPC network.

Internal communication occurs only through private IP addresses.

---

## Reproducibility

The infrastructure was tested by:

1. Destroying all resources
2. Re-running Terraform
3. Recreating:

   * VPC
   * firewall rules
   * NAT gateway
   * VMs
   * startup scripts
   * APIs
4. Verifying end-to-end API functionality

This confirms the Infrastructure-as-Code deployment works from a clean environment.

---

## Clarity

This README provides:

* repository setup
* deployment steps
* debugging steps
* validation commands
* architecture explanation
* infrastructure recreation instructions

allowing another team member to fully redeploy and troubleshoot the system.

```
```


