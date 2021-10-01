// ----------------------------------------------------------------------------
// Create and configure the Kubernetes cluster
//
// https://www.terraform.io/docs/providers/google/r/container_cluster.html
// ----------------------------------------------------------------------------
locals {
  cluster_oauth_scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/compute",
    "https://www.googleapis.com/auth/devstorage.full_control",
    "https://www.googleapis.com/auth/service.management",
    "https://www.googleapis.com/auth/servicecontrol",
    "https://www.googleapis.com/auth/logging.admin",
    "https://www.googleapis.com/auth/monitoring",

    #Changed https://www.googleapis.com/auth/logging.write to https://www.googleapis.com/auth/logging.admin
    #Will change this after testing successful env deployment into existing cluster
  ]
}
resource "google_container_cluster" "jx_cluster" {
  provider                = google-beta
  name                    = var.cluster_name
  description             = ""
  location                = var.cluster_location
  network                 = var.cluster_network
  subnetwork              = var.cluster_subnetwork
  enable_kubernetes_alpha = var.enable_kubernetes_alpha
  enable_legacy_abac      = var.enable_legacy_abac
  enable_shielded_nodes   = var.enable_shielded_nodes
  initial_node_count      = var.min_node_count
  logging_service         = var.logging_service
  monitoring_service      = var.monitoring_service


  //----added by david-----

  #node_version            = var.node_version
  #min_master_version      = var.min_master_version
  #cluster_ipv4_cidr       = var.cluster_ipv4_cidr

  //-----------------------

  // should disable master auth
  master_auth {
    username = ""
    password = ""
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  release_channel {
    channel = var.release_channel
  }

  workload_identity_config {
    identity_namespace = "${var.gcp_project}.svc.id.goog"
  }

  resource_labels = var.resource_labels

  cluster_autoscaling {
    enabled = true

    auto_provisioning_defaults {
      oauth_scopes = local.cluster_oauth_scopes
    }

    resource_limits {
      resource_type = "cpu"
      minimum       = ceil(var.min_node_count * var.machine_types_cpu[var.node_machine_type])
      maximum       = ceil(var.max_node_count * var.machine_types_cpu[var.node_machine_type])
    }

    resource_limits {
      resource_type = "memory"
      minimum       = ceil(var.min_node_count * var.machine_types_memory[var.node_machine_type])
      maximum       = ceil(var.max_node_count * var.machine_types_memory[var.node_machine_type])
    }
  }

  node_config {
    preemptible  = var.node_preemptible
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size
    disk_type    = var.node_disk_type

    oauth_scopes = local.cluster_oauth_scopes

    workload_metadata_config {
      node_metadata = "GKE_METADATA_SERVER"
    }

  }
}


module "jx-health" {
  count  = var.jx2 && var.kuberhealthy ? 0 : 1
  source = "github.com/jenkins-x/terraform-jx-health?ref=main"

  depends_on = [
    google_container_cluster.jx_cluster
  ]
}


// ----------------------------------------------------------------------------
// Add main Jenkins X Kubernetes namespace
//
// https://www.terraform.io/docs/providers/kubernetes/r/namespace.html
// ----------------------------------------------------------------------------
resource "kubernetes_namespace" "jenkins_x_namespace" {
  count = var.jx2 ? 1 : 0
  metadata {
    name = var.jenkins_x_namespace
  }
  lifecycle {
    ignore_changes = [
      metadata[0].labels,
      metadata[0].annotations,
    ]
  }
  depends_on = [
    google_container_cluster.jx_cluster
  ]
}

// ----------------------------------------------------------------------------
// Add the Terraform generated jx-requirements.yml to a configmap so it can be
// sync'd with the Git repository
//
// https://www.terraform.io/docs/providers/kubernetes/r/namespace.html
// ----------------------------------------------------------------------------
resource "kubernetes_config_map" "jenkins_x_requirements" {
  count = var.jx2 ? 0 : 1
  metadata {
    name      = "terraform-jx-requirements"
    namespace = "default"
  }
  data = {
    "jx-requirements.yml" = var.content
  }
  depends_on = [
    google_container_cluster.jx_cluster
  ]
}

resource "helm_release" "jx-git-operator" {
  count = var.jx2 || var.jx_git_url == "" ? 0 : 1

  provider         = helm
  name             = "jx-git-operator"
  chart            = "jx-git-operator"
  namespace        = "jx-git-operator"
  repository       = "https://jenkins-x-charts.github.io/repo"
  version          = var.jx_git_operator_version
  create_namespace = true

  set {
    name  = "bootServiceAccount.enabled"
    value = true
  }
  set {
    name  = "bootServiceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = "${var.cluster_name}-boot@${var.gcp_project}.iam.gserviceaccount.com"
  }
  set {
    name  = "env.NO_RESOURCE_APPLY"
    value = true
  }
  set {
    name  = "url"
    value = var.jx_git_url
  }
  set {
    name  = "username"
    value = var.jx_bot_username
  }
  set {
    name  = "password"
    value = var.jx_bot_token
  }

  lifecycle {
    ignore_changes = all
  }
  depends_on = [
    google_container_cluster.jx_cluster
  ]
}

//----------added by david-----------------

resource "kubernetes_daemonset" "ip-masq-daemonset"{
  metadata {
    name = "ip-masq-agent"
    namespace = "kube-system"
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "ip-masq-agent"
      }
    }

    template {
      metadata  {
        labels = {
          k8s-app = "ip-masq-agent"
        }
      }

      spec {
        host_network = true
        container {
          name = "ip-masq-agent"
          image = "gcr.io/google-containers/ip-masq-agent-amd64:v2.0.0"
          security_context {
            privileged = false
            capabilities {
              add = [
                "NET_ADMIN",
                "NET_RAW"
              ]
            }
          }
          volume_mount {
              name = "config"
              mount_path = "/etc/config"
          }
        }
        volume {
          name = "config"
          config_map {
            name = "ip-masq-agent"
            optional = false
            items {
                key = "config"
                path = "ip-masq-agent"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_config_map" "masq-ip-cm"{
  metadata {
    name          = "ip-masq-agent"
    namespace     = "kube-system"
  }

  data = {
    "config"      = "nonMasqueradeCIDRs:\n  - 10.56.0.0/14\nresyncInterval: 60s"
  }
}

//------------------------------------
