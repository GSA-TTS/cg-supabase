output "api_url" {
  description = "Public URL of the Kong API gateway (the main entry point for all Supabase APIs)"
  value       = local.api_url
}

output "dashboard_username" {
  description = "Username for the Supabase Studio basic-auth login (via Kong)"
  value       = local.api_username
}

output "dashboard_password" {
  description = "Auto-generated password for the Supabase Studio basic-auth login. Retrieve with: terraform output -raw dashboard_password"
  value       = random_password.dashboard_password.result
  sensitive   = true
}

output "anon_key" {
  description = "Anon JWT used by Kong key-auth and public Supabase clients. Retrieve with: terraform output -raw anon_key"
  value       = local.effective_anon_key
  sensitive   = true
}
