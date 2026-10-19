terraform {
  required_version = ">= 1.8.0"

  # Версии провайдеров зафиксированы (см. также .terraform.lock.hcl).
  # Файл написан под OpenTofu, HCL совместим и с Terraform.
  required_providers {
    kind = {
      source  = "registry.terraform.io/tehcyx/kind"
      version = "0.9.0"
    }
    kubernetes = {
      source  = "registry.terraform.io/hashicorp/kubernetes"
      version = "3.3.0"
    }
    helm = {
      source  = "registry.terraform.io/hashicorp/helm"
      version = "3.3.0"
    }
  }

  # State локальный: в этом демо и человек, и self-hosted раннер работают на одной машине.
  # Путь задаётся при init: tofu init -backend-config=path=$HOME/.local/share/tofu/k8s-demo.tfstate
  # В команде вместо этого — удалённый backend (S3/MinIO) с блокировкой.
  backend "local" {}
}
