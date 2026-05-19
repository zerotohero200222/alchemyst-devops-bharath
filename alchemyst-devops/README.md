# Alchemyst DevOps Assignment — Cloud Cartographer

Distributed inference stack: **gemma-3-270m** (GGUF Q8) running behind a worker mesh on GCP, exposed as a JSON HTTP API. Workers live in a private subnet and communicate over RPC; only the API gateway has a public IP.

---

## Architecture

```
                          ┌─────────────────────────────────────────────────┐
                          │             GCP VPC  (10.0.0.0/16)              │
                          │                                                  │
   Internet               │  public-subnet (10.0.0.0/24)                    │
      │                   │  ┌──────────────────────────────────────┐        │
      │  :80 (HTTP)       │  │  api-vm   (e2-small)                 │        │
      └──────────────────►│  │  • nginx  :80  ──► iii-http  :3111  │        │
                          │  │  • iii engine   (WS bus  :49134)     │        │
                          │  └──────────────────┬───────────────────┘        │
                          │                     │ ws://10.0.0.x:49134        │
                          │  private-subnet (10.0.1.0/24)  (internal only)   │
                          │                     │                            │
                          │       ┌─────────────┼──────────────┐             │
                          │       ▼             │              ▼             │
                          │  ┌────────────┐     │   ┌────────────────────┐  │
                          │  │ caller-vm  │     │   │   inference-vm     │  │
                          │  │ (e2-small) │─────┘   │   (e2-medium 4GB)  │  │
                          │  │ caller-    │  RPC     │   inference-       │  │
                          │  │ worker     │◄────────►│   worker           │  │
                          │  │ TypeScript │          │   Python + GGUF    │  │
                          │  └────────────┘          └────────────────────┘  │
                          │                                                  │
                          └─────────────────────────────────────────────────┘
```

### RPC call flow

```
curl POST /v1/chat/completions
  → nginx (api-vm :80)
  → iii-http (api-vm :3111)
  → http::run_inference_over_http  (caller-vm, TypeScript)
  → inference::get_response        (caller-vm, TypeScript)
  → inference::run_inference       (inference-vm, Python)
  → gemma-3-270m GGUF model
  → response bubbles back up the chain
```

All RPC hops travel over the private subnet via WebSocket through the iii engine on api-vm. No worker is reachable from the public internet.

---

## Repository layout

```
alchemyst-devops/
├── terraform/
│   ├── main.tf                      # VPC, subnets, firewall, 3 VMs
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example     # copy → terraform.tfvars and fill in
│   └── startup-scripts/
│       ├── api-vm.sh                # installs iii engine + nginx
│       ├── caller-vm.sh             # installs Node.js + caller-worker
│       └── inference-vm.sh          # installs Python + model + inference-worker
├── workers/
│   ├── caller-worker/               # TypeScript source (from quickstart)
│   └── inference-worker/            # Python source (from quickstart)
├── config/
│   └── engine-config.yaml           # iii engine config (no remote worker paths)
├── systemd/
│   └── units.conf                   # reference systemd unit snippets
├── nginx/
│   └── iii-api.conf                 # nginx reverse-proxy config
└── README.md
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | ≥ 1.6 | https://developer.hashicorp.com/terraform/install |
| gcloud CLI | any | https://cloud.google.com/sdk/docs/install |
| A GCP project | — | https://console.cloud.google.com |

Enable these GCP APIs on your project:

```bash
gcloud services enable compute.googleapis.com iap.googleapis.com
```

---

## Deploy from scratch

### 1 — Configure credentials

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2 — Create `terraform.tfvars`

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
project_id     = "your-gcp-project-id"
ssh_public_key = "ssh-rsa AAAA..."   # contents of ~/.ssh/id_rsa.pub
ssh_user       = "ubuntu"
```

### 3 — Apply

```bash
terraform init
terraform plan   # review before applying
terraform apply  # type "yes" when prompted
```

Terraform prints the public IP of `api-vm` when it finishes:

```
Outputs:
  api_vm_public_ip = "34.x.x.x"
  curl_example     = "curl -s -X POST http://34.x.x.x/v1/chat/completions ..."
```

### 4 — Wait for workers to come online

On first boot, `inference-vm` downloads the model (~270 MB) and installs Python dependencies. This typically takes **5–10 minutes**. You can watch progress:

```bash
# SSH in via IAP (no need to expose port 22 publicly)
gcloud compute ssh inference-vm --tunnel-through-iap --zone us-central1-a
journalctl -u inference-worker -f
```

Once you see `inference-worker registered and listening` the stack is ready.

---

## API reference

### `POST /v1/chat/completions`

**Request**

```json
{
  "messages": [
    { "role": "system",    "content": "You are a helpful assistant." },
    { "role": "user",      "content": "What is 2 + 2?" }
  ],
  "max_new_tokens": 256
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `messages` | array | ✅ | OpenAI-style message array |
| `max_new_tokens` | integer | ❌ | Max tokens to generate (default: 512) |

**Response**

```json
{
  "result": {
    "response": "2 + 2 = 4.",
    "model": "ggml-org/gemma-3-270m-GGUF",
    "success": "Connected two workers across VMs — interoperating seamlessly over the private subnet."
  }
}
```

---

## Exact `curl` example

Replace `34.x.x.x` with the IP from `terraform output api_vm_public_ip`:

```bash
curl -s -X POST http://34.x.x.x/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "Explain what a VPC is in one sentence." }
    ]
  }' | jq .
```

**Sample response:**

```json
{
  "result": {
    "response": "A Virtual Private Cloud (VPC) is an isolated network within a public cloud provider that lets you define your own IP ranges, subnets, and routing rules.",
    "model": "ggml-org/gemma-3-270m-GGUF",
    "success": "Connected two workers across VMs — interoperating seamlessly over the private subnet."
  }
}
```

---

## Tear down

```bash
terraform destroy   # destroys all VMs, VPC, firewall rules, NAT, router
```

---

## Debugging

```bash
# Check iii engine on api-vm
gcloud compute ssh api-vm --tunnel-through-iap --zone us-central1-a
journalctl -u iii-engine -f

# Check caller-worker on caller-vm
gcloud compute ssh caller-vm --tunnel-through-iap --zone us-central1-a
journalctl -u caller-worker -f

# Check inference-worker on inference-vm
gcloud compute ssh inference-vm --tunnel-through-iap --zone us-central1-a
journalctl -u inference-worker -f

# Quick connectivity test from caller-vm to engine
nc -zv <api-vm-internal-ip> 49134

# Test nginx → iii-http pipeline directly on api-vm
curl -s http://localhost/healthz
curl -s -X POST http://localhost/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"ping"}]}'
```

---

## What I would harden before putting this in production

**Network layer**

- Replace the ephemeral external IP on `api-vm` with a static IP and put a load balancer (GCP HTTPS LB) in front of it. This gives you a stable endpoint, TLS termination, DDoS protection via Cloud Armor, and health-check-driven failover.
- Restrict the `allow-internal` firewall rule to only the specific ports actually used — port 49134 for the iii engine WS bus, nothing else. Right now it's all-open within the VPC, which is fine for a prototype but too permissive for production.
- Enable VPC Flow Logs on both subnets to get visibility into lateral movement if a VM is ever compromised.

**Authentication and secrets**

- Put the HTTP API behind an API key or OAuth 2.0 via Cloud Endpoints or Apigee. Right now any IP can POST to the inference endpoint.
- Use GCP Secret Manager for any credentials (HuggingFace tokens, etc.) instead of baking them into startup scripts or environment variables.
- Lock down IAM: each VM's service account should have the minimum scopes needed. The current `cloud-platform` scope is fine for development but should be replaced with scoped roles.

**Reliability**

- The iii engine on `api-vm` is currently a single point of failure. In production I'd either run two engine nodes with a shared Redis-backed queue, or migrate to a fully managed message bus (Pub/Sub) so the engine can be stateless and horizontally scaled.
- Add a startup dependency check that waits until the model worker has registered before nginx starts accepting traffic. Right now there's a window after first boot where nginx returns errors.

**Observability**

- Route the iii observability exporter to Cloud Monitoring (or Prometheus + Grafana) instead of in-memory. Set up alerts on inference latency p95 and error rate.
- Structured logs (JSON) from all three services with a correlation ID threaded through the RPC chain, so you can trace a single user request end-to-end.

---

## What I'd do differently if the model were 100× larger

A 100× scale-up (e.g., Gemma-27B or similar, ~27 GB in FP16) changes almost everything about the deployment:

**Compute**

- Swap `inference-vm` for an A100 or L4 GPU instance (GCP `a2-highgpu-1g` or `g2-standard-8`). The model won't fit in CPU RAM, and even if it did, inference at CPU speed would be unusable.
- Explore tensor parallelism across multiple GPUs with vLLM or TensorRT-LLM rather than running a single GGUF process.

**Model serving**

- Replace the raw `transformers.generate()` call with a purpose-built inference server — vLLM, Triton, or TGI — that handles batching, KV cache management, continuous batching, and streaming. Single-request `generate()` is a bottleneck at any real traffic volume.
- Serve the model over an internal OpenAI-compatible endpoint (vLLM does this natively) so the `caller-worker` just makes an HTTP call rather than an RPC hop — simpler, and easier to swap implementations.

**Storage and startup time**

- Store the model weights on a persistent disk (or GCS bucket mounted via `gcsfuse`) rather than downloading on every cold start. A 27 GB download at boot is a 15-minute delay; unacceptable in a production auto-scaling scenario.
- Use a managed model registry and pre-warm instances during off-peak hours.

**Infrastructure topology**

- Separate the inference tier into its own managed instance group with autoscaling on GPU utilization, behind an internal load balancer. The `caller-worker` sends requests to the ILB, not to a specific IP.
- Add a request queue (Pub/Sub or Redis Streams) between the caller and inference layers to absorb traffic spikes and enable async inference with webhook / polling responses.
