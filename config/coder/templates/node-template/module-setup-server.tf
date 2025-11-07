# Node-template override for shared setup-server glue
# Defines exposed_ports_list for use by Traefik and preview-link modules,
# without exposing static-site parameters in the UI.

locals {
  exposed_ports_list = module.node_server.server_ports
}
