// ----------------------------------------------------------------------------
// Create and configure the Kubernetes cluster
//
// https://www.terraform.io/docs/providers/google/r/container_cluster.html
// ----------------------------------------------------------------------------


resource "google_container_cluster" "jx_cluster" {
  provider                = google-beta
  name                    = var.cluster_name
  #description             = "jenkins-x cluster"
  #location                = var.cluster_location
  #network                 = var.cluster_network
  #subnetwork              = var.cluster_subnetwork
  #enable_kubernetes_alpha = var.enable_kubernetes_alpha
  #enable_legacy_abac      = var.enable_legacy_abac
  #enable_shielded_nodes   = var.enable_shielded_nodes
  #initial_node_count      = var.min_node_count
  #logging_service         = var.logging_service
  #monitoring_service      = var.monitoring_service
}

