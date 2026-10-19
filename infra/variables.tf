variable "cluster_name" {
  description = "Имя кластера kind"
  type        = string
  default     = "k8s-demo"
}

variable "kubeconfig_path" {
  description = "Куда записать kubeconfig нового кластера"
  type        = string
  default     = "~/.kube/config"
}

variable "http_host_port" {
  description = "Порт на хосте, куда проброшен 80 порт ingress-контроллера"
  type        = number
  default     = 8080
}

variable "https_host_port" {
  description = "Порт на хосте, куда проброшен 443 порт ingress-контроллера"
  type        = number
  default     = 8443
}

variable "dev_host" {
  description = "Хост Ingress для dev-окружения"
  type        = string
  default     = "k8s-demo.dev.local"
}

variable "prod_host" {
  description = "Хост Ingress для prod-окружения"
  type        = string
  default     = "k8s-demo.prod.local"
}

variable "argocd_host" {
  description = "Хост Ingress для Argo CD"
  type        = string
  default     = "argocd.local"
}

variable "sops_age_key_file" {
  description = "Путь к файлу с приватным age-ключом (keys.txt) для sops-secrets-operator"
  type        = string
  default     = "~/.config/sops/age/keys.txt"
}

variable "chart_versions" {
  description = "Зафиксированные версии helm-чартов (стабильные релизы на момент написания)"
  type = object({
    ingress_nginx         = string
    metrics_server        = string
    argo_cd               = string
    sops_secrets_operator = string
  })
  default = {
    ingress_nginx         = "4.15.1"
    metrics_server        = "3.14.0"
    argo_cd               = "10.10.5"
    sops_secrets_operator = "0.28.1"
  }
}
