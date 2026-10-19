output "cluster_name" {
  description = "Имя кластера kind"
  value       = kind_cluster.this.name
}

output "kubeconfig_path" {
  description = "Файл kubeconfig созданного кластера"
  value       = kind_cluster.this.kubeconfig_path
}

output "argocd_url" {
  description = "UI Argo CD (через ingress-контроллер kind)"
  value       = "http://${var.argocd_host}:${var.http_host_port}"
}

output "app_urls" {
  description = "URL окружений (Host-заголовок обязателен, DNS мы не настраиваем)"
  value = {
    dev  = "http://${var.dev_host}:${var.http_host_port}"
    prod = "http://${var.prod_host}:${var.http_host_port}"
  }
}

output "argocd_admin_password_command" {
  description = "Как получить начальный пароль admin в Argo CD"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
