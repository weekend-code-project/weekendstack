# =============================================================================
# MODULE PARAMS: Git
# =============================================================================
# Exposes parameters for Git repository cloning at workspace startup.

data "coder_parameter" "github_repo" {
  name         = "github_repo"
  display_name = "GitHub Repository URL"
  description  = "SSH or HTTPS URL to clone into /home/coder/workspace on first start (leave blank to skip)."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 30
}
