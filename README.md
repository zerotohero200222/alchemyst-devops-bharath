# README.md

````markdown
# Serverless E-Commerce Microservices on Google Cloud Platform

# Overview

This project demonstrates a production-style multi-tier microservice deployment on Google Cloud Platform using:

- Terraform Infrastructure as Code (IaC)
- Cloud Build CI/CD
- Google Compute Engine (GCE)
- VPC networking
- Private subnet architecture
- NGINX reverse proxy
- Node.js microservice
- FastAPI inference service
- Zero-touch VM provisioning
- Startup-script automation
- Systemd service persistence

The system deploys a distributed HTTP-based inference platform where:

- `api-vm` acts as the public reverse proxy
- `caller-vm` acts as the API/business layer
- `inference-vm` acts as the backend inference service

Architecture:

```text
Internet
   ↓
api-vm (NGINX Reverse Proxy)
   ↓
caller-vm (Node.js Express API)
   ↓
inference-vm (FastAPI Inference Service)
````

---

# Why This Project Exists

Modern cloud-native applications require:

* automated infrastructure provisioning
* reproducible deployments
* scalable networking
* internal service communication
* CI/CD automation
* service persistence
* zero-touch deployments

Traditional manual VM configuration causes:

* inconsistent deployments
* downtime during recreation
* difficult debugging
* non-repeatable infrastructure
* operational overhead

This project demonstrates how DevOps practices solve those problems using Infrastructure as Code and automation.

---

# Common Challenges Include

* Manual VM provisioning
* Manual package installation
* Configuration drift
* Service failures after reboot
* Public exposure of internal services
* Complex deployment steps
* Lack of reproducibility
* CI/CD integration difficulties
* Internal VM communication failures
* Startup script inconsistencies

---

# Key Challenges Addressed

This project addresses:

| Challenge                      | Solution                  |
| ------------------------------ | ------------------------- |
| Manual infrastructure creation | Terraform                 |
| Manual deployments             | Cloud Build               |
| VM startup inconsistency       | Startup scripts           |
| Service persistence            | systemd                   |
| Public attack surface          | private subnet            |
| Service orchestration          | internal HTTP APIs        |
| Infrastructure reproducibility | IaC                       |
| Reverse proxy routing          | NGINX                     |
| Internal service communication | private VPC networking    |
| Zero-touch provisioning        | automated startup scripts |

---

# Problems Solved

## 1. Infrastructure Automation

Terraform provisions:

* VPC
* subnets
* firewall rules
* NAT gateway
* Compute Engine VMs
* startup scripts

without manual intervention.

---

## 2. CI/CD Automation

GitHub push automatically triggers:

```text
Cloud Build
→ Terraform Init
→ Terraform Validate
→ Terraform Plan
→ Terraform Apply
→ Smoke Tests
```

This creates a fully automated deployment workflow.

---

## 3. Internal Service Communication

Internal services communicate securely using private IPs:

```text
api-vm → caller-vm → inference-vm
```

No backend services are publicly exposed.

---

## 4. Service Persistence

All APIs run as:

```text
systemd services
```

which ensures:

* reboot persistence
* automatic restart
* process management

---

## 5. Reverse Proxy Architecture

NGINX acts as:

* public entrypoint
* reverse proxy
* request router

This simulates real production architecture.

---

# How the Solution Works

## Step 1 — Infrastructure Deployment

Terraform provisions:

* custom VPC
* public subnet
* private subnet
* firewall rules
* Cloud NAT
* Compute Engine instances

---

## Step 2 — VM Bootstrap Automation

Startup scripts automatically install:

### api-vm

* NGINX
* reverse proxy configuration

### caller-vm

* Node.js
* Express API
* Axios
* systemd service

### inference-vm

* Python
* FastAPI
* Uvicorn
* virtual environment
* systemd service

---

## Step 3 — Service Communication

### Public Requests

```http
POST /generate
```

flow through:

```text
NGINX
→ Node.js API
→ FastAPI inference service
```

---

## Step 4 — Smoke Testing

Cloud Build validates deployment by testing:

* `/healthz`
* `/generate`

before marking deployment successful.

---

# Prerequisites

Before deployment:

## Tools Required

* Git
* Terraform >= 1.6
* Google Cloud SDK
* VS Code
* GitHub account

---

## GCP APIs Required

Enable:

```bash
gcloud services enable \
cloudbuild.googleapis.com \
compute.googleapis.com \
iam.googleapis.com
```

---

## Required IAM Roles

Cloud Build service account requires:

* roles/compute.admin
* roles/storage.admin
* roles/iam.serviceAccountUser
* roles/editor

---

## Terraform Backend Bucket

Create:

```bash
gsutil mb gs://PROJECT_ID-tf-state
```

Enable versioning:

```bash
gsutil versioning set on gs://PROJECT_ID-tf-state
```

---

# Repository Structure

```text
alchemyst-devops/
│
├── cloudbuild.yaml
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

# What Was Changed Compared to Original Assignment

The original assignment architecture used:

* iii-engine
* iii-http
* iii-observability
* queue-based orchestration
* internal iii messaging

The project was redesigned into a cleaner HTTP microservice architecture.

---

## Original Architecture

```text
api-vm
   ↓
iii-engine
   ↓
worker queue
   ↓
inference
```

---

## Final Architecture

```text
api-vm (NGINX)
   ↓
caller-vm (Express API)
   ↓
inference-vm (FastAPI)
```

---

# Changes Implemented

| Original Requirement | Final Implementation      |
| -------------------- | ------------------------- |
| iii-engine           | Express API               |
| iii-http             | NGINX                     |
| iii queues           | HTTP REST APIs            |
| port 3111            | ports 8000/8001           |
| iii inference        | FastAPI                   |
| manual setup         | startup-script automation |
| partial automation   | zero-touch deployment     |
| manual persistence   | systemd services          |

---

# Newly Added Features

The following improvements were added beyond the original requirement:

* NGINX reverse proxy architecture
* REST-based internal communication
* FastAPI inference microservice
* Express.js API gateway layer
* systemd persistence
* reboot persistence validation
* fully automated startup scripts
* Cloud Build smoke tests
* zero-touch Terraform provisioning
* internal private networking
* automated VM bootstrap process

---

# Problems Faced During Implementation

## 1. Terraform Version Mismatch

### Problem

Terraform version:

```text
1.5.7
```

did not satisfy:

```text
required_version >= 1.6
```

### Resolution

Installed Terraform 1.6 manually in Cloud Shell.

---

## 2. Cloud Build Directory Issue

### Problem

Cloud Build could not find Terraform configuration files.

### Cause

Incorrect:

```yaml
dir: terraform
```

### Resolution

Updated path to:

```yaml
dir: alchemyst-devops/terraform
```

---

## 3. Cloud Build Variable Escaping

### Problem

Cloud Build failed with:

```text
invalid substitution variable
```

### Cause

Using:

```bash
$API_IP
```

inside YAML.

### Resolution

Escaped variables using:

```bash
$$API_IP
```

---

## 4. Smoke Test Failure

### Problem

Smoke test failed because:

```text
terraform: not found
```

inside Cloud Build container.

### Resolution

Replaced Terraform output command with:

```bash
gcloud compute instances describe
```

---

## 5. Node.js ES Module Errors

### Problem

Node.js failed with:

```text
require is not defined in ES module scope
```

### Resolution

Migrated code to:

```javascript
import express from "express"
```

and added:

```json
"type": "module"
```

inside package.json.

---

## 6. FastAPI Environment Errors

### Problem

Python package installation failed because of:

```text
externally-managed-environment
```

### Resolution

Created Python virtual environment:

```bash
python3 -m venv venv
```

---

## 7. systemd Service Restart Failures

### Problem

Services repeatedly restarted and exited.

### Resolution

Corrected:

* ExecStart paths
* WorkingDirectory
* Node.js execution commands

---

## 8. Internal VM Communication Failure

### Problem

Caller service could not reach inference service.

### Cause

Incorrect internal IP configuration.

### Resolution

Updated API routing to use correct private IPs.

---

# When to Use This Project

This project is useful for:

* DevOps learning
* Terraform practice
* CI/CD demonstrations
* GCP infrastructure automation
* microservice deployment
* VM orchestration
* reverse proxy implementation
* startup automation
* production-style infrastructure design

---

# Future Improvements

Possible future enhancements:

* Docker containerization
* Kubernetes migration (GKE)
* HTTPS with Load Balancer
* Auto Scaling Groups
* Cloud Monitoring integration
* Secret Manager integration
* Managed databases
* Redis caching
* GPU inference deployment
* CI/CD approval gates

---

# Conclusion

This project demonstrates a complete DevOps deployment lifecycle using:

* Terraform
* Cloud Build
* Google Cloud Platform
* Compute Engine
* startup-script automation
* microservice architecture
* reverse proxy networking
* internal service communication
* zero-touch provisioning

The final system is:

* fully automated
* reproducible
* reboot persistent
* CI/CD integrated
* Terraform-driven
* production-style

and demonstrates practical cloud infrastructure engineering and DevOps automation concepts.

```
```
