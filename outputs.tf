output "api_url" {
  description = "Public URL of the Kong API gateway (the main entry point for all Supabase APIs)"
  value       = module.supabase.api_url
}

output "dashboard_username" {
  description = "Username for the Supabase Studio basic-auth login (via Kong)"
  value       = module.supabase.dashboard_username
}

output "dashboard_password" {
  description = "Auto-generated password for the Supabase Studio basic-auth login. Retrieve with: terraform output -raw dashboard_password"
  value       = module.supabase.dashboard_password
  sensitive   = true
}
