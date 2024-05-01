data "azuread_client_config" "current" {}

resource "azuread_application" "aad_app" {
  display_name = var.name
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "aad_pass" {
  application_id = azuread_application.aad_app.id
}

resource "azuread_service_principal" "self_mged_k8s_sp" {
  client_id               = azuread_application.aad_app.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}
