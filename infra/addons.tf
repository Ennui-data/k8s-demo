# Платформенные аддоны кластера. Всё версионировано, всё обновляется через plan/apply.

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.chart_versions.ingress_nginx

  wait    = true
  timeout = 600

  values = [<<-YAML
    controller:
      # Порты 80/443 ноды: kind пробрасывает их на порты хоста (см. kind.tf)
      hostPort:
        enabled: true
      nodeSelector:
        ingress-ready: "true"
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      service:
        type: ClusterIP
  YAML
  ]
}

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  namespace        = "kube-system"
  create_namespace = false

  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.chart_versions.metrics_server

  wait    = true
  timeout = 300

  values = [<<-YAML
    # kind: у kubelet самоподписанный сертификат
    args:
      - --kubelet-insecure-tls
      - --kubelet-preferred-address-types=InternalIP
  YAML
  ]
}

resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_versions.argo_cd

  wait    = true
  timeout = 900

  values = [<<-YAML
    global:
      domain: ${var.argocd_host}
    configs:
      params:
        # Внутри кластера TLS терминирует ingress-контроллер
        server.insecure: true
      cm:
        # По умолчанию Argo CD опрашивает git раз в 3 минуты. Для стенда,
        # где всё видно сразу, уменьшаем до 30 секунд.
        timeout.reconciliation: 30s
        timeout.reconciliation.jitter: 5s
    # Лишние компоненты на тестовом стенде не нужны
    dex:
      enabled: false
    notifications:
      enabled: false
    # Чарт по умолчанию тянет redis из ecr-public.aws.com, который из этого
    # региона недоступен. Берём тот же тег из Docker Hub.
    redis:
      image:
        repository: docker.io/library/redis
    server:
      ingress:
        enabled: false   # Ingress создаём сами ниже, чтобы он был виден в плане
  YAML
  ]
}

resource "helm_release" "sops_secrets_operator" {
  name      = "sops-secrets-operator"
  namespace = kubernetes_namespace_v1.sops.metadata[0].name

  # namespace и age-ключ уже созданы ресурсами выше (см. secrets.tf)
  create_namespace = false

  repository = "https://isindir.github.io/sops-secrets-operator/"
  chart      = "sops-secrets-operator"
  version    = var.chart_versions.sops_secrets_operator

  wait    = true
  timeout = 300

  values = [<<-YAML
    # Приватный age-ключ монтируется файлом, sops читает его по SOPS_AGE_KEY_FILE.
    # Сам Secret создаётся в secrets.tf.
    secretsAsFiles:
      - mountPath: /etc/sops-age-key-file
        name: sops-age-key-file
        secretName: sops-age-key-file
    extraEnv:
      - name: SOPS_AGE_KEY_FILE
        value: /etc/sops-age-key-file/key
  YAML
  ]

  depends_on = [kubernetes_secret_v1.sops_age_key_file]
}

# Ingress для UI Argo CD (обычный core-ресурс, не CRD — можно создавать из IaC)
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.argocd_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argo-cd-argocd-server"

              port {
                name = "http"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argo_cd, helm_release.ingress_nginx]
}
