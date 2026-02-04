# Testing Guide for Valkey FIPS Implementation

**Last Updated:** December 18, 2025

---

## 🆕 NEW: Comprehensive Test Suites

Two new automated test suites have been added:

### 1. Valkey Functionality Test ⭐ **NEW**

Comprehensive testing of all Valkey data structures and operations:

```bash
./tests/test-valkey-functionality.sh
```

**Result:** ✅ **ALL 15 TESTS PASSED**

**What It Tests:**
- ✅ All 5 core data structures (String, List, Set, Hash, Sorted Set)
- ✅ Key management (EXISTS, DEL, EXPIRE, TTL, RENAME)
- ✅ Advanced features (Transactions, Pub/Sub, Streams, Geo, HyperLogLog)
- ✅ Bit operations and pipelining
- ✅ INFO command and monitoring

### 2. FIPS SHA-256 Verification Test

Verify the FIPS SHA-256 implementation (replaces SHA-1):

```bash
./tests/test-fips-sha256.sh
```

**Result:** ✅ **ALL 15 TESTS PASSED**

**What It Tests:**
- ✅ SHA-1 completely replaced with SHA-256
- ✅ Lua script hashing uses SHA-256 (FIPS compliant)
- ✅ No SHA-1 symbols in binary
- ✅ OpenSSL FIPS linkage verified
- ✅ Backward compatibility maintained (40-char hashes)
- ✅ FIPS mode enabled and operational
- ✅ wolfProvider active
- ✅ All Valkey commands working

### Run All Tests

```bash
./tests/run-all-tests.sh
```

Runs all 4 test suites:
1. Valkey Functionality (15 tests)
2. FIPS SHA-256 Verification (15 tests)
3. Quick Test Suite
4. Non-FIPS Algorithm Check

### Documentation

- [TEST-FIPS-SHA256-README.md](TEST-FIPS-SHA256-README.md) - FIPS SHA-256 test details
- [TEST-SUITE-SUMMARY.md](../TEST-SUITE-SUMMARY.md) - Overall test summary

---

## Quick Start

### Option 1: Automated Quick Test (Recommended for Initial Validation)

Run the automated test script to verify all critical functionality:

```bash
cd valkey/8.1.5-ubuntu-22.04

# Make sure you've built the image first
# (see BUILD-FIRST.md below if you haven't)

# Run quick test suite
./tests/quick-test.sh valkey-fips-test:latest
```

**Expected Runtime:** ~2-3 minutes

**What it tests:**
- ✓ Image structure (no system OpenSSL, FIPS libraries present)
- ✓ FIPS validation (all 4 checks pass)
- ✓ OE validation (kernel, CPU, entropy)
- ✓ OpenSSL configuration (wolfProvider loaded)
- ✓ Valkey (version, SSL, library linkage)
- ✓ Full entrypoint validation
- ✓ Container startup and connection

---

### Option 2: Non-FIPS Algorithm Detection (Recommended for Compliance Verification)

Run the comprehensive algorithm checking script to verify 100% FIPS compliance:

```bash
cd valkey/8.1.5-ubuntu-22.04

# Run non-FIPS algorithm detection script
./tests/check-non-fips-algorithms.sh valkey-fips-test:latest
```

**Expected Runtime:** ~2-3 minutes

**What it tests:**
- ✓ Non-FIPS algorithms BLOCKED (MD5, MD4, RC4, DES, Blowfish, etc.)
- ✓ FIPS algorithms WORKING (SHA-256, AES, 3DES, etc.)
- ✓ OpenSSL layer enforcement
- ✓ Valkey TLS cipher suite verification
- ✓ 100% FIPS compliance verification

**Use this script when:**
- Verifying no non-FIPS algorithms can be used
- Preparing for FedRAMP 3PAO audit
- Validating security compliance requirements
- Testing after configuration changes

---

### Option 3: Manual Step-by-Step Testing

For detailed testing and troubleshooting, follow the comprehensive test plan:

```bash
# Open the test plan document
less tests/TEST-PLAN.md

# Or view in your browser/editor
code tests/TEST-PLAN.md
```

The test plan includes:
- Detailed test procedures for each component
- Expected outputs for each test
- Troubleshooting guidance
- Test result documentation template

---

## BUILD FIRST

If you haven't built the image yet:

```bash
cd valkey/8.1.5-ubuntu-22.04

# Ensure wolfSSL password file exists
# (You should have received this password from wolfSSL)
echo "YOUR_WOLFSSL_PASSWORD" > wolfssl_password.txt
chmod 600 wolfssl_password.txt

# Build the image
export DOCKER_BUILDKIT=1
docker buildx build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  --tag valkey-fips-test:latest \
  --file Dockerfile \
  .
```

**Build time:** 8-20 minutes depending on your hardware

---

## Testing Phases

### Phase 1: Build Verification
- Image builds successfully
- No non-FIPS libraries included
- All FIPS components present

### Phase 2: FIPS Validation
- FIPS compile-time flags
- FIPS Known Answer Tests (CAST)
- SHA-256 cryptographic operations
- Entropy source and RNG validation

### Phase 3: Operating Environment
- Kernel version validation
- CPU architecture check
- Hardware feature detection (RDRAND, AES-NI)

### Phase 4: Runtime Validation
- Container starts successfully
- Valkey initializes
- FIPS validation passes on startup
- Database connections work

---

## Quick Manual Tests

### Test 1: FIPS Startup Check

```bash
docker run --rm valkey-fips-test:latest \
  /usr/local/bin/fips-startup-check
```

**Expected:** All 4 validation checks pass

---

### Test 2: Verify No System OpenSSL

```bash
docker run --rm valkey-fips-test:latest \
  find /usr/lib /lib -name "libssl.so*" 2>/dev/null
```

**Expected:** No output (no system OpenSSL found)

---

### Test 3: Verify wolfProvider Loaded

```bash
docker run --rm valkey-fips-test:latest \
  openssl list -providers
```

**Expected:** Shows "wolfprov" provider

---

### Test 4: Full Container Startup

```bash
docker run -d --name test-valkey \
  -e ALLOW_EMPTY_PASSWORD=yes \
  valkey-fips-test:latest

# Wait 30 seconds for startup
sleep 30

# Check logs
docker logs test-valkey 2>&1 | grep "FIPS VALIDATION"

# Check connection
docker exec test-valkey valkey-cli ping

# Cleanup
docker stop test-valkey && docker rm test-valkey
```

---

## Test Results Interpretation

### All Tests Pass ✓
Your implementation is working correctly! Proceed to:
1. Complete remaining documentation tasks
2. Prepare for 3PAO audit
3. Deploy to staging environment

### Some Tests Fail ✗
1. Review the specific error messages
2. Check the troubleshooting section in TEST-PLAN.md
3. Verify build logs for warnings
4. Check that host kernel is >= 6.8.x
5. Verify wolfSSL password is correct

---

## Common Issues

### Issue: "Image not found"
**Solution:** Build the image first (see BUILD FIRST above)

### Issue: "FIPS validation failed"
**Solution:** Check kernel version: `uname -r` (must be >= 6.8.x)

### Issue: "wolfProvider not found"
**Solution:** Check build logs for errors during wolfProvider installation

### Issue: "Container exits immediately"
**Solution:** Check container logs: `docker logs <container_id>`

---

## Getting Help

1. **Review logs:** Check `docker logs <container_id>` for detailed error messages
2. **Review build logs:** Check `build.log` if you saved it during build
3. **Check documentation:**
   - `docs/build-documentation.md` - Build process details
   - `docs/operating-environment.md` - OE requirements
   - `docs/entropy-architecture.md` - RNG/entropy details
4. **Consult TEST-PLAN.md:** Detailed troubleshooting section

---

## Test Files

| File | Purpose | Runtime | Test Scope |
|------|---------|---------|------------|
| `quick-test.sh` | Automated test script for rapid validation | ~2-3 min | Image structure, FIPS validation, startup |
| `check-non-fips-algorithms.sh` | **NEW:** Non-FIPS algorithm detection & verification | ~2-3 min | 100% FIPS compliance, algorithm blocking |
| `crypto-path-validation-valkey.sh` | Comprehensive crypto path testing | ~2-3 min | Binary linkage, OpenSSL config, crypto ops |
| `TEST-PLAN.md` | Comprehensive manual test procedures | Manual | All components, detailed troubleshooting |
| `README.md` | This file - testing quick start guide | Reference | Testing overview and instructions |

### Script Comparison

**When to use which script:**

- **`quick-test.sh`** - First run after building image. Validates basic FIPS setup.
- **`check-non-fips-algorithms.sh`** - Before audit/production. Verifies 100% compliance (no non-FIPS algorithms).
- **`crypto-path-validation-valkey.sh`** - Deep dive validation. Checks crypto library paths and linkage.
- **All three together** - Complete validation suite for production deployment.

---

## Detailed Test Example: Non-FIPS Algorithm Detection

The `check-non-fips-algorithms.sh` script provides comprehensive FIPS compliance verification:

### What Gets Tested

**Non-FIPS Algorithms (Must be BLOCKED):** 9 tests
- **Hash functions:** MD5, MD4, MD2, RIPEMD160 (4 tests)
- **Encryption:** RC4, DES (single), Blowfish, CAST5 (4 tests)
- **Cipher suites:** MD5-based TLS ciphers (1 test)

**FIPS-Approved Algorithms (Must WORK):** 10 tests
- **Hash functions:** SHA-256, SHA-384, SHA-512 (3 tests)
- **Encryption:** AES-128, AES-256, AES-GCM, 3DES (4 tests)
- **Valkey operations:** FIPS cipher suites, SET/GET, INFO (3 tests)

**Test Layers:**
1. **OpenSSL CLI Layer** - Tests `openssl dgst`, `openssl enc` commands
2. **Valkey Layer** - Tests TLS cipher suites and Valkey operations with FIPS crypto

### Running the Script

```bash
# Standard run with default image name
./tests/check-non-fips-algorithms.sh

# With custom image name
./tests/check-non-fips-algorithms.sh valkey-fips:8.1.5-ubuntu-22.04

# Save results to file
./tests/check-non-fips-algorithms.sh valkey-fips:8.1.5-ubuntu-22.04 | tee fips-compliance-report.txt
```

### Expected Output

```
================================================================================
         Valkey FIPS - Non-FIPS Algorithm Detection
================================================================================

[1/5] OpenSSL Layer - Non-FIPS Algorithm Tests
  Testing MD5 hash (non-FIPS) ... ✓ BLOCKED (expected)
  Testing MD4 hash (non-FIPS) ... ✓ BLOCKED (expected)
  Testing RC4 encryption (non-FIPS) ... ✓ BLOCKED (expected)
  ...

[2/5] OpenSSL Layer - FIPS Algorithm Verification
  Testing SHA-256 hash (FIPS-approved) ... ✓ WORKS (expected)
  Testing AES-256-CBC encryption (FIPS-approved) ... ✓ WORKS (expected)
  ...

[3/5] Starting Valkey Container
  ✓ Container started
  ✓ Valkey ready (4s)

[4/5] Valkey Layer - FIPS Cipher Suite Verification
  Testing FIPS-approved cipher suites available ... ✓ WORKS (expected)
  Testing non-FIPS ciphers blocked ... ✓ BLOCKED (expected)
  Testing Valkey basic operations ... ✓ WORKS (expected)
  ...

[5/5] Compliance Report
  Non-FIPS algorithms blocked: 9/9 (100%)
  FIPS algorithms working: 10/10 (100%)

✓ ALL TESTS PASSED - 100% FIPS COMPLIANCE VERIFIED
```

### Interpreting Results

**✓ PASS (100% Compliance):**
- All non-FIPS algorithms are blocked
- All FIPS algorithms work correctly
- Valkey operations use FIPS-approved cryptography
- Image is ready for production/audit

**✗ FAIL (Compliance Issues):**
- Non-FIPS algorithms not fully blocked → Security risk
- FIPS algorithms not working → Functionality issue
- Review test output and check OpenSSL/Valkey configuration

---

## After Testing

Once all tests pass:

1. ✓ Document test results (use template in TEST-PLAN.md)
2. ✓ Save test logs for audit trail
3. ✓ Continue with remaining implementation tasks:
   - Verification guide
   - Reference architecture
   - Crypto path validation script
   - CA certificate fixes

---

## Questions?

Refer to the main documentation in `docs/` directory or the comprehensive test plan in `TEST-PLAN.md`.
