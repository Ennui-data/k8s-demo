# Кластер kind как код: именно apply создаёт кластер, а не скрипт с kubectl.
resource "kind_cluster" "this" {
  name            = var.cluster_name
  wait_for_ready  = true
  kubeconfig_path = pathexpand(var.kubeconfig_path)

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Метка, по которой ingress-nginx выбирает ноду (у kind она одна).
      kubeadm_config_patches = [
        <<-PATCH
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        PATCH
      ]

      # Порты ingress-контроллера внутри ноды -> порты на хосте.
      extra_port_mappings {
        container_port = 80
        host_port      = var.http_host_port
      }

      extra_port_mappings {
        container_port = 443
        host_port      = var.https_host_port
      }
    }
  }
}
