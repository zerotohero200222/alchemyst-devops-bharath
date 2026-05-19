output "api_vm_public_ip" {
  description = "Public IP of the API gateway VM — use this for curl calls"
  value       = google_compute_instance.api_vm.network_interface[0].access_config[0].nat_ip
}

output "api_vm_internal_ip" {
  description = "Internal IP of the API / engine VM"
  value       = google_compute_instance.api_vm.network_interface[0].network_ip
}

output "caller_vm_internal_ip" {
  description = "Internal IP of the caller-worker VM"
  value       = google_compute_instance.caller_vm.network_interface[0].network_ip
}

output "inference_vm_internal_ip" {
  description = "Internal IP of the inference-worker VM"
  value       = google_compute_instance.inference_vm.network_interface[0].network_ip
}

output "curl_example" {
  description = "Example curl command once the stack is up"
  value       = "curl -s -X POST http://${google_compute_instance.api_vm.network_interface[0].access_config[0].nat_ip}/v1/chat/completions -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello, what is 2+2?\"}]}'"
}

output "ssh_api_vm" {
  description = "SSH to api-vm via IAP (no public key needed)"
  value       = "gcloud compute ssh api-vm --tunnel-through-iap --zone ${var.zone} --project ${var.project_id}"
}

output "ssh_caller_vm" {
  description = "SSH to caller-vm via IAP"
  value       = "gcloud compute ssh caller-vm --tunnel-through-iap --zone ${var.zone} --project ${var.project_id}"
}

output "ssh_inference_vm" {
  description = "SSH to inference-vm via IAP"
  value       = "gcloud compute ssh inference-vm --tunnel-through-iap --zone ${var.zone} --project ${var.project_id}"
}
output "api_public_ip" {
  value = google_compute_instance.api_vm.network_interface[0].access_config[0].nat_ip
}
