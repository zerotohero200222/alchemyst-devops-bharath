terraform {
  backend "gcs" {
    bucket = "eternal-bruin-489005-u2-tf-state"
    prefix = "terraform/state"
  }
}