output "app_secret" {
  value     = azuread_application_password.aad_pass.value
  sensitive = true
}

output "app_id" {
  value     = azuread_application.aad_app.id
  sensitive = false
}

output "object_id" {
  value     = azuread_service_principal.self_mged_k8s_sp.object_id
  sensitive = false
}