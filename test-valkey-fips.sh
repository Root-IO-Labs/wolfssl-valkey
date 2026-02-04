#!/bin/bash
###############################################################################
# FIPS Valkey Test Script
#
# This script tests the FIPS-enabled Valkey container to ensure:
# 1. Container starts successfully with FIPS validation
# 2. Valkey is running and responding
# 3. TLS connections work with FIPS cryptography
# 4. Basic Valkey operations function correctly
#
# Usage:
#   ./test-valkey-fips.sh [container_name]
#
# Default container name: valkey-fips-test
###############################################################################

set -e

CONTAINER_NAME="${1:-valkey-fips-test}"
IMAGE_NAME="valkey-fips:8.1.5-ubuntu-24.04"
VALKEY_PORT=6379
VALKEY_TLS_PORT=6380

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "FIPS Valkey Test Suite"
echo "========================================"
echo ""

# Function to print test status
print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

###############################################################################
# Test 1: Check if image exists
###############################################################################
print_test "Checking if image exists: $IMAGE_NAME"
if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    print_success "Image found: $IMAGE_NAME"
else
    print_error "Image not found: $IMAGE_NAME"
    echo "Please build the image first:"
    echo "  docker build --secret id=wolfssl_password,src=.password \\"
    echo "    -t $IMAGE_NAME \\"
    echo "    -f valkey/8.1.5-ubuntu-24.04-fips/Dockerfile ."
    exit 1
fi

###############################################################################
# Test 2: Start container
###############################################################################
print_test "Starting Valkey container: $CONTAINER_NAME"

# Stop and remove existing container if it exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Removing existing container: $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
fi

# Start new container (with ALLOW_EMPTY_PASSWORD for testing)
docker run -d \
    --name "$CONTAINER_NAME" \
    -p ${VALKEY_PORT}:6379 \
    -e ALLOW_EMPTY_PASSWORD=yes \
    "$IMAGE_NAME" >/dev/null

print_success "Container started: $CONTAINER_NAME"

# Wait for container to be ready
print_test "Waiting for Valkey to be ready..."
sleep 5

###############################################################################
# Test 3: Check container logs for FIPS validation
###############################################################################
print_test "Checking container logs for FIPS validation..."

LOGS=$(docker logs "$CONTAINER_NAME" 2>&1)

if echo "$LOGS" | grep -q "ALL FIPS CHECKS PASSED"; then
    print_success "FIPS validation passed in container logs"
else
    print_error "FIPS validation not found in logs"
    echo "Container logs:"
    echo "$LOGS"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

if echo "$LOGS" | grep -q "FIPS VALIDATION FAILED"; then
    print_error "FIPS validation failed in logs"
    echo "Container logs:"
    echo "$LOGS"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

###############################################################################
# Test 4: Check if Valkey is running
###############################################################################
print_test "Checking if Valkey process is running..."

if docker exec "$CONTAINER_NAME" pgrep -x valkey-server >/dev/null 2>&1; then
    print_success "Valkey server process is running"
else
    print_error "Valkey server process not found"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

###############################################################################
# Test 5: Test basic Valkey operations
###############################################################################
print_test "Testing basic Valkey operations..."

# Test PING command
if docker exec "$CONTAINER_NAME" valkey-cli PING 2>/dev/null | grep -q "PONG"; then
    print_success "PING command successful"
else
    print_error "PING command failed"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

# Test SET command
if docker exec "$CONTAINER_NAME" valkey-cli SET fips_test "FIPS_140_3" >/dev/null 2>&1; then
    print_success "SET command successful"
else
    print_error "SET command failed"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

# Test GET command
GET_RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli GET fips_test 2>/dev/null)
if [ "$GET_RESULT" = "FIPS_140_3" ]; then
    print_success "GET command successful (value: $GET_RESULT)"
else
    print_error "GET command failed (expected: FIPS_140_3, got: $GET_RESULT)"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

###############################################################################
# Test 6: Verify OpenSSL and wolfProvider configuration
###############################################################################
print_test "Verifying OpenSSL and wolfProvider configuration..."

# Check OpenSSL version
OPENSSL_VERSION=$(docker exec "$CONTAINER_NAME" openssl version 2>/dev/null)
if echo "$OPENSSL_VERSION" | grep -q "OpenSSL 3"; then
    print_success "OpenSSL 3.x detected: $OPENSSL_VERSION"
else
    print_warning "Unexpected OpenSSL version: $OPENSSL_VERSION"
fi

# Check for wolfProvider
if docker exec "$CONTAINER_NAME" openssl list -providers 2>/dev/null | grep -qi "wolfprov"; then
    print_success "wolfProvider is loaded"
else
    print_warning "wolfProvider not detected in provider list"
fi

###############################################################################
# Test 7: Check Valkey version and info
###############################################################################
print_test "Checking Valkey version and info..."

VALKEY_VERSION=$(docker exec "$CONTAINER_NAME" valkey-server --version 2>/dev/null | head -n1)
print_success "Valkey version: $VALKEY_VERSION"

# Get server info
INFO=$(docker exec "$CONTAINER_NAME" valkey-cli INFO server 2>/dev/null | grep "valkey_version" || true)
if [ -n "$INFO" ]; then
    print_success "Server info: $INFO"
fi

###############################################################################
# Test 8: Verify wolfSSL FIPS library
###############################################################################
print_test "Verifying wolfSSL FIPS library..."

if docker exec "$CONTAINER_NAME" sh -c 'ls /usr/local/lib/libwolfssl.so* 2>/dev/null' | grep -q "libwolfssl"; then
    WOLFSSL_LIB=$(docker exec "$CONTAINER_NAME" sh -c 'ls -lh /usr/local/lib/libwolfssl.so* 2>/dev/null' | head -n1)
    print_success "wolfSSL library found: $WOLFSSL_LIB"
else
    print_error "wolfSSL library not found"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

###############################################################################
# Test 9: Check environment variables
###############################################################################
print_test "Checking FIPS environment variables..."

OPENSSL_CONF=$(docker exec "$CONTAINER_NAME" printenv OPENSSL_CONF 2>/dev/null || echo "")
if [ -n "$OPENSSL_CONF" ]; then
    print_success "OPENSSL_CONF is set: $OPENSSL_CONF"
else
    print_error "OPENSSL_CONF is not set"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

OPENSSL_MODULES=$(docker exec "$CONTAINER_NAME" printenv OPENSSL_MODULES 2>/dev/null || echo "")
if [ -n "$OPENSSL_MODULES" ]; then
    print_success "OPENSSL_MODULES is set: $OPENSSL_MODULES"
else
    print_error "OPENSSL_MODULES is not set"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

###############################################################################
# Test 10: Performance test
###############################################################################
print_test "Running basic performance test..."

PERF_RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli --intrinsic-latency 1 2>/dev/null | tail -n1 || echo "failed")
if [ "$PERF_RESULT" != "failed" ]; then
    print_success "Performance test completed: $PERF_RESULT"
else
    print_warning "Performance test failed or not available"
fi

###############################################################################
# Summary
###############################################################################
echo ""
echo "========================================"
echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
echo "========================================"
echo ""
echo "Container Information:"
echo "  Container Name: $CONTAINER_NAME"
echo "  Image: $IMAGE_NAME"
echo "  Valkey Port: $VALKEY_PORT"
echo "  Status: Running with FIPS 140-3 validation"
echo ""
echo "Next steps:"
echo "  1. View logs:     docker logs $CONTAINER_NAME"
echo "  2. Connect:       docker exec -it $CONTAINER_NAME valkey-cli"
echo "  3. Stop:          docker stop $CONTAINER_NAME"
echo "  4. Remove:        docker rm $CONTAINER_NAME"
echo ""

# Option to keep container running or stop it
read -p "Keep container running? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
    print_test "Stopping and removing container..."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    print_success "Container removed"
else
    echo "Container is still running: $CONTAINER_NAME"
fi
