variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access (contents of ~/.ssh/id_rsa.pub)"
  type        = string
}

variable "ssh_user" {
  description = "SSH username"
  type        = string
  default     = "ubuntu"
}

# Machine types — adjust to stay within free-tier / budget.
# inference-vm needs ≥4 GB RAM for the 270 M GGUF model.
variable "api_machine_type" {
  description = "Machine type for the API / engine VM"
  type        = string
  default     = "e2-small" # 2 vCPU, 2 GB
}

variable "caller_machine_type" {
  description = "Machine type for the caller-worker VM"
  type        = string
  default     = "e2-small" # 2 vCPU, 2 GB
}

variable "inference_machine_type" {
  description = "Machine type for the inference-worker VM (needs ≥4 GB)"
  type        = string
  default     = "e2-medium" # 2 vCPU, 4 GB
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}
