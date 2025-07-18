# Supabase Terraform Deployment TODO List

## 🔥 Critical Issues (Deployment Blockers)

### 1. Fix Variable Configuration
- [ ] Add missing `cf_user` and `cf_password` variables to root `variables.tf`
- [ ] Fix variable passing between root and supabase module
- [ ] Add data source to get `cf_space_id` dynamically
- [ ] Remove unused variables from module interfaces

### 2. Create Kong Preparation Script
- [ ] Create `supabase/kong/prepare-kong.sh` script
- [ ] Implement Kong binary download and configuration logic
- [ ] Test script execution in Cloud Foundry environment

### 3. Enable Auth Service
- [ ] Uncomment and configure the auth service in `auth.tf`
- [ ] Fix environment variables for GoTrue
- [ ] Update Kong configuration to properly route to auth service
- [ ] Add required network policies for auth service

## ⚠️ High Priority (Functionality Issues)

### 4. Network Policies
- [ ] Remove auth app references from network policies until auth is working
- [ ] Verify all required service-to-service communications are allowed
- [ ] Test internal routing between services

### 5. Environment Configuration
- [ ] Generate real JWT secrets using Supabase CLI or JWT generator
- [ ] Replace placeholder values in `.env` file
- [ ] Document secret generation process in README

### 6. Cloud Foundry Space Management
- [ ] Add data source to automatically discover `cf_space_id`
- [ ] Verify organization and space exist before deployment
- [ ] Add proper error handling for missing CF resources

## 📋 Medium Priority (Integration & Testing)

### 7. External Dependencies Integration
- [ ] Integrate HTTPS proxy configuration (currently commented out)
- [ ] Add log drain service integration
- [ ] Consider making external S3 injection optional

### 8. Service Health & Monitoring
- [ ] Verify health check endpoints for all services
- [ ] Add proper startup dependencies between services
- [ ] Configure service timeouts appropriately

### 9. Security Hardening
- [ ] Use user-provided service instances (UPSI) for secrets
- [ ] Implement proper secret rotation mechanism
- [ ] Review and harden Kong security configuration

## 🔧 Low Priority (Optimization & Maintenance)

### 10. Resource Optimization
- [ ] Review memory and disk quotas for production use
- [ ] Optimize instance counts based on expected load
- [ ] Consider auto-scaling configuration

### 11. Documentation
- [ ] Update README with actual deployment steps
- [ ] Document troubleshooting common issues
- [ ] Add architecture decision records (ADRs)

### 12. Development Experience
- [ ] Add Terraform validation in CI/CD
- [ ] Create development vs production configurations
- [ ] Add automated testing for deployed services

### 13. Advanced Features
- [ ] Add support for custom domains
- [ ] Implement backup and disaster recovery
- [ ] Add monitoring and alerting integration

## 🚀 Quick Wins (Can be done immediately)

### A. Fix Immediate Syntax Issues
```bash
# Add to root variables.tf
variable "cf_user" {
  type        = string
  description = "cloud.gov deployer account user"
}

variable "cf_password" {
  type        = string
  description = "cloud.gov deployer account password"
  sensitive   = true
}
```

### B. Create Basic Kong Script
```bash
# Create supabase/kong/prepare-kong.sh
#!/bin/bash
# Basic Kong preparation script
echo '{"path": "kong.zip"}' | jq -r
```

### C. Update Environment Variables
```bash
# Generate real secrets
openssl rand -base64 32  # for JWT_SECRET
# Use Supabase CLI: supabase gen keys
```

## Progress Tracking

- [ ] **Phase 1**: Critical Issues Fixed (Target: Day 1)
- [ ] **Phase 2**: High Priority Completed (Target: Day 3)
- [ ] **Phase 3**: Medium Priority Features (Target: Week 1)
- [ ] **Phase 4**: Production Ready (Target: Week 2)

## Success Criteria

✅ **Deployment Success**: `terraform apply` completes without errors
✅ **Service Health**: All services respond to health checks
✅ **API Gateway**: Kong routes requests to backend services
✅ **Authentication**: Auth service accepts and validates tokens
✅ **Database**: All services can connect to PostgreSQL
✅ **Storage**: File upload/download works through S3
✅ **Admin Interface**: Studio dashboard accessible and functional

## Notes

- Focus on getting a minimal working deployment first
- Add features incrementally after core functionality works
- Test each service individually before testing integration
- Keep external dependencies optional until core services are stable
