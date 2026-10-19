# Приватный age-ключ для SOPS попадает в кластер как Secret и монтируется
# в sops-secrets-operator. В git его нет — только публичный ключ в .sops.yaml.
resource "kubernetes_secret_v1" "sops_age_key_file" {
  metadata {
    name      = "sops-age-key-file"
    namespace = "sops"
  }

  # Имя ключа фиксировано: оператор читает файл /etc/sops-age-key-file/key
  data = {
    key = file(pathexpand(var.sops_age_key_file))
  }

  type = "Opaque"

  depends_on = [helm_release.sops_secrets_operator]
}
