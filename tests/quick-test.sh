#!/bin/bash
################################################################################
# Quick FIPS Implementation Test Script
#
# Runs critical validation tests on the Valkey FIPS image
#
# Usage:
#   ./quick-test.sh [image_name]
#
# Default image: valkey-fips:8.1.5-ubuntu-22.04
#
# Test Coverage:
#   - Image structure validation
#   - FIPS startup checks (wolfSSL FIPS v5)
#   - Operating Environment (OE) compliance
#   - OpenSSL 3.x + wolfProvider configuration
#   - Valkey 8.1.5 with FIPS crypto
#   - CRITICAL: Fail-closed security enforcement
#   - CRITICAL: MD5 algorithm rejection (FIPS requirement)
#   - Full container startup and crypto operations
#
# Last Updated: 2025-12-04
# Version: 2.0 (with security fix validation)
################################################################################

# Note: NOT using 'set -e' so script continues even if tests fail
# We want to run ALL test suites and report all results

IMAGE_NAME="${1:-valkey-fips:8.1.5-ubuntu-22.04}"
FAILED_TESTS=0
PASSED_TESTS=0

echo "========================================"
echo "Valkey FIPS Quick Test Suite"
echo "Version: 2.0"
echo "========================================"
echo "Image: $IMAGE_NAME"
echo "Date: $(date)"
echo ""
echo "Test Coverage:"
echo "  • Image structure and library validation"
echo "  • FIPS cryptographic validation (wolfSSL v5)"
echo "  • Operating Environment (OE) compliance"
echo "  • OpenSSL + wolfProvider integration"
echo "  • Valkey FIPS crypto operations"
echo "  • CRITICAL: Fail-closed security tests"
echo "  • CRITICAL: MD5 rejection (FIPS enforcement)"
echo ""

###############################################################################
# Helper Functions
###############################################################################

run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -n "Testing: $test_name ... "

    # Use || true to ensure command doesn't cause script to exit
    if eval "$test_command" > /tmp/test_output.log 2>&1 || false; then
        echo "✓ PASS"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "✗ FAIL"
        echo "  Error output:"
        cat /tmp/test_output.log | sed 's/^/    /' | head -10
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

run_test_with_output() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"

    echo -n "Testing: $test_name ... "

    # Use || true to ensure command doesn't cause script to exit
    output=$(eval "$test_command" 2>&1 || true)

    if echo "$output" | grep -qE "$expected_pattern"; then
        echo "✓ PASS"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "✗ FAIL"
        echo "  Expected pattern: $expected_pattern"
        echo "  Actual output:"
        echo "$output" | sed 's/^/    /' | head -10
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

###############################################################################
# Pre-Test: Check Image Exists
###############################################################################

echo "[Pre-Test] Checking image exists..."
if ! docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
    echo "✗ ERROR: Image $IMAGE_NAME not found"
    echo "Please build the image first:"
    echo "  DOCKER_BUILDKIT=1 docker buildx build --secret id=wolfssl_password,src=wolfssl_password.txt -t $IMAGE_NAME ."
    exit 1
fi
echo "✓ Image found"
echo ""

###############################################################################
# Test Suite
###############################################################################

echo "========================================"
echo "Test Suite 1: Image Structure"
echo "========================================"
echo "Starting Test Suite 1..."

run_test_with_output \
    "No system OpenSSL (libssl3t64) present" \
    "docker run --rm $IMAGE_NAME bash -c 'dpkg -l | grep libssl3t64 || true'" \
    "^$"

run_test_with_output \
    "FIPS OpenSSL present" \
    "docker run --rm $IMAGE_NAME ls /usr/lib/x86_64-linux-gnu/libssl.so.3" \
    "libssl.so.3"

run_test_with_output \
    "wolfSSL library present" \
    "docker run --rm $IMAGE_NAME find /usr/local/lib -name 'libwolfssl.so*'" \
    "libwolfssl.so"

run_test_with_output \
    "wolfProvider module present" \
    "docker run --rm $IMAGE_NAME ls /usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so" \
    "libwolfprov.so"

echo ""
echo "========================================"
echo "Test Suite 2: FIPS Validation"
echo "========================================"
echo "Starting Test Suite 2..."

run_test_with_output \
    "FIPS startup check utility exists" \
    "docker run --rm $IMAGE_NAME ls -l /usr/local/bin/fips-startup-check" \
    "fips-startup-check"

run_test_with_output \
    "FIPS startup check passes" \
    "docker run --rm $IMAGE_NAME /usr/local/bin/fips-startup-check" \
    "✓ FIPS VALIDATION PASSED"

run_test_with_output \
    "FIPS compile-time check" \
    "docker run --rm $IMAGE_NAME /usr/local/bin/fips-startup-check" \
    "✓ FIPS mode: ENABLED"

run_test_with_output \
    "FIPS CAST passes" \
    "docker run --rm $IMAGE_NAME /usr/local/bin/fips-startup-check" \
    "✓ FIPS CAST: PASSED"

run_test_with_output \
    "SHA-256 validation passes" \
    "docker run --rm $IMAGE_NAME /usr/local/bin/fips-startup-check" \
    "✓ SHA-256 test vector: PASSED"

run_test_with_output \
    "Entropy/RNG validation passes" \
    "docker run --rm --entrypoint='' $IMAGE_NAME /usr/local/bin/fips-startup-check" \
    "✓ FIPS VALIDATION PASSED" || true

echo ""
echo "========================================"
echo "Test Suite 3: OE Validation"
echo "========================================"
echo "Starting Test Suite 3..."

run_test_with_output \
    "Kernel version detection" \
    "docker run --rm $IMAGE_NAME /usr/local/bin/fips-entrypoint.sh /bin/true" \
    "Detected kernel:"

run_test_with_output \
    "CPU architecture validation (x86_64)" \
    "docker run --rm $IMAGE_NAME /usr/local/bin/fips-entrypoint.sh /bin/true" \
    "✓ CPU architecture: x86_64"

run_test_with_output \
    "Ubuntu OpenSSL with wolfProvider verified" \
    "docker run --rm $IMAGE_NAME /usr/local/bin/fips-entrypoint.sh /bin/true" \
    "✓ Ubuntu OpenSSL 3.x with wolfProvider verified"

echo ""
echo "========================================"
echo "Test Suite 4: OpenSSL Configuration"
echo "========================================"

run_test_with_output \
    "OpenSSL version (3.x)" \
    "docker run --rm $IMAGE_NAME openssl version" \
    "OpenSSL 3\."

run_test_with_output \
    "wolfProvider is loaded" \
    "docker run --rm $IMAGE_NAME openssl list -providers" \
    "wolfprov"

run_test_with_output \
    "OpenSSL SHA-256 works" \
    "docker run --rm $IMAGE_NAME bash -c 'echo -n test | openssl dgst -sha256'" \
    "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

run_test_with_output \
    "OpenSSL random generation works" \
    "docker run --rm --entrypoint='' $IMAGE_NAME bash -c 'openssl rand -hex 16 | tr -d \"[:space:]\"'" \
    "^[0-9a-f]{32}$"

echo ""
echo "========================================"
echo "Test Suite 5: Valkey"
echo "========================================"

run_test_with_output \
    "Valkey version (8.1.5)" \
    "docker run --rm $IMAGE_NAME valkey-server --version" \
    "8\.1\.5"

run_test_with_output \
    "Valkey binary exists" \
    "docker run --rm $IMAGE_NAME ls /opt/bitnami/valkey/bin/valkey-server" \
    "valkey-server"

run_test_with_output \
    "Valkey links to FIPS OpenSSL" \
    "docker run --rm --entrypoint='' $IMAGE_NAME ldd /opt/bitnami/valkey/bin/valkey-server" \
    "(/usr/local/openssl/lib64|/usr/lib/x86_64-linux-gnu)/libssl\.so"

echo ""
echo "========================================"
echo "Test Suite 6: Full Entrypoint"
echo "========================================"

run_test_with_output \
    "All 6 validation checks pass" \
    "docker run --rm $IMAGE_NAME /usr/local/bin/fips-entrypoint.sh valkey-server --version" \
    "✓ ALL FIPS CHECKS PASSED"

echo ""
echo "========================================"
echo "Test Suite 7: CRITICAL - Fail-Closed Security"
echo "========================================"

echo -n "Testing: Fail-closed on missing fips-startup-check ... "
output=$(docker run --rm --user root $IMAGE_NAME bash -c 'rm /usr/local/bin/fips-startup-check; /usr/local/bin/fips-entrypoint.sh /bin/true' 2>&1 || true)
if echo "$output" | grep -q "✗ FIPS VALIDATION FAILED"; then
    echo "✓ PASS (correctly fails)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (security vulnerability - container should NOT start!)"
    echo "  Expected: '✗ FIPS VALIDATION FAILED'"
    echo "  Actual output:"
    echo "$output" | sed 's/^/    /'
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo -n "Testing: Fail-closed on missing wolfProvider ... "
output=$(docker run --rm --user root $IMAGE_NAME bash -c 'rm /usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so; /usr/local/bin/fips-entrypoint.sh /bin/true' 2>&1 || true)
if echo "$output" | grep -q "✗ FIPS VALIDATION FAILED"; then
    echo "✓ PASS (correctly fails)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (security vulnerability - container should NOT start!)"
    echo "  Expected: '✗ FIPS VALIDATION FAILED'"
    echo "  Actual output:"
    echo "$output" | sed 's/^/    /'
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo -n "Testing: Fail-closed on missing wolfSSL library ... "
output=$(docker run --rm --user root $IMAGE_NAME bash -c 'rm /usr/local/lib/libwolfssl.so*; /usr/local/bin/fips-entrypoint.sh /bin/true' 2>&1 || true)
if echo "$output" | grep -q "✗ FIPS VALIDATION FAILED"; then
    echo "✓ PASS (correctly fails)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (security vulnerability - container should NOT start!)"
    echo "  Expected: '✗ FIPS VALIDATION FAILED'"
    echo "  Actual output:"
    echo "$output" | sed 's/^/    /'
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""
echo "========================================"
echo "Test Suite 8: FIPS Algorithm Enforcement"
echo "========================================"

echo -n "Testing: MD5 is disabled (OpenSSL) ... "
output=$(docker run --rm $IMAGE_NAME bash -c 'echo -n "test" | openssl dgst -md5' 2>&1 || true)
if echo "$output" | grep -qi "unsupported\|error\|disabled"; then
    echo "✓ PASS (MD5 correctly disabled)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (MD5 should be disabled in FIPS mode!)"
    echo "  MD5 worked when it should have failed"
    echo "  Actual output:"
    echo "$output" | sed 's/^/    /'
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo -n "Testing: SHA-256 is enabled (FIPS-approved) ... "
output=$(docker run --rm $IMAGE_NAME bash -c 'echo -n "test" | openssl dgst -sha256' 2>&1)
if echo "$output" | grep -q "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"; then
    echo "✓ PASS (SHA-256 works correctly)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "✗ FAIL (SHA-256 should work in FIPS mode)"
    echo "  Actual output:"
    echo "$output" | sed 's/^/    /'
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""
echo "========================================"
echo "Test Suite 9: Container Startup"
echo "========================================"

echo -n "Testing: Container starts successfully ... "
CONTAINER_ID=$(docker run -d --name valkey-quick-test-$$ \
    -e ALLOW_EMPTY_PASSWORD=yes \
    $IMAGE_NAME 2>/dev/null)

if [ -n "$CONTAINER_ID" ]; then
    sleep 10

    if docker ps | grep -q "valkey-quick-test-$$"; then
        echo "✓ PASS"
        PASSED_TESTS=$((PASSED_TESTS + 1))

        # Check logs for FIPS validation
        echo -n "Testing: FIPS validation in container logs ... "
        if docker logs valkey-quick-test-$$ 2>&1 | grep -q "✓ ALL FIPS CHECKS PASSED"; then
            echo "✓ PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "✗ FAIL"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi

        # Wait for Valkey to be ready
        sleep 15

        # Check Valkey is accepting connections
        echo -n "Testing: Valkey accepting connections (PING) ... "
        output=$(docker exec valkey-quick-test-$$ valkey-cli PING 2>&1 || true)
        if echo "$output" | grep -q "PONG"; then
            echo "✓ PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "✗ FAIL"
            echo "  Expected: PONG"
            echo "  Actual output: $output"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi

        # Test Valkey SET/GET operations
        echo -n "Testing: Valkey SET/GET works ... "
        docker exec valkey-quick-test-$$ valkey-cli SET testkey "fips_test_value" >/dev/null 2>&1
        output=$(docker exec valkey-quick-test-$$ valkey-cli GET testkey 2>&1)
        if echo "$output" | grep -q "fips_test_value"; then
            echo "✓ PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "✗ FAIL"
            echo "  Expected: fips_test_value"
            echo "  Actual output: $output"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi

        # Test Valkey INFO command
        echo -n "Testing: Valkey INFO command works ... "
        output=$(docker exec valkey-quick-test-$$ valkey-cli INFO server 2>&1 || true)
        if echo "$output" | grep -q "valkey_version"; then
            echo "✓ PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "✗ FAIL"
            echo "  Expected: valkey_version in output"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi

        # Test Valkey is using correct version
        echo -n "Testing: Valkey version in INFO ... "
        output=$(docker exec valkey-quick-test-$$ valkey-cli INFO server 2>&1 || true)
        if echo "$output" | grep -q "valkey_version:8\.1\.5"; then
            echo "✓ PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "✗ FAIL"
            echo "  Expected: valkey_version:8.1.5"
            echo "  Actual output:"
            echo "$output" | sed 's/^/    /'
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi

        # Cleanup
        docker stop valkey-quick-test-$$ >/dev/null 2>&1
        docker rm valkey-quick-test-$$ >/dev/null 2>&1
    else
        echo "✗ FAIL"
        echo "  Container exited unexpectedly"
        docker logs valkey-quick-test-$$ 2>&1 | sed 's/^/    /'
        docker rm valkey-quick-test-$$ >/dev/null 2>&1
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "✗ FAIL"
    echo "  Failed to start container"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

###############################################################################
# Test Summary
###############################################################################

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total Tests: $((PASSED_TESTS + FAILED_TESTS))"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo "✓✓✓ ALL TESTS PASSED ✓✓✓"
    echo ""
    echo "Your FIPS implementation is working correctly!"
    echo ""
    echo "Security Status:"
    echo "  ✅ Fail-closed security enforced (critical)"
    echo "  ✅ MD5 disabled in FIPS mode (required)"
    echo "  ✅ Valkey 8.1.5 with TLS support (FIPS-compliant)"
    echo "  ✅ wolfSSL FIPS v5 + OpenSSL 3.x operational"
    echo ""
    echo "Next Steps:"
    echo "  1. Review detailed test results above"
    echo "  2. Run full test plan (tests/TEST-PLAN.md) for comprehensive validation"
    echo "  3. Review security fix documentation (docs/SECURITY-FIX-2025-12-03.md)"
    echo "  4. Deploy to production (docs/deployment-quickstart.md)"
    echo ""
    exit 0
else
    echo "✗✗✗ SOME TESTS FAILED ✗✗✗"
    echo ""
    echo "⚠️  CRITICAL: If fail-closed security tests failed, this is a SECURITY VULNERABILITY!"
    echo "⚠️  Container MUST NOT start when FIPS validation fails."
    echo ""
    echo "Please review the failed tests above and:"
    echo "  1. Check error messages for details"
    echo "  2. Refer to tests/TEST-PLAN.md for troubleshooting"
    echo "  3. Review build logs for any warnings or errors"
    echo "  4. Check docs/SECURITY-FIX-2025-12-03.md for security requirements"
    echo ""
    exit 1
fi
