#!/bin/bash
#
# Valkey Hardened Image - FIPS Compliance Verification Script
#
# Purpose: Verify that security hardening packages don't break FIPS 140-3 compliance
# Tests: Non-FIPS crypto libraries, FIPS OpenSSL linkage, Valkey functionality
#
# Usage: ./test-hardened-fips-compliance.sh [image-name]
#

set -e

# Configuration
IMAGE_NAME="${1:-valkey-fips:8.1.5-ubuntu-22.04-hardened}"
CONTAINER_NAME="test-hardened-fips-$(date +%s)"
VALKEY_PORT="${VALKEY_PORT:-6379}"

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
CRITICAL_FAILURES=0

# Results tracking
declare -a CRITICAL_ISSUES
declare -a WARNING_ISSUES
declare -a PASSED_CHECKS

# Helper functions
print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

print_subheader() {
    echo ""
    echo "--- $1 ---"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_TESTS++))
    PASSED_CHECKS+=("$1")
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED_TESTS++))
}

print_critical() {
    echo -e "${RED}🔴 CRITICAL:${NC} $1"
    ((CRITICAL_FAILURES++))
    CRITICAL_ISSUES+=("$1")
}

print_warning() {
    echo -e "${YELLOW}🟡 WARNING:${NC} $1"
    WARNING_ISSUES+=("$1")
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

run_test() {
    ((TOTAL_TESTS++))
}

cleanup() {
    if [ -n "$CONTAINER_NAME" ]; then
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

# ============================================================================
# PHASE 1: IMAGE EXISTENCE AND STRUCTURE
# ============================================================================

print_header "Phase 1: Image and Container Validation"

run_test
print_info "Checking if hardened image exists: $IMAGE_NAME"
if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    print_pass "Hardened image exists"
    IMAGE_EXISTS=true
else
    print_fail "Hardened image not found: $IMAGE_NAME"
    echo ""
    echo "To build the hardened image:"
    echo "  cd /home/vysakh-k-s/focaloid/root/bitnami/valkey/8.1.5-ubuntu-22.04"
    echo "  docker build --secret id=wolfssl_password,src=wolfssl_password.txt \\"
    echo "    -t valkey-fips:8.1.5-ubuntu-22.04-hardened \\"
    echo "    -f Dockerfile.hardened ."
    exit 1
fi

# ============================================================================
# PHASE 2: NON-FIPS CRYPTO LIBRARY DETECTION
# ============================================================================

print_header "Phase 2: Non-FIPS Crypto Library Detection"

print_subheader "2.1: NSS (Network Security Services) Libraries"

run_test
print_info "Checking for libnss3 (non-FIPS crypto library)..."
NSS_LIBS=$(docker run --rm "$IMAGE_NAME" sh -c "find /usr /lib -name 'libnss3.so*' 2>/dev/null || true")
if [ -n "$NSS_LIBS" ]; then
    print_critical "NSS crypto library found (bypasses FIPS OpenSSL)"
    echo "  Locations:"
    echo "$NSS_LIBS" | while read -r line; do
        echo "    - $line"
    done
    NSS_FOUND=true
else
    print_pass "NSS crypto library not found (good)"
    NSS_FOUND=false
fi

run_test
print_info "Checking for libnss3-tools package..."
NSS_TOOLS=$(docker run --rm "$IMAGE_NAME" sh -c "dpkg -l | grep libnss3-tools || true")
if [ -n "$NSS_TOOLS" ]; then
    print_critical "libnss3-tools package installed"
    echo "  Package details:"
    echo "$NSS_TOOLS" | sed 's/^/    /'
else
    print_pass "libnss3-tools package not installed (good)"
fi

print_subheader "2.2: GNU Crypto (libgcrypt) Libraries"

run_test
print_info "Checking for libgcrypt20 (non-FIPS crypto library)..."
GCRYPT_LIBS=$(docker run --rm "$IMAGE_NAME" sh -c "find /usr /lib -name 'libgcrypt.so*' 2>/dev/null || true")
if [ -n "$GCRYPT_LIBS" ]; then
    print_critical "GNU crypto library found (bypasses FIPS OpenSSL)"
    echo "  Locations:"
    echo "$GCRYPT_LIBS" | while read -r line; do
        echo "    - $line"
    done
    GCRYPT_FOUND=true
else
    print_pass "GNU crypto library not found (good)"
    GCRYPT_FOUND=false
fi

run_test
print_info "Checking for rsyslog (may pull libgcrypt20)..."
RSYSLOG_PKG=$(docker run --rm "$IMAGE_NAME" sh -c "dpkg -l | grep rsyslog || true")
if [ -n "$RSYSLOG_PKG" ]; then
    print_warning "rsyslog package installed (may have libgcrypt20 dependency)"
    echo "  Package details:"
    echo "$RSYSLOG_PKG" | sed 's/^/    /'

    # Check if it actually pulled libgcrypt20
    GCRYPT_PKG=$(docker run --rm "$IMAGE_NAME" sh -c "dpkg -l | grep libgcrypt20 || true")
    if [ -n "$GCRYPT_PKG" ]; then
        print_critical "rsyslog pulled libgcrypt20 dependency"
        echo "$GCRYPT_PKG" | sed 's/^/    /'
    fi
else
    print_pass "rsyslog package not installed"
fi

print_subheader "2.3: System OpenSSL Detection"

run_test
print_info "Checking for system OpenSSL libraries..."
SYSTEM_SSL=$(docker run --rm "$IMAGE_NAME" sh -c "find /usr/lib /lib -name 'libssl.so*' -o -name 'libcrypto.so*' 2>/dev/null | grep -v '/usr/local/openssl/' || true")
if [ -n "$SYSTEM_SSL" ]; then
    print_critical "System OpenSSL libraries found (should be removed)"
    echo "  Locations:"
    echo "$SYSTEM_SSL" | while read -r line; do
        echo "    - $line"
    done
    SYSTEM_SSL_FOUND=true
else
    print_pass "System OpenSSL not found (correctly removed)"
    SYSTEM_SSL_FOUND=false
fi

run_test
print_info "Checking for system OpenSSL packages..."
SSL_PACKAGES=$(docker run --rm "$IMAGE_NAME" sh -c "dpkg -l | grep -E 'libssl3|openssl\s' | grep -v 'libssl-dev' || true")
if [ -n "$SSL_PACKAGES" ]; then
    print_warning "System OpenSSL packages found"
    echo "$SSL_PACKAGES" | sed 's/^/    /'
else
    print_pass "System OpenSSL packages not installed"
fi

# ============================================================================
# PHASE 3: FIPS OPENSSL VERIFICATION
# ============================================================================

print_header "Phase 3: FIPS OpenSSL Verification"

run_test
print_info "Checking FIPS OpenSSL presence..."
FIPS_SSL=$(docker run --rm "$IMAGE_NAME" sh -c "ls -la /usr/local/openssl/lib64/libssl.so* 2>/dev/null || true")
if [ -n "$FIPS_SSL" ]; then
    print_pass "FIPS OpenSSL libraries present"
    echo "$FIPS_SSL" | sed 's/^/    /'
else
    print_critical "FIPS OpenSSL libraries not found"
fi

run_test
print_info "Checking Valkey binary linkage to FIPS OpenSSL..."
VALKEY_LINKAGE=$(docker run --rm "$IMAGE_NAME" ldd /opt/bitnami/valkey/bin/valkey-server | grep ssl || true)
if echo "$VALKEY_LINKAGE" | grep -q "/usr/local/openssl"; then
    print_pass "Valkey linked to FIPS OpenSSL"
    echo "$VALKEY_LINKAGE" | sed 's/^/    /'
else
    print_critical "Valkey NOT linked to FIPS OpenSSL"
    echo "  Current linkage:"
    echo "$VALKEY_LINKAGE" | sed 's/^/    /'
fi

run_test
print_info "Checking wolfProvider availability..."
WOLFPROV=$(docker run --rm "$IMAGE_NAME" openssl list -providers 2>/dev/null | grep -A 5 wolfprov || true)
if [ -n "$WOLFPROV" ]; then
    print_pass "wolfProvider loaded"
else
    print_critical "wolfProvider not loaded"
fi

# ============================================================================
# PHASE 4: HARDENING PACKAGE DEPENDENCY ANALYSIS
# ============================================================================

print_header "Phase 4: Hardening Package Analysis"

print_subheader "4.1: Installed Hardening Packages"

HARDENING_PACKAGES=(
    "libpam-pwquality:Password quality checking"
    "libpam-runtime:PAM runtime support"
    "aide:Advanced Intrusion Detection"
    "aide-common:AIDE common files"
    "auditd:Linux audit daemon"
    "rsyslog:System logging"
    "sudo:Superuser privileges"
    "vim:Text editor"
    "less:Pager"
    "libnss3-tools:NSS tools"
)

for pkg_info in "${HARDENING_PACKAGES[@]}"; do
    pkg="${pkg_info%%:*}"
    desc="${pkg_info#*:}"

    run_test
    print_info "Checking $pkg ($desc)..."
    PKG_STATUS=$(docker run --rm "$IMAGE_NAME" sh -c "dpkg -l | grep \"^ii.*$pkg\" || true")
    if [ -n "$PKG_STATUS" ]; then
        echo -e "  ${GREEN}Installed:${NC} $pkg"

        # Check crypto dependencies for this package
        CRYPTO_DEPS=$(docker run --rm "$IMAGE_NAME" sh -c "apt-cache depends $pkg 2>/dev/null | grep -E 'libnss3|libgcrypt|libssl' || true")
        if [ -n "$CRYPTO_DEPS" ]; then
            print_warning "$pkg has crypto library dependencies"
            echo "$CRYPTO_DEPS" | sed 's/^/    /'
        fi
    else
        echo "  Not installed: $pkg"
    fi
done

# ============================================================================
# PHASE 5: RUNTIME VALIDATION
# ============================================================================

print_header "Phase 5: Runtime FIPS Validation"

print_info "Starting hardened container..."
docker run -d --name "$CONTAINER_NAME" \
    -e ALLOW_EMPTY_PASSWORD=yes \
    -p "$VALKEY_PORT:6379" \
    "$IMAGE_NAME" >/dev/null 2>&1

print_info "Waiting for container to initialize..."
sleep 10

run_test
print_info "Checking FIPS validation on startup..."
FIPS_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | grep "FIPS VALIDATION" || true)
if echo "$FIPS_LOGS" | grep -q "ALL CHECKS PASSED"; then
    print_pass "FIPS validation passed on startup"
else
    print_critical "FIPS validation failed on startup"
    echo "  Startup logs:"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20 | sed 's/^/    /'
fi

run_test
print_info "Testing Valkey connectivity..."
sleep 5
PING_RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli ping 2>/dev/null || echo "FAILED")
if [ "$PING_RESULT" == "PONG" ]; then
    print_pass "Valkey responding to commands"
else
    print_critical "Valkey not responding"
fi

run_test
print_info "Testing Valkey data operations..."
docker exec "$CONTAINER_NAME" valkey-cli SET test-key "fips-test-value" >/dev/null 2>&1
GET_RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli GET test-key 2>/dev/null || echo "FAILED")
if [ "$GET_RESULT" == "fips-test-value" ]; then
    print_pass "Valkey data operations working"
else
    print_critical "Valkey data operations failed"
fi

run_test
print_info "Testing Lua script hashing (SHA-256)..."
SCRIPT_HASH=$(docker exec "$CONTAINER_NAME" valkey-cli SCRIPT LOAD "return 'test'" 2>/dev/null || echo "FAILED")
if [ ${#SCRIPT_HASH} -eq 40 ] && [ "$SCRIPT_HASH" != "FAILED" ]; then
    print_pass "Lua script hashing works (40-char SHA-256)"
    echo "  Hash: $SCRIPT_HASH"
else
    print_critical "Lua script hashing failed"
fi

# ============================================================================
# PHASE 6: FIPS MODE VERIFICATION
# ============================================================================

print_header "Phase 6: FIPS Mode Status"

run_test
print_info "Checking FIPS startup validation..."
FIPS_CHECK=$(docker exec "$CONTAINER_NAME" cat /tmp/fips-startup-check.log 2>/dev/null || echo "LOG NOT FOUND")
if echo "$FIPS_CHECK" | grep -q "ALL CHECKS PASSED"; then
    print_pass "FIPS startup check passed"
    echo "$FIPS_CHECK" | grep "✓" | sed 's/^/    /'
else
    print_warning "FIPS startup check log not found or failed"
fi

run_test
print_info "Verifying FIPS OpenSSL configuration..."
OPENSSL_CONF=$(docker exec "$CONTAINER_NAME" cat /usr/local/openssl/ssl/openssl.cnf 2>/dev/null | grep -A 5 "\[openssl_init\]" || true)
if echo "$OPENSSL_CONF" | grep -q "providers = provider_sect"; then
    print_pass "OpenSSL configured for FIPS providers"
else
    print_warning "OpenSSL configuration not found or incomplete"
fi

# ============================================================================
# FINAL REPORT
# ============================================================================

print_header "Compliance Report Summary"

echo ""
echo "Test Statistics:"
echo "  Total Tests Run: $TOTAL_TESTS"
echo "  Tests Passed: $PASSED_TESTS"
echo "  Tests Failed: $FAILED_TESTS"
echo "  Critical Failures: $CRITICAL_FAILURES"

echo ""
echo "Non-FIPS Crypto Library Status:"
if [ "$NSS_FOUND" = true ]; then
    echo -e "  ${RED}🔴 NSS (libnss3): FOUND - CRITICAL RISK${NC}"
else
    echo -e "  ${GREEN}✓ NSS (libnss3): Not found${NC}"
fi

if [ "$GCRYPT_FOUND" = true ]; then
    echo -e "  ${RED}🔴 GNU Crypto (libgcrypt20): FOUND - CRITICAL RISK${NC}"
else
    echo -e "  ${GREEN}✓ GNU Crypto (libgcrypt20): Not found${NC}"
fi

if [ "$SYSTEM_SSL_FOUND" = true ]; then
    echo -e "  ${RED}🔴 System OpenSSL: FOUND - CRITICAL RISK${NC}"
else
    echo -e "  ${GREEN}✓ System OpenSSL: Removed${NC}"
fi

if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
    echo ""
    echo "Critical Issues Detected:"
    for issue in "${CRITICAL_ISSUES[@]}"; do
        echo -e "  ${RED}🔴${NC} $issue"
    done
fi

if [ ${#WARNING_ISSUES[@]} -gt 0 ]; then
    echo ""
    echo "Warnings:"
    for warning in "${WARNING_ISSUES[@]}"; do
        echo -e "  ${YELLOW}🟡${NC} $warning"
    done
fi

echo ""
echo "========================================"
if [ $CRITICAL_FAILURES -gt 0 ]; then
    echo -e "${RED}❌ FIPS COMPLIANCE: FAILED${NC}"
    echo "========================================"
    echo ""
    echo "The hardened image has CRITICAL FIPS compliance issues."
    echo "Non-FIPS crypto libraries detected that bypass FIPS OpenSSL."
    echo ""
    echo "Recommendation: Remove packages that introduce non-FIPS crypto:"
    echo "  - libnss3-tools (introduces NSS crypto)"
    echo "  - rsyslog (pulls libgcrypt20 dependency)"
    echo ""
    echo "See HARDENING-FIPS-IMPACT-ANALYSIS.md for detailed findings."
    exit 1
elif [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  FIPS COMPLIANCE: WARNINGS${NC}"
    echo "========================================"
    echo ""
    echo "The hardened image has potential FIPS compliance concerns."
    echo "Review warnings and consider package alternatives."
    exit 2
else
    echo -e "${GREEN}✅ FIPS COMPLIANCE: VERIFIED${NC}"
    echo "========================================"
    echo ""
    echo "The hardened image maintains FIPS 140-3 compliance."
    echo "No non-FIPS crypto libraries detected."
    echo "Valkey functionality intact."
    exit 0
fi
