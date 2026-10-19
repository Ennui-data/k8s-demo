# Namespace и Secret для age-ключа создаются ДО helm-релиза оператора.
#
# Почему не отдать namespace чарту (create_namespace = true): оператор монтирует
# ключ из Secret как том. Если Secret ещё не создан, Pod навсегда застревает в
# ContainerCreating, а helm с wait=true всё это время ждёт готовности Pod —
# получается взаимная блокировка. Поэтому порядок задаём явно: namespace →
# Secret → релиз.
resource "kubernetes_namespace_v1" "sops" {
  metadata {
    name = "sops"

    labels = {
      "app.kubernetes.io/part-of" = "sops-secrets-operator"
    }
  }
}

# Приватный age-ключ для SOPS попадает в кластер как Secret и монтируется
# в sops-secrets-operator. В git его нет — только публичный ключ в .sops.yaml.
resource "kubernetes_secret_v1" "sops_age_key_file" {
  metadata {
    name      = "sops-age-key-file"
    namespace = kubernetes_namespace_v1.sops.metadata[0].name
  }

  # Имя ключа фиксировано: оператор читает файл /etc/sops-age-key-file/key
  data = {
    key = file(pathexpand(var.sops_age_key_file))
  }

  type = "Opaque"
}
