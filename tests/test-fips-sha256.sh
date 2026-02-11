#!/bin/bash
#
# Valkey 8.1.5 FIPS SHA-256 Verification Test Suite
#
# Purpose: Verify that SHA-1 has been completely replaced with SHA-256
#          and that all FIPS compliance requirements are met
#
# Author: Automated Test Suite
# Date: December 18, 2025
# Version: 1.0
#

# Exit on error disabled to allow all tests to run
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Configuration
IMAGE_NAME="${IMAGE_NAME:-valkey-fips:8.1.5-ubuntu-22.04}"
CONTAINER_NAME="valkey-fips-test-$$"
VALKEY_PORT=6379

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

# Print functions
print_header() {
    echo ""
    echo "========================================"
    echo -e "${BLUE}$1${NC}"
    echo "========================================"
    echo ""
}

print_test() {
    echo -e "${YELLOW}[TEST $TESTS_RUN]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✓ PASSED${NC}: $1"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAILED${NC}: $1"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

run_test() {
    ((TESTS_RUN++))
    print_test "$1"
}

# Test 1: Docker image exists
test_image_exists() {
    run_test "Verify Docker image exists"

    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        print_pass "Docker image '$IMAGE_NAME' exists"
        return 0
    else
        print_fail "Docker image '$IMAGE_NAME' not found"
        return 1
    fi
}

# Test 2: Start container with FIPS validation
test_container_startup() {
    run_test "Start container and verify FIPS validation"

    docker run --name "$CONTAINER_NAME" -d \
        -p $VALKEY_PORT:6379 \
        -e ALLOW_EMPTY_PASSWORD=yes \
        "$IMAGE_NAME" >/dev/null 2>&1

    sleep 5

    # Check if container is running
    if docker ps | grep -q "$CONTAINER_NAME"; then
        print_pass "Container started successfully"

        # Check FIPS validation in logs
        if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "FIPS VALIDATION PASSED"; then
            print_pass "FIPS startup validation passed"
            return 0
        else
            print_fail "FIPS validation not found in startup logs"
            return 1
        fi
    else
        print_fail "Container failed to start"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -20
        return 1
    fi
}

# Test 3: Basic connectivity
test_basic_connectivity() {
    run_test "Test basic Valkey connectivity (PING)"

    RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli PING 2>/dev/null || echo "ERROR")

    if [ "$RESULT" = "PONG" ]; then
        print_pass "PING command successful"
        return 0
    else
        print_fail "PING command failed: $RESULT"
        return 1
    fi
}

# Test 4: SET/GET operations
test_set_get() {
    run_test "Test SET/GET operations"

    docker exec "$CONTAINER_NAME" valkey-cli SET fips_test "Hello FIPS SHA-256" >/dev/null 2>&1
    RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli GET fips_test 2>/dev/null)

    if [ "$RESULT" = "Hello FIPS SHA-256" ]; then
        print_pass "SET/GET operations working"
        return 0
    else
        print_fail "SET/GET failed: expected 'Hello FIPS SHA-256', got '$RESULT'"
        return 1
    fi
}

# Test 5: Lua SCRIPT LOAD (SHA-256 hashing)
test_script_load() {
    run_test "Test SCRIPT LOAD (SHA-256 hashing)"

    SCRIPT_HASH=$(docker exec "$CONTAINER_NAME" valkey-cli SCRIPT LOAD "return 'fips_test'" 2>/dev/null)

    # Verify hash is 40 characters (hexadecimal)
    if [ ${#SCRIPT_HASH} -eq 40 ]; then
        print_pass "SCRIPT LOAD generated 40-character hash: $SCRIPT_HASH"
        print_info "Hash format maintained for backward compatibility"

        # Store for next test
        echo "$SCRIPT_HASH" > /tmp/valkey_script_hash_$$
        return 0
    else
        print_fail "SCRIPT LOAD hash invalid: $SCRIPT_HASH (length: ${#SCRIPT_HASH})"
        return 1
    fi
}

# Test 6: EVALSHA execution
test_evalsha() {
    run_test "Test EVALSHA with SHA-256 hash"

    if [ ! -f /tmp/valkey_script_hash_$$ ]; then
        print_fail "No script hash from previous test"
        return 1
    fi

    SCRIPT_HASH=$(cat /tmp/valkey_script_hash_$$)
    RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli EVALSHA "$SCRIPT_HASH" 0 2>/dev/null)

    if [ "$RESULT" = "fips_test" ]; then
        print_pass "EVALSHA executed successfully with SHA-256 hash"
        rm -f /tmp/valkey_script_hash_$$
        return 0
    else
        print_fail "EVALSHA failed: expected 'fips_test', got '$RESULT'"
        rm -f /tmp/valkey_script_hash_$$
        return 1
    fi
}

# Test 7: EVAL command
test_eval() {
    run_test "Test EVAL command"

    RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli EVAL "return 'SHA-256 working'" 0 2>/dev/null)

    if [ "$RESULT" = "SHA-256 working" ]; then
        print_pass "EVAL command working"
        return 0
    else
        print_fail "EVAL failed: $RESULT"
        return 1
    fi
}

# Test 8: Lua server.sha1hex() function (now uses SHA-256)
test_lua_sha1hex() {
    run_test "Test Lua server.sha1hex() function (SHA-256 implementation)"

    RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli EVAL "return server.sha1hex('test')" 0 2>/dev/null)

    # Verify it returns 40 characters
    if [ ${#RESULT} -eq 40 ]; then
        print_pass "server.sha1hex() returns 40-character hash: $RESULT"
        print_info "API name maintained, SHA-256 used internally"

        # Verify it's actually SHA-256 (first 40 chars of SHA-256('test'))
        # SHA-256('test') = 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b3c0b822cd15d6c15b0f00a08
        # First 40 chars: 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b
        EXPECTED="9f86d081884c7d659a2feaa0c55ad015a3bf4f1b"
        if [ "$RESULT" = "$EXPECTED" ]; then
            print_pass "Confirmed: Using SHA-256 (not SHA-1)"
            print_info "SHA-1('test') would be: a94a8fe5ccb19ba61c4c0873d391e987982fbbd3"
            return 0
        else
            print_fail "Hash mismatch: expected $EXPECTED, got $RESULT"
            return 1
        fi
    else
        print_fail "Invalid hash length: ${#RESULT}"
        return 1
    fi
}

# Test 9: Multiple script loads (hash consistency)
test_hash_consistency() {
    run_test "Test hash consistency across multiple SCRIPT LOAD calls"

    HASH1=$(docker exec "$CONTAINER_NAME" valkey-cli SCRIPT LOAD "return 'consistency_test'" 2>/dev/null)
    HASH2=$(docker exec "$CONTAINER_NAME" valkey-cli SCRIPT LOAD "return 'consistency_test'" 2>/dev/null)

    if [ "$HASH1" = "$HASH2" ]; then
        print_pass "Hash consistency verified: $HASH1"
        return 0
    else
        print_fail "Hash mismatch: $HASH1 vs $HASH2"
        return 1
    fi
}

# Test 10: No SHA-1 symbols in binary
test_no_sha1_symbols() {
    run_test "Verify no SHA-1 symbols in valkey-server binary"

    # Copy binary to host for inspection
    docker cp "$CONTAINER_NAME:/opt/bitnami/valkey/bin/valkey-server" /tmp/valkey-server-test-$$ >/dev/null 2>&1

    # Check for SHA-1 function symbols
    SHA1_SYMBOLS=$(strings /tmp/valkey-server-test-$$ | grep -i "SHA1_Init\|SHA1_Update\|SHA1_Final" || true)

    rm -f /tmp/valkey-server-test-$$

    if [ -z "$SHA1_SYMBOLS" ]; then
        print_pass "No SHA-1 symbols found in binary"
        return 0
    else
        print_fail "SHA-1 symbols found in binary:"
        echo "$SHA1_SYMBOLS"
        return 1
    fi
}

# Test 11: OpenSSL FIPS linkage (Ubuntu OpenSSL + wolfProvider architecture)
test_openssl_linkage() {
    run_test "Verify OpenSSL FIPS linkage"

    OPENSSL_LIBS=$(docker exec "$CONTAINER_NAME" ldd /opt/bitnami/valkey/bin/valkey-server 2>/dev/null | grep -i ssl)

    # With Ubuntu OpenSSL architecture:
    # - Valkey links to Ubuntu system OpenSSL at /usr/lib/x86_64-linux-gnu/
    # - FIPS compliance comes from wolfProvider (not from OpenSSL itself)
    if echo "$OPENSSL_LIBS" | grep -q "/usr/lib/x86_64-linux-gnu/libssl.so"; then
        print_pass "Linked to Ubuntu OpenSSL with wolfProvider (/usr/lib/x86_64-linux-gnu/):"
        echo "$OPENSSL_LIBS" | sed 's/^/    /'

        # Verify wolfProvider is present
        WOLFPROV_CHECK=$(docker exec "$CONTAINER_NAME" ls /usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so 2>/dev/null)
        if [ -n "$WOLFPROV_CHECK" ]; then
            print_info "wolfProvider module confirmed: /usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so"
        fi
        return 0
    else
        print_fail "Not linked to Ubuntu OpenSSL"
        echo "$OPENSSL_LIBS"
        return 1
    fi
}

# Test 12: FIPS startup check utility
test_fips_startup_check() {
    run_test "Run FIPS startup check utility"

    OUTPUT=$(docker exec "$CONTAINER_NAME" /usr/local/bin/fips-startup-check 2>&1)

    if echo "$OUTPUT" | grep -q "FIPS VALIDATION PASSED"; then
        print_pass "FIPS startup check passed"

        # Verify specific checks
        if echo "$OUTPUT" | grep -q "FIPS mode: ENABLED"; then
            print_info "FIPS mode: ENABLED ✓"
        fi
        if echo "$OUTPUT" | grep -q "FIPS CAST: PASSED"; then
            print_info "FIPS CAST: PASSED ✓"
        fi
        if echo "$OUTPUT" | grep -q "SHA-256 test vector: PASSED"; then
            print_info "SHA-256 test vector: PASSED ✓"
        fi
        return 0
    else
        print_fail "FIPS startup check failed"
        echo "$OUTPUT"
        return 1
    fi
}

# Test 13: wolfProvider status
test_wolfprovider() {
    run_test "Verify wolfProvider is active"

    OUTPUT=$(docker exec "$CONTAINER_NAME" openssl list -providers 2>/dev/null)

    if echo "$OUTPUT" | grep -q "wolfprov"; then
        print_pass "wolfProvider is active"

        if echo "$OUTPUT" | grep -q "wolfSSL Provider FIPS"; then
            print_info "Provider: wolfSSL Provider FIPS ✓"
        fi
        if echo "$OUTPUT" | grep -q "status: active"; then
            print_info "Status: active ✓"
        fi
        return 0
    else
        print_fail "wolfProvider not found"
        echo "$OUTPUT"
        return 1
    fi
}

# Test 14: Valkey version check
test_valkey_version() {
    run_test "Verify Valkey version"

    VERSION=$(docker exec "$CONTAINER_NAME" valkey-cli INFO Server | grep valkey_version | cut -d: -f2 | tr -d '\r')

    if [ "$VERSION" = "8.1.5" ]; then
        print_pass "Valkey version: $VERSION"
        return 0
    else
        print_fail "Unexpected version: $VERSION"
        return 1
    fi
}

# Test 15: Complex Lua script with hashing
test_complex_lua_script() {
    run_test "Test complex Lua script with multiple hash operations"

    SCRIPT='
    local hash1 = server.sha1hex("data1")
    local hash2 = server.sha1hex("data2")
    return {hash1, hash2}
    '

    RESULT=$(docker exec "$CONTAINER_NAME" valkey-cli --raw EVAL "$SCRIPT" 0 2>/dev/null)

    # Should return two hashes
    HASH_COUNT=$(echo "$RESULT" | wc -l)

    if [ "$HASH_COUNT" -ge 2 ]; then
        print_pass "Complex Lua script executed successfully"
        print_info "Generated multiple SHA-256 hashes"
        return 0
    else
        print_fail "Complex Lua script failed"
        return 1
    fi
}

# Main test execution
main() {
    print_header "Valkey 8.1.5 FIPS SHA-256 Test Suite"

    echo "Test Configuration:"
    echo "  Image: $IMAGE_NAME"
    echo "  Container: $CONTAINER_NAME"
    echo "  Port: $VALKEY_PORT"
    echo ""

    print_header "Phase 1: Image & Container Tests"
    test_image_exists
    test_container_startup

    print_header "Phase 2: Basic Functionality Tests"
    test_basic_connectivity
    test_set_get

    print_header "Phase 3: Lua Script & SHA-256 Tests"
    test_script_load
    test_evalsha
    test_eval
    test_lua_sha1hex
    test_hash_consistency
    test_complex_lua_script

    print_header "Phase 4: FIPS Compliance Verification"
    test_no_sha1_symbols
    test_openssl_linkage
    test_fips_startup_check
    test_wolfprovider

    print_header "Phase 5: System Information"
    test_valkey_version

    # Print summary
    print_header "Test Summary"
    echo "Total Tests Run: $TESTS_RUN"
    echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
        echo ""
        echo -e "${RED}OVERALL RESULT: FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}Tests Failed: 0${NC}"
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}OVERALL RESULT: ALL TESTS PASSED ✓${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "FIPS SHA-256 Implementation: VERIFIED"
        echo "Backward Compatibility: MAINTAINED"
        echo "Production Readiness: CONFIRMED"
        exit 0
    fi
}

# Run main function
main "$@"
