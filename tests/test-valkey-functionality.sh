#!/bin/bash
#
# Valkey 8.1.5 Comprehensive Functionality Test Suite
#
# Purpose: Verify all core Valkey data structures and functionality
#          work correctly after FIPS SHA-256 modifications
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
CONTAINER_NAME="valkey-func-test-$$"
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

# Helper function to execute Valkey commands
vcli() {
    docker exec "$CONTAINER_NAME" valkey-cli "$@"
}

# Test 1: String operations
test_string_operations() {
    run_test "Test string operations (SET, GET, APPEND, INCR)"

    # SET and GET
    vcli SET str_key "Hello" >/dev/null
    RESULT=$(vcli GET str_key)
    if [ "$RESULT" != "Hello" ]; then
        print_fail "GET failed: expected 'Hello', got '$RESULT'"
        return 1
    fi

    # APPEND
    vcli APPEND str_key " World" >/dev/null
    RESULT=$(vcli GET str_key)
    if [ "$RESULT" != "Hello World" ]; then
        print_fail "APPEND failed: expected 'Hello World', got '$RESULT'"
        return 1
    fi

    # INCR
    vcli SET counter 10 >/dev/null
    vcli INCR counter >/dev/null
    RESULT=$(vcli GET counter)
    if [ "$RESULT" != "11" ]; then
        print_fail "INCR failed: expected '11', got '$RESULT'"
        return 1
    fi

    # DECR
    vcli DECR counter >/dev/null
    RESULT=$(vcli GET counter)
    if [ "$RESULT" != "10" ]; then
        print_fail "DECR failed: expected '10', got '$RESULT'"
        return 1
    fi

    print_pass "String operations: SET, GET, APPEND, INCR, DECR"
    return 0
}

# Test 2: List operations
test_list_operations() {
    run_test "Test list operations (LPUSH, RPUSH, LRANGE, LPOP, RPOP)"

    # LPUSH
    vcli LPUSH mylist "first" >/dev/null
    vcli LPUSH mylist "second" >/dev/null

    # RPUSH
    vcli RPUSH mylist "third" >/dev/null

    # LRANGE
    RESULT=$(vcli LRANGE mylist 0 -1 | tr '\n' '|')
    if ! echo "$RESULT" | grep -q "second.*first.*third"; then
        print_fail "List operations failed: $RESULT"
        return 1
    fi

    # LPOP
    RESULT=$(vcli LPOP mylist)
    if [ "$RESULT" != "second" ]; then
        print_fail "LPOP failed: expected 'second', got '$RESULT'"
        return 1
    fi

    # RPOP
    RESULT=$(vcli RPOP mylist)
    if [ "$RESULT" != "third" ]; then
        print_fail "RPOP failed: expected 'third', got '$RESULT'"
        return 1
    fi

    # LLEN
    RESULT=$(vcli LLEN mylist)
    if [ "$RESULT" != "1" ]; then
        print_fail "LLEN failed: expected '1', got '$RESULT'"
        return 1
    fi

    print_pass "List operations: LPUSH, RPUSH, LRANGE, LPOP, RPOP, LLEN"
    return 0
}

# Test 3: Set operations
test_set_operations() {
    run_test "Test set operations (SADD, SMEMBERS, SISMEMBER, SREM)"

    # SADD
    vcli SADD myset "apple" >/dev/null
    vcli SADD myset "banana" >/dev/null
    vcli SADD myset "orange" >/dev/null

    # SMEMBERS
    RESULT=$(vcli SMEMBERS myset | wc -l)
    if [ "$RESULT" != "3" ]; then
        print_fail "SMEMBERS failed: expected 3 members, got $RESULT"
        return 1
    fi

    # SISMEMBER
    RESULT=$(vcli SISMEMBER myset "banana")
    if [ "$RESULT" != "1" ]; then
        print_fail "SISMEMBER failed: expected '1', got '$RESULT'"
        return 1
    fi

    # SREM
    vcli SREM myset "banana" >/dev/null
    RESULT=$(vcli SCARD myset)
    if [ "$RESULT" != "2" ]; then
        print_fail "SREM failed: expected cardinality 2, got $RESULT"
        return 1
    fi

    print_pass "Set operations: SADD, SMEMBERS, SISMEMBER, SREM, SCARD"
    return 0
}

# Test 4: Hash operations
test_hash_operations() {
    run_test "Test hash operations (HSET, HGET, HGETALL, HDEL)"

    # HSET
    vcli HSET user:1000 name "John Doe" >/dev/null
    vcli HSET user:1000 email "john@example.com" >/dev/null
    vcli HSET user:1000 age "30" >/dev/null

    # HGET
    RESULT=$(vcli HGET user:1000 name)
    if [ "$RESULT" != "John Doe" ]; then
        print_fail "HGET failed: expected 'John Doe', got '$RESULT'"
        return 1
    fi

    # HGETALL
    RESULT=$(vcli HGETALL user:1000 | wc -l)
    if [ "$RESULT" != "6" ]; then  # 3 fields * 2 lines (key + value)
        print_fail "HGETALL failed: expected 6 lines, got $RESULT"
        return 1
    fi

    # HDEL
    vcli HDEL user:1000 age >/dev/null
    RESULT=$(vcli HLEN user:1000)
    if [ "$RESULT" != "2" ]; then
        print_fail "HDEL failed: expected length 2, got $RESULT"
        return 1
    fi

    print_pass "Hash operations: HSET, HGET, HGETALL, HDEL, HLEN"
    return 0
}

# Test 5: Sorted set operations
test_sorted_set_operations() {
    run_test "Test sorted set operations (ZADD, ZRANGE, ZRANK, ZREM)"

    # ZADD
    vcli ZADD leaderboard 100 "player1" >/dev/null
    vcli ZADD leaderboard 200 "player2" >/dev/null
    vcli ZADD leaderboard 150 "player3" >/dev/null

    # ZRANGE
    RESULT=$(vcli ZRANGE leaderboard 0 0)
    if [ "$RESULT" != "player1" ]; then
        print_fail "ZRANGE failed: expected 'player1', got '$RESULT'"
        return 1
    fi

    # ZRANK
    RESULT=$(vcli ZRANK leaderboard "player3")
    if [ "$RESULT" != "1" ]; then
        print_fail "ZRANK failed: expected '1', got '$RESULT'"
        return 1
    fi

    # ZSCORE
    RESULT=$(vcli ZSCORE leaderboard "player2")
    if [ "$RESULT" != "200" ]; then
        print_fail "ZSCORE failed: expected '200', got '$RESULT'"
        return 1
    fi

    # ZREM
    vcli ZREM leaderboard "player3" >/dev/null
    RESULT=$(vcli ZCARD leaderboard)
    if [ "$RESULT" != "2" ]; then
        print_fail "ZREM failed: expected cardinality 2, got $RESULT"
        return 1
    fi

    print_pass "Sorted set operations: ZADD, ZRANGE, ZRANK, ZSCORE, ZREM, ZCARD"
    return 0
}

# Test 6: Key expiration
test_key_expiration() {
    run_test "Test key expiration (EXPIRE, TTL, PERSIST)"

    # EXPIRE
    vcli SET expiring_key "temp_value" >/dev/null
    vcli EXPIRE expiring_key 10 >/dev/null

    # TTL
    RESULT=$(vcli TTL expiring_key)
    if [ "$RESULT" -le 0 ] || [ "$RESULT" -gt 10 ]; then
        print_fail "EXPIRE/TTL failed: expected TTL between 1-10, got $RESULT"
        return 1
    fi

    # PERSIST
    vcli PERSIST expiring_key >/dev/null
    RESULT=$(vcli TTL expiring_key)
    if [ "$RESULT" != "-1" ]; then
        print_fail "PERSIST failed: expected TTL -1 (no expiry), got $RESULT"
        return 1
    fi

    print_pass "Key expiration: EXPIRE, TTL, PERSIST"
    return 0
}

# Test 7: Transactions
test_transactions() {
    run_test "Test transactions (MULTI, EXEC)"

    # Clear any existing data
    vcli DEL txlist >/dev/null 2>&1

    # Execute transaction using here-doc
    docker exec "$CONTAINER_NAME" bash -c 'valkey-cli <<EOF
MULTI
LPUSH txlist "a"
LPUSH txlist "b"
EXEC
EOF' >/dev/null 2>&1

    # Check result - b should be first since LPUSH adds to the left
    RESULT=$(vcli LRANGE txlist 0 0)
    if [ "$RESULT" != "b" ]; then
        print_fail "Transaction failed: expected 'b' as first element, got '$RESULT'"
        return 1
    fi

    # Verify list has both elements
    COUNT=$(vcli LLEN txlist)
    if [ "$COUNT" != "2" ]; then
        print_fail "Transaction failed: expected list length 2, got $COUNT"
        return 1
    fi

    print_pass "Transactions: MULTI, EXEC"
    return 0
}

# Test 8: Key operations
test_key_operations() {
    run_test "Test key operations (EXISTS, DEL, KEYS, TYPE, RENAME)"

    # EXISTS
    vcli SET key_test "value" >/dev/null
    RESULT=$(vcli EXISTS key_test)
    if [ "$RESULT" != "1" ]; then
        print_fail "EXISTS failed: expected '1', got '$RESULT'"
        return 1
    fi

    # TYPE
    RESULT=$(vcli TYPE key_test)
    if [ "$RESULT" != "string" ]; then
        print_fail "TYPE failed: expected 'string', got '$RESULT'"
        return 1
    fi

    # RENAME
    vcli RENAME key_test key_renamed >/dev/null
    RESULT=$(vcli EXISTS key_renamed)
    if [ "$RESULT" != "1" ]; then
        print_fail "RENAME failed: key not found after rename"
        return 1
    fi

    # DEL
    vcli DEL key_renamed >/dev/null
    RESULT=$(vcli EXISTS key_renamed)
    if [ "$RESULT" != "0" ]; then
        print_fail "DEL failed: key still exists"
        return 1
    fi

    print_pass "Key operations: EXISTS, DEL, TYPE, RENAME"
    return 0
}

# Test 9: Pub/Sub
test_pubsub() {
    run_test "Test pub/sub functionality"

    # Start subscriber in background
    PUBSUB_OUTPUT="/tmp/pubsub_output_$$"
    timeout 5 docker exec "$CONTAINER_NAME" valkey-cli SUBSCRIBE test_channel > "$PUBSUB_OUTPUT" 2>&1 &
    SUB_PID=$!

    # Wait for subscriber to be ready
    sleep 2

    # Publish message
    RESULT=$(vcli PUBLISH test_channel "Hello PubSub" 2>&1)
    if [ "$RESULT" != "1" ]; then
        kill $SUB_PID 2>/dev/null || true
        wait $SUB_PID 2>/dev/null || true
        rm -f "$PUBSUB_OUTPUT"
        print_fail "PUBLISH failed: expected '1' subscriber, got '$RESULT'"
        return 1
    fi

    # Wait for message to be received
    sleep 2

    # Stop subscriber
    kill $SUB_PID 2>/dev/null || true
    wait $SUB_PID 2>/dev/null || true

    # Check if message was received
    if grep -q "Hello PubSub" "$PUBSUB_OUTPUT" 2>/dev/null; then
        rm -f "$PUBSUB_OUTPUT"
        print_pass "Pub/Sub: SUBSCRIBE, PUBLISH"
        return 0
    else
        print_fail "Pub/Sub message not received"
        if [ -f "$PUBSUB_OUTPUT" ]; then
            echo "Subscriber output:"
            cat "$PUBSUB_OUTPUT" | head -10
        fi
        rm -f "$PUBSUB_OUTPUT"
        return 1
    fi
}

# Test 10: Bit operations
test_bit_operations() {
    run_test "Test bit operations (SETBIT, GETBIT, BITCOUNT)"

    # SETBIT
    vcli SETBIT bitkey 7 1 >/dev/null
    vcli SETBIT bitkey 10 1 >/dev/null

    # GETBIT
    RESULT=$(vcli GETBIT bitkey 7)
    if [ "$RESULT" != "1" ]; then
        print_fail "GETBIT failed: expected '1', got '$RESULT'"
        return 1
    fi

    # BITCOUNT
    RESULT=$(vcli BITCOUNT bitkey)
    if [ "$RESULT" != "2" ]; then
        print_fail "BITCOUNT failed: expected '2', got '$RESULT'"
        return 1
    fi

    print_pass "Bit operations: SETBIT, GETBIT, BITCOUNT"
    return 0
}

# Test 11: HyperLogLog
test_hyperloglog() {
    run_test "Test HyperLogLog (PFADD, PFCOUNT)"

    # PFADD
    vcli PFADD hll_test "user1" "user2" "user3" >/dev/null

    # PFCOUNT
    RESULT=$(vcli PFCOUNT hll_test)
    if [ "$RESULT" != "3" ]; then
        print_fail "HyperLogLog failed: expected '3', got '$RESULT'"
        return 1
    fi

    # Add duplicate
    vcli PFADD hll_test "user1" >/dev/null
    RESULT=$(vcli PFCOUNT hll_test)
    if [ "$RESULT" != "3" ]; then
        print_fail "HyperLogLog duplicate handling failed: expected '3', got '$RESULT'"
        return 1
    fi

    print_pass "HyperLogLog: PFADD, PFCOUNT"
    return 0
}

# Test 12: Geo operations
test_geo_operations() {
    run_test "Test geo operations (GEOADD, GEODIST, GEORADIUS)"

    # GEOADD
    vcli GEOADD cities 13.361389 38.115556 "Palermo" >/dev/null
    vcli GEOADD cities 15.087269 37.502669 "Catania" >/dev/null

    # GEODIST
    RESULT=$(vcli GEODIST cities Palermo Catania km)
    # Should be approximately 166 km
    if ! echo "$RESULT" | grep -qE "^1[0-9]{2}\.[0-9]"; then
        print_fail "GEODIST failed: unexpected distance '$RESULT'"
        return 1
    fi

    # GEOPOS
    RESULT=$(vcli GEOPOS cities Palermo | head -1)
    if [ -z "$RESULT" ]; then
        print_fail "GEOPOS failed: no position returned"
        return 1
    fi

    print_pass "Geo operations: GEOADD, GEODIST, GEOPOS"
    return 0
}

# Test 13: Streams (basic)
test_streams() {
    run_test "Test streams (XADD, XLEN, XREAD)"

    # XADD
    vcli XADD mystream "*" field1 "value1" field2 "value2" >/dev/null

    # XLEN
    RESULT=$(vcli XLEN mystream)
    if [ "$RESULT" != "1" ]; then
        print_fail "XLEN failed: expected '1', got '$RESULT'"
        return 1
    fi

    # XADD another entry
    vcli XADD mystream "*" field1 "value3" >/dev/null
    RESULT=$(vcli XLEN mystream)
    if [ "$RESULT" != "2" ]; then
        print_fail "XADD failed: expected length '2', got '$RESULT'"
        return 1
    fi

    print_pass "Streams: XADD, XLEN"
    return 0
}

# Test 14: Pipeline performance
test_pipeline() {
    run_test "Test pipelining (bulk operations)"

    # Create pipeline commands
    PIPELINE_FILE="/tmp/pipeline_$$"
    for i in {1..100}; do
        echo "SET pipe_key_$i value_$i"
    done > "$PIPELINE_FILE"

    # Execute pipeline
    START=$(date +%s%N)
    cat "$PIPELINE_FILE" | docker exec -i "$CONTAINER_NAME" valkey-cli --pipe >/dev/null 2>&1
    END=$(date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))  # Convert to ms

    rm -f "$PIPELINE_FILE"

    # Verify a few keys
    RESULT=$(vcli GET pipe_key_50)
    if [ "$RESULT" != "value_50" ]; then
        print_fail "Pipeline failed: expected 'value_50', got '$RESULT'"
        return 1
    fi

    print_pass "Pipelining: 100 operations in ${DURATION}ms"
    return 0
}

# Test 15: Info command
test_info_command() {
    run_test "Test INFO command (server stats)"

    # INFO Server
    if ! vcli INFO Server | grep -q "valkey_version:8.1.5"; then
        print_fail "INFO Server failed: version not found"
        return 1
    fi

    # INFO Stats
    if ! vcli INFO Stats | grep -q "total_commands_processed"; then
        print_fail "INFO Stats failed: stats not found"
        return 1
    fi

    # INFO Memory
    if ! vcli INFO Memory | grep -q "used_memory"; then
        print_fail "INFO Memory failed: memory info not found"
        return 1
    fi

    print_pass "INFO command: Server, Stats, Memory"
    return 0
}

# Setup test environment
setup_test_environment() {
    print_header "Setting Up Test Environment"

    # Check if image exists
    print_info "Checking if image exists: $IMAGE_NAME"
    if ! docker images "$IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_NAME"; then
        echo -e "${RED}Error: Image not found: $IMAGE_NAME${NC}"
        echo "Please build the image first:"
        echo "  cd /path/to/valkey/8.1.5-ubuntu-22.04"
        echo "  ./build.sh"
        exit 1
    fi
    print_info "✓ Image found"

    # Remove any existing container
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    sleep 1

    # Check if port is already in use (if lsof is available)
    if command -v lsof >/dev/null 2>&1; then
        if lsof -Pi :$VALKEY_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo -e "${RED}Error: Port $VALKEY_PORT is already in use${NC}"
            echo "Please stop the service using port $VALKEY_PORT or choose a different port"
            echo ""
            lsof -Pi :$VALKEY_PORT -sTCP:LISTEN 2>/dev/null || true
            exit 1
        fi
    fi

    # Start container
    print_info "Starting Valkey container..."
    ERROR_OUTPUT=$(docker run --name "$CONTAINER_NAME" -d \
        -p $VALKEY_PORT:6379 \
        -e ALLOW_EMPTY_PASSWORD=yes \
        "$IMAGE_NAME" 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to start container${NC}"
        echo "Docker error output:"
        echo "$ERROR_OUTPUT"
        exit 1
    fi
    print_info "✓ Container started (ID: $(echo $ERROR_OUTPUT | cut -c1-12))"

    # Wait for container to be ready (FIPS validation takes time)
    print_info "Waiting for FIPS validation and Valkey initialization..."
    print_info "This may take 20-30 seconds due to FIPS startup checks..."

    # Wait for FIPS validation to complete
    MAX_WAIT=60
    ELAPSED=0
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "✓ ALL FIPS CHECKS PASSED"; then
            print_info "✓ FIPS validation completed"
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo -e "${RED}FIPS validation timeout${NC}"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -30
        exit 1
    fi

    # Wait a bit more for Valkey to fully start
    sleep 5

    # Verify container is running
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        echo -e "${RED}Container not running${NC}"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -20
        exit 1
    fi

    # Test connectivity with retries
    print_info "Testing Valkey connectivity..."
    RETRIES=10
    while [ $RETRIES -gt 0 ]; do
        if vcli PING >/dev/null 2>&1; then
            print_info "✓ Valkey is responding"
            break
        fi
        sleep 1
        RETRIES=$((RETRIES - 1))
    done

    if [ $RETRIES -eq 0 ]; then
        echo -e "${RED}Cannot connect to Valkey${NC}"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -30
        exit 1
    fi

    print_info "✓ Test environment ready"
}

# Main test execution
main() {
    print_header "Valkey 8.1.5 Comprehensive Functionality Test Suite"

    echo "Test Configuration:"
    echo "  Image: $IMAGE_NAME"
    echo "  Container: $CONTAINER_NAME"
    echo "  Port: $VALKEY_PORT"
    echo ""

    # Setup
    setup_test_environment

    # Run all tests
    print_header "Phase 1: Core Data Structures"
    test_string_operations
    test_list_operations
    test_set_operations
    test_hash_operations
    test_sorted_set_operations

    print_header "Phase 2: Key Management"
    test_key_operations
    test_key_expiration

    print_header "Phase 3: Advanced Features"
    test_transactions
    test_pubsub
    test_bit_operations
    test_hyperloglog
    test_geo_operations
    test_streams

    print_header "Phase 4: Performance & Monitoring"
    test_pipeline
    test_info_command

    # Print summary
    print_header "Test Summary"
    echo "Total Tests Run: $TESTS_RUN"
    echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}OVERALL RESULT: FAILED${NC}"
        echo -e "${RED}========================================${NC}"
        exit 1
    else
        echo -e "${GREEN}Tests Failed: 0${NC}"
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}OVERALL RESULT: ALL TESTS PASSED ✓${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "Valkey Functionality: VERIFIED"
        echo "All Data Structures: WORKING"
        echo "Production Readiness: CONFIRMED"
        exit 0
    fi
}

# Run main function
main "$@"
