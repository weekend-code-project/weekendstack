# =============================================================================
# WordPress Template Parameters
# =============================================================================

data "coder_parameter" "php_version" {
  name         = "php_version"
  display_name = "PHP Version"
  description  = "Select PHP version for WordPress"
  type         = "string"
  default      = "8.2"
  order        = 101
  option {
    name  = "PHP 8.3"
    value = "8.3"
  }
  option {
    name  = "PHP 8.2"
    value = "8.2"
  }
  option {
    name  = "PHP 8.1"
    value = "8.1"
  }
  option {
    name  = "PHP 8.0"
    value = "8.0"
  }
  option {
    name  = "PHP 7.4"
    value = "7.4"
  }
}

# WordPress setup module
module "wordpress" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/wordpress-module?ref=feature/services-cleanup"
  
  php_version    = data.coder_parameter.php_version.value
  db_host        = "mysql-${data.coder_workspace.me.name}"
  db_name        = "wordpress"
  db_user        = "wordpress"
  db_password    = random_password.db_password.result
  wp_url         = "https://${lower(data.coder_workspace.me.name)}.${var.base_domain}"
  workspace_name = data.coder_workspace.me.name
}
