#!/bin/bash
#
# Run all Valkey FIPS test suites
#
# Usage: ./run-all-tests.sh [image-name]
#

set -e

IMAGE="${1:-valkey-fips:8.1.5-ubuntu-22.04}"
echo "========================================"
echo "Running All Valkey FIPS Test Suites"
echo "========================================"
echo "Image: $IMAGE"
echo ""

# Test 1: Valkey Functionality
echo "========================================"
echo "Test Suite 1: Valkey Functionality"
echo "========================================"
IMAGE_NAME="$IMAGE" ./tests/test-valkey-functionality.sh
TEST1_RESULT=$?

# Test 2: FIPS SHA-256 Verification
echo ""
echo "========================================"
echo "Test Suite 2: FIPS SHA-256 Verification"
echo "========================================"
IMAGE_NAME="$IMAGE" ./tests/test-fips-sha256.sh
TEST2_RESULT=$?

# Test 3: Quick Test Suite
echo ""
echo "========================================"
echo "Test Suite 3: Quick Test Suite"
echo "========================================"
./tests/quick-test.sh "$IMAGE"
TEST3_RESULT=$?

# Test 4: Non-FIPS Algorithm Check
echo ""
echo "========================================"
echo "Test Suite 4: Non-FIPS Algorithm Check"
echo "========================================"
./tests/check-non-fips-algorithms.sh "$IMAGE"
TEST4_RESULT=$?

# Summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Test Suite 1 (Valkey Functionality): $([ $TEST1_RESULT -eq 0 ] && echo '✓ PASSED' || echo '✗ FAILED')"
echo "Test Suite 2 (FIPS SHA-256): $([ $TEST2_RESULT -eq 0 ] && echo '✓ PASSED' || echo '✗ FAILED')"
echo "Test Suite 3 (Quick Test): $([ $TEST3_RESULT -eq 0 ] && echo '✓ PASSED' || echo '✗ FAILED')"
echo "Test Suite 4 (Algorithm Check): $([ $TEST4_RESULT -eq 0 ] && echo '✓ PASSED' || echo '✗ FAILED')"

if [ $TEST1_RESULT -eq 0 ] && [ $TEST2_RESULT -eq 0 ] && [ $TEST3_RESULT -eq 0 ] && [ $TEST4_RESULT -eq 0 ]; then
    echo ""
    echo "✅ ALL TEST SUITES PASSED"
    exit 0
else
    echo ""
    echo "❌ SOME TESTS FAILED"
    exit 1
fi
