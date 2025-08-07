#!/bin/bash

# Supabase Stack Health Check Script
# Tests all core Supabase service endpoints for reachability and basic configuration

set -e

echo "=============================================="
echo "    Supabase Stack Health Check"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check HTTP endpoint
check_http_endpoint() {
    local service_name="$1"
    local url="$2"
    local expected_codes="$3"
    local auth_header="$4"
    
    echo -n "Checking ${service_name} (${url})... "
    
    if command -v curl >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 -H "$auth_header" "$url" 2>/dev/null || echo "000")
        else
            response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")
        fi
        
        if echo "$expected_codes" | grep -q "$response"; then
            echo -e "${GREEN}OK${NC} (HTTP $response)"
            return 0
        else
            echo -e "${RED}FAIL${NC} (HTTP $response)"
            return 1
        fi
    else
        echo -e "${YELLOW}SKIP${NC} (curl not available)"
        return 2
    fi
}

# Function to check TCP port
check_tcp_port() {
    local service_name="$1"
    local host="$2"
    local port="$3"
    
    echo -n "Checking ${service_name} TCP (${host}:${port})... "
    
    if command -v nc >/dev/null 2>&1; then
        if nc -z "$host" "$port" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
            return 0
        else
            echo -e "${RED}FAIL${NC}"
            return 1
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout 5 telnet "$host" "$port" >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
            return 0
        else
            echo -e "${RED}FAIL${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}SKIP${NC} (nc/telnet not available)"
        return 2
    fi
}

# Function to check Docker container status
check_container_status() {
    echo -e "${BLUE}Docker Container Status:${NC}"
    if command -v docker >/dev/null 2>&1; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=supabase-"
        echo ""
    else
        echo -e "${YELLOW}Docker not available${NC}"
        echo ""
    fi
}

# Load environment variables if .env exists
if [ -f "docker/.env" ]; then
    source docker/.env
    echo -e "${BLUE}Loaded environment from docker/.env${NC}"
elif [ -f ".env" ]; then
    source .env
    echo -e "${BLUE}Loaded environment from .env${NC}"
else
    echo -e "${YELLOW}No .env file found, using defaults${NC}"
fi

echo ""

# Set default ports if not specified in environment
KONG_HTTP_PORT=${KONG_HTTP_PORT:-8000}
POSTGRES_PORT=${POSTGRES_PORT:-5432}

# Set up auth headers if keys are available
ANON_AUTH_HEADER=""
SERVICE_AUTH_HEADER=""
if [ -n "$ANON_KEY" ]; then
    ANON_AUTH_HEADER="Authorization: Bearer $ANON_KEY"
fi
if [ -n "$SERVICE_ROLE_KEY" ]; then
    SERVICE_AUTH_HEADER="Authorization: Bearer $SERVICE_ROLE_KEY"
fi

# Check container status first
check_container_status

# Track results
total_checks=0
passed_checks=0
failed_checks=0
skipped_checks=0

echo -e "${BLUE}Testing Service Endpoints:${NC}"
echo ""

# Test PostgreSQL Database (port check only)
total_checks=$((total_checks + 1))
if check_tcp_port "PostgreSQL Database" "localhost" "$POSTGRES_PORT"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test Kong API Gateway
total_checks=$((total_checks + 1))
if check_http_endpoint "Kong API Gateway" "http://localhost:$KONG_HTTP_PORT" "200 404 502"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test Kong Admin API (if exposed)
if [ "${KONG_HTTP_PORT}" = "8000" ]; then
    total_checks=$((total_checks + 1))
    if check_http_endpoint "Kong Admin API" "http://localhost:8001" "200 404"; then
        passed_checks=$((passed_checks + 1))
    else
        failed_checks=$((failed_checks + 1))
    fi
fi

# Test PostgREST API (through Kong) - with anon key
total_checks=$((total_checks + 1))
if check_http_endpoint "PostgREST API" "http://localhost:$KONG_HTTP_PORT/rest/v1/" "200 404" "$ANON_AUTH_HEADER"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test GoTrue Auth API (through Kong) - health endpoint should work without auth
total_checks=$((total_checks + 1))
if check_http_endpoint "GoTrue Auth API" "http://localhost:$KONG_HTTP_PORT/auth/v1/health" "200 404"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test Storage API (through Kong) - with service role key
total_checks=$((total_checks + 1))
if check_http_endpoint "Storage API" "http://localhost:$KONG_HTTP_PORT/storage/v1/health" "200 404" "$SERVICE_AUTH_HEADER"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test Supabase Studio (if exposed)
total_checks=$((total_checks + 1))
if check_http_endpoint "Supabase Studio" "http://localhost:8082" "200 404"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test Meta API (if exposed)
total_checks=$((total_checks + 1))
if check_http_endpoint "Meta API" "http://localhost:5555/health" "200 404"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test Realtime (if exposed)
total_checks=$((total_checks + 1))
if check_http_endpoint "Realtime API" "http://localhost:4000/api/health" "200 404"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test Edge Functions (if exposed)  
total_checks=$((total_checks + 1))
if check_http_endpoint "Edge Functions" "http://localhost:9000/_internal/health" "200 404"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

# Test Analytics/Logflare (if exposed)
total_checks=$((total_checks + 1))
if check_http_endpoint "Analytics API" "http://localhost:4000/health" "200 404"; then
    passed_checks=$((passed_checks + 1))
else
    failed_checks=$((failed_checks + 1))
fi

echo ""
echo "=============================================="
echo -e "${BLUE}Health Check Summary:${NC}"
echo "=============================================="
echo -e "Total checks: ${total_checks}"
echo -e "Passed: ${GREEN}${passed_checks}${NC}"
echo -e "Failed: ${RED}${failed_checks}${NC}"
echo -e "Skipped: ${YELLOW}${skipped_checks}${NC}"

# If we have auth keys, test a simple authenticated API call
if [ -n "$ANON_KEY" ] && [ $passed_checks -gt 0 ]; then
    echo ""
    echo -e "${BLUE}Testing Authenticated API Access:${NC}"
    echo -n "Testing PostgREST with anon key... "
    
    if command -v curl >/dev/null 2>&1; then
        auth_response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $ANON_KEY" -H "apikey: $ANON_KEY" "http://localhost:$KONG_HTTP_PORT/rest/v1/" 2>/dev/null || echo "000")
        if echo "200 201 202" | grep -q "${auth_response: -3}"; then
            echo -e "${GREEN}OK${NC} - Authentication working"
        else
            echo -e "${YELLOW}PARTIAL${NC} - API accessible but may need schema/tables"
        fi
    else
        echo -e "${YELLOW}SKIP${NC} (curl not available)"
    fi
fi

if [ $failed_checks -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All checks passed! Supabase stack is healthy.${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some checks failed. Please review the output above.${NC}"
    echo ""
    echo -e "${YELLOW}Common troubleshooting steps:${NC}"
    echo "1. Check if containers are running: docker ps"
    echo "2. Check container logs: docker logs <container-name>"
    echo "3. Verify port mappings in docker-compose.yml"
    echo "4. Ensure .env file has correct configuration"
    exit 1
fi
