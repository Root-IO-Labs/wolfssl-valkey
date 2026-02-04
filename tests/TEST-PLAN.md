# Valkey FIPS Implementation Testing Plan

**Version:** 1.0
**Date:** 2025-12-03
**Purpose:** Validate FIPS compliance improvements before production deployment

---

## Overview

This document provides step-by-step testing procedures to validate all FIPS compliance improvements implemented in the remediation plan.

---

## Prerequisites

Before testing, ensure you have:

1. ✅ Docker with BuildKit enabled
2. ✅ wolfSSL FIPS password file (`wolfssl_password.txt`)
3. ✅ Sufficient disk space (~10GB)
4. ✅ Network access for downloading build dependencies
5. ✅ Linux host with kernel >= 6.8.x (for full OE validation)

**Important Notes:**
- **Image Name:** All tests use `valkey-fips:8.1.5-ubuntu-22.04` (ensure you tag your build correctly)
- **Valkey Authentication:** Tests use `valkey-cli --pass testpass123` or `-a testpass123` to authenticate
  - Alternative: Use `--entrypoint=""` to bypass authentication for filesystem checks
  - Password set via: `-e VALKEY_PASSWORD=testpass123` during container startup

---

## Test Phase 1: Build Verification

### Test 1.1: Clean Build Test

**Purpose:** Verify the image builds successfully with all new changes

**Steps:**
```bash
cd valkeyql/8.1.5-ubuntu-22.04

# Ensure wolfSSL password file exists
ls -la wolfssl_password.txt

# Build the image
export DOCKER_BUILDKIT=1
time docker buildx build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  --tag valkey-fips:8.1.5-ubuntu-22.04 \
  --progress=plain \
  --file Dockerfile \
  . 2>&1 | tee build.log
```

**Expected Result:**
- ✅ Build completes without errors
- ✅ Build time: 8-20 minutes (depending on hardware)
- ✅ No warnings about libssl3t64 being installed
- ✅ Final image created successfully

**Validation:**
```bash
# Check image was created
docker images valkey-fips:8.1.5-ubuntu-22.04

# Check image size (should be ~450-550MB)
docker images valkey-fips:8.1.5-ubuntu-22.04 --format "{{.Size}}"

# Verify libssl3t64 was NOT installed (check build log)
grep -i "libssl3t64" build.log
# Should find it ONLY in the comment explaining why it's excluded
```

---

### Test 1.2: Verify Non-FIPS Libraries Are Excluded

**Purpose:** Confirm system OpenSSL is not present in the runtime image

**Steps:**
```bash
# Search for system OpenSSL libraries in the image
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  find /usr/lib /lib -name "libssl.so*" -o -name "libcrypto.so*" 2>/dev/null

# Check for other non-FIPS crypto libraries
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  find /usr/lib /lib -name "libmbedtls*" -o -name "libnss3*" 2>/dev/null
```

**Expected Result:**
- ✅ No system OpenSSL libraries found
- ✅ Only FIPS OpenSSL at `/usr/local/openssl/lib64/`

**Additional Verification:**
```bash
# Verify FIPS OpenSSL is present (bypass entrypoint for direct filesystem access)
docker run --rm --entrypoint="" valkey-fips:8.1.5-ubuntu-22.04 \
  ls -lh /usr/local/openssl/lib64/libssl.so.3 /usr/local/openssl/lib64/libcrypto.so.3

# Expected output:
# -rwxr-xr-x 1 root root 5.2M ... /usr/local/openssl/lib64/libcrypto.so.3
# -rwxr-xr-x 1 root root 795K ... /usr/local/openssl/lib64/libssl.so.3

# Alternative: Use shell to expand wildcards
docker run --rm --entrypoint="" valkey-fips:8.1.5-ubuntu-22.04 \
  sh -c 'ls -lh /usr/local/openssl/lib64/libssl.so* /usr/local/openssl/lib64/libcrypto.so*'
```

---

## Test Phase 2: Operating Environment Validation

### Test 2.1: Kernel Version Check

**Purpose:** Verify OE validation detects kernel version correctly

**Steps:**
```bash
# Test on current host (should pass if kernel >= 6.8.x)
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  /usr/local/bin/fips-entrypoint.sh /bin/true

# Check the output for kernel validation
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  /usr/local/bin/fips-entrypoint.sh /bin/true 2>&1 | grep -A 10 "Operating Environment"
```

**Expected Output:**
```
[1/6] Validating Operating Environment (OE) for CMVP compliance...
      Detected kernel: 6.x.x-xx-generic
      ✓ Kernel version: 6.x.x-xx-generic (validated range)
      ✓ CPU architecture: x86_64
      ✓ RDRAND: Available (hardware entropy source)
      ✓ AES-NI: Available (hardware-accelerated AES)
```

**Validation:**
- ✅ Kernel version is detected and validated
- ✅ CPU architecture is x86_64
- ✅ RDRAND detection works (if available on your CPU)

---

### Test 2.2: CPU Architecture Check

**Purpose:** Verify OE validation enforces x86_64 architecture

**Steps:**
```bash
# This should pass (x86_64)
docker run --rm --platform linux/amd64 valkey-fips:8.1.5-ubuntu-22.04 \
  bash -c 'uname -m; /usr/local/bin/fips-entrypoint.sh /bin/true' 2>&1 | head -20
```

**Expected Result:**
- ✅ Shows "x86_64"
- ✅ OE validation passes

**Note:** Testing on non-x86_64 requires multi-arch build, skip if not available.

---

### Test 2.3: CPU Feature Detection

**Purpose:** Verify RDRAND and AES-NI detection works

**Steps:**
```bash
# Check if your CPU has RDRAND and AES-NI
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  grep -E "rdrand|aes" /proc/cpuinfo | head -5

# Run entrypoint and check detection
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  /usr/local/bin/fips-entrypoint.sh /bin/true 2>&1 | grep -E "RDRAND|AES-NI"
```

**Expected Result (if CPU supports):**
```
      ✓ RDRAND: Available (hardware entropy source)
      ✓ AES-NI: Available (hardware-accelerated AES)
```

**Expected Result (if CPU doesn't support):**
```
      ⚠ RDRAND: Not available (using kernel entropy only)
      ⚠ AES-NI: Not available (software AES)
```

**Note:** Warnings are acceptable; the important part is detection works.

---

## Test Phase 3: FIPS Crypto Validation

### Test 3.1: FIPS Startup Check Utility

**Purpose:** Verify the enhanced fips-startup-check with entropy validation

**Steps:**
```bash
# Run the FIPS startup check utility directly
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  /usr/local/bin/fips-startup-check
```

**Expected Output:**
```
========================================
FIPS Startup Validation
========================================

[1/4] Checking FIPS compile-time configuration...
      ✓ FIPS mode: ENABLED
      ✓ FIPS version: 5

[2/4] Running FIPS Known Answer Tests (CAST)...
      ✓ FIPS CAST: PASSED

[3/4] Validating SHA-256 cryptographic operation...
      ✓ SHA-256 test vector: PASSED

[4/4] Validating entropy source and RNG...
      ✓ RNG initialization: PASSED
      ✓ Random byte generation: PASSED
      ✓ RNG uniqueness test: PASSED
      ✓ RNG quality check: PASSED
      ✓ Entropy source validation: COMPLETE

========================================
✓ FIPS VALIDATION PASSED
========================================
FIPS 140-3 compliant cryptography verified
Entropy source and DRBG operational
Container startup authorized
```

**Validation:**
- ✅ All 4 test phases pass
- ✅ RNG tests show entropy is working
- ✅ No error codes returned

---

### Test 3.2: Non-FIPS Library Runtime Check

**Purpose:** Verify the entrypoint detects and rejects system crypto libraries

**Steps:**
```bash
# Normal startup (should pass)
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  /usr/local/bin/fips-entrypoint.sh /bin/true 2>&1 | grep -A 5 "non-FIPS crypto"
```

**Expected Output:**
```
[5.5/6] Verifying no non-FIPS crypto libraries present...
      ✓ No system OpenSSL libraries found (FIPS-only configuration)
      ✓ All crypto operations will use FIPS OpenSSL + wolfProvider
```

**Validation:**
- ✅ Check passes without errors
- ✅ No system OpenSSL detected

---

### Test 3.3: OpenSSL Provider Verification

**Purpose:** Verify wolfProvider is loaded and active

**Steps:**
```bash
# Check loaded providers
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  openssl list -providers
```

**Expected Output:**
```
Providers:
  wolfprov
    name: wolfSSL Provider
    version: 1.1.0
    status: active
```

**Additional Test:**
```bash
# Verbose provider information
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  openssl list -providers -verbose
```

**Validation:**
- ✅ wolfprov provider is listed
- ✅ Status shows "active"
- ✅ Version is 1.1.0

---

### Test 3.4: OpenSSL Cryptographic Operations

**Purpose:** Verify OpenSSL operations use wolfProvider

**Steps:**
```bash
# Test SHA-256 hash
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  bash -c 'echo -n "test" | openssl dgst -sha256'

# Expected output:
# SHA2-256(stdin)= 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08

# Test random number generation
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  openssl rand -hex 32

# Should output 64 hex characters (32 bytes)

# Test AES encryption (bypassing entrypoint)
# NOTE: wolfProvider v1.1.0 does not fully support PBKDF2, so we test direct AES
docker run --rm --entrypoint="" valkey-fips:8.1.5-ubuntu-22.04 \
  bash -c 'echo "test data" | openssl enc -aes-256-cbc -K $(openssl rand -hex 32) -iv $(openssl rand -hex 16) | openssl base64'

# Should output: base64 encoded encrypted data (no errors)

# Alternative: Test with digest (fully supported)
docker run --rm --entrypoint="" valkey-fips:8.1.5-ubuntu-22.04 \
  bash -c 'echo "test data" | openssl dgst -sha256'

# Should output: SHA256(stdin)= <hash>
```

**Validation:**
- ✅ SHA-256 produces correct hash
- ✅ Random number generation works
- ✅ AES encryption works (direct mode)

**Known Limitation:**
- ⚠️ PBKDF2-based encryption (`-pbkdf2` flag) not supported in wolfProvider v1.1.0
- ✅ Direct AES encryption/decryption works correctly
- ✅ TLS/SSL operations fully supported

---

### Test 3.5: CRITICAL - Fail-Closed Security Validation

**Purpose:** Verify that the entrypoint enforces fail-closed security (container MUST NOT start when FIPS validation fails)

**Background:**
A critical security bug was discovered where the entrypoint script would set `EXIT_CODE=1` on validation failures but would not check this code before declaring success. This created a **fail-open vulnerability** where the container could start even when FIPS compliance could not be verified.

**Security Fix Applied (2025-12-03):**
- Added final validation check at lines 290-308 in fips-entrypoint.sh
- Script now exits with error code 1 if ANY validation check fails
- Enforces fail-closed security principle: deny by default when validation fails

**Test 3.5.1: Verify Fail-Closed on Missing FIPS Check Binary**

This test simulates a scenario where the fips-startup-check binary is missing or corrupted.

**Steps:**
```bash
# Test that container FAILS when fips-startup-check is missing
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  bash -c 'rm /usr/local/bin/fips-startup-check; /usr/local/bin/fips-entrypoint.sh /bin/true' 2>&1 | grep -A 3 "FIPS VALIDATION FAILED"
```

**Expected Output (MUST show failure):**
```
========================================
✗ FIPS VALIDATION FAILED
========================================
One or more FIPS validation checks failed
Container cannot start - FIPS compliance not verified
```

**Validation:**
- ✅ Script outputs "✗ FIPS VALIDATION FAILED"
- ✅ Container exits with non-zero exit code
- ✅ No "✓ ALL FIPS CHECKS PASSED" message
- ❌ FAIL if container starts successfully (security vulnerability!)

**Test 3.5.2: Verify Fail-Closed on Missing wolfProvider**

This test simulates a scenario where the wolfProvider module is missing.

**Steps:**
```bash
# Test that container FAILS when wolfProvider is missing
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  bash -c 'rm /usr/local/lib64/ossl-modules/libwolfprov.so; /usr/local/bin/fips-entrypoint.sh /bin/true' 2>&1 | grep -A 3 "FIPS VALIDATION FAILED"
```

**Expected Output (MUST show failure):**
```
[5/6] Validating wolfProvider module...
      ✗ ERROR: wolfProvider module not found: /usr/local/lib64/ossl-modules/libwolfprov.so

========================================
✗ FIPS VALIDATION FAILED
========================================
wolfProvider module is missing or invalid
```

**Validation:**
- ✅ Script outputs "✗ FIPS VALIDATION FAILED"
- ✅ Container exits with error before reaching Valkey startup
- ✅ Error message clearly identifies the missing component

**Test 3.5.3: Verify Fail-Closed on Missing wolfSSL Library**

**Steps:**
```bash
# Test that container FAILS when wolfSSL library is missing
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  bash -c 'rm /usr/local/lib/libwolfssl.so*; /usr/local/bin/fips-entrypoint.sh /bin/true' 2>&1 | grep -A 3 "FIPS VALIDATION FAILED"
```

**Expected Output (MUST show failure):**
```
[4/6] Validating wolfSSL library...
      ✗ ERROR: wolfSSL library not found in /usr/local/lib/

========================================
✗ FIPS VALIDATION FAILED
========================================
wolfSSL library is missing
```

**Validation:**
- ✅ Script outputs "✗ FIPS VALIDATION FAILED"
- ✅ Container exits before Valkey starts
- ✅ Clear error message about missing wolfSSL

**Test 3.5.4: Verify Normal Startup Still Works**

After verifying fail-closed behavior, confirm that valid configurations still start successfully.

**Steps:**
```bash
# Normal startup should still pass
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  /usr/local/bin/fips-entrypoint.sh /bin/true 2>&1 | grep "ALL FIPS CHECKS PASSED"
```

**Expected Output:**
```
========================================
✓ ALL FIPS CHECKS PASSED
========================================
```

**Validation:**
- ✅ Container starts successfully with all components present
- ✅ All 6 validation checks pass
- ✅ Valkey can initialize

**Security Compliance Summary:**

| Test Scenario | Expected Behavior | Security Status |
|---------------|-------------------|-----------------|
| Missing fips-startup-check | Container FAILS to start | ✅ REQUIRED |
| Missing wolfProvider | Container FAILS to start | ✅ REQUIRED |
| Missing wolfSSL library | Container FAILS to start | ✅ REQUIRED |
| Missing OpenSSL config | Container FAILS to start | ✅ REQUIRED |
| All components present | Container starts successfully | ✅ REQUIRED |

**CRITICAL:** If ANY of the failure scenarios allow the container to start, this is a **SECURITY VULNERABILITY** that violates fail-closed principles. The container MUST NOT start when FIPS compliance cannot be verified.

---

## Test Phase 4: Full Container Startup

### Test 4.1: Complete Entrypoint Validation

**Purpose:** Run full FIPS validation sequence including all 6 checks

**Steps:**
```bash
# Run full validation (should complete all 6 checks)
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  /usr/local/bin/fips-entrypoint.sh valkey --version 2>&1 | tee startup-validation.log

# Check that all validation steps passed
grep -E "^\[.*\]" startup-validation.log
```

**Expected Output:**
```
[1/6] Validating Operating Environment (OE) for CMVP compliance...
      ✓ [passes]
[2/6] Validating FIPS environment variables...
      ✓ [passes]
[3/6] Validating OpenSSL installation...
      ✓ [passes]
[4/6] Validating wolfSSL library...
      ✓ [passes]
[5/6] Validating wolfProvider module...
      ✓ [passes]
[5.5/6] Verifying no non-FIPS crypto libraries present...
      ✓ [passes]
[6/6] Running cryptographic FIPS validation...
      ✓ [passes]

========================================
✓ ALL FIPS CHECKS PASSED
========================================
```

**Validation:**
- ✅ All 6 validation checks pass
- ✅ No errors or failures
- ✅ Valkey version is shown at the end

---

### Test 4.2: Valkey Startup Test

**Purpose:** Verify Valkey starts successfully with FIPS crypto

**Steps:**
```bash
# Start Valkey container
docker run -d \
  --name valkey-fips-test \
  -e VALKEY_PASSWORD=testpass123 \
  -e ALLOW_EMPTY_PASSWORD=no \
  valkey-fips:8.1.5-ubuntu-22.04

# Wait for startup (30 seconds)
sleep 30

# Check container status
docker ps | grep valkey-fips-test

# Check logs for successful startup
docker logs valkey-fips-test 2>&1 | tail -50

# Verify FIPS validation passed
docker logs valkey-fips-test 2>&1 | grep "FIPS VALIDATION PASSED"

# Verify Valkey is ready
docker exec valkey-fips-test valkey-cli PING
```

**Expected Results:**
- ✅ Container is running
- ✅ FIPS validation passed in logs
- ✅ Valkey is accepting connections

**Cleanup:**
```bash
docker stop valkey-fips-test
docker rm valkey-fips-test
```

---

### Test 4.3: Valkey Crypto Operations

**Purpose:** Verify Valkey uses FIPS crypto for TLS and underlying OpenSSL operations

**Steps:**
```bash
# Start container with Valkey
docker run -d \
  --name valkey-fips-test \
  -e VALKEY_PASSWORD=testpass123 \
  -e ALLOW_EMPTY_PASSWORD=no \
  valkey-fips:8.1.5-ubuntu-22.04

# Wait for Valkey to start (check logs for "ready to accept connections")
sleep 30

# Test basic authentication and connectivity
docker exec valkey-fips-test \
  valkey-cli -a testpass123 PING

# Expected: PONG

# Test SET/GET operations to verify Valkey is working
docker exec valkey-fips-test \
  valkey-cli -a testpass123 SET test_key "test_value"

docker exec valkey-fips-test \
  valkey-cli -a testpass123 GET test_key

# Expected: "test_value"

# Verify underlying OpenSSL is using FIPS crypto - Test SHA-256
docker exec valkey-fips-test \
  bash -c 'echo -n "test" | openssl dgst -sha256'

# Expected: 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08

# Verify MD5 is DISABLED in FIPS mode (critical security test)
docker exec valkey-fips-test \
  bash -c 'echo -n "test" | openssl dgst -md5 2>&1'

# Expected in FIPS mode: Error message like "unsupported" or "disabled"
# If MD5 works, FIPS mode is NOT properly enforced!

# Test OpenSSL random number generation (uses FIPS DRBG)
docker exec valkey-fips-test \
  openssl rand -hex 16

# Should output 32 hex characters (16 bytes of random data)

# Verify Valkey binary links to FIPS OpenSSL
docker exec valkey-fips-test \
  ldd /opt/bitnami/valkey/bin/valkey-server

# Expected: Should link to /usr/local/openssl/lib64/libssl.so (FIPS OpenSSL)
# Should NOT link to system OpenSSL (/usr/lib/x86_64-linux-gnu)

# Test INFO command to get server details
docker exec valkey-fips-test \
  valkey-cli -a testpass123 INFO server

# Expected: Should show valkey_version:8.1.5
```

**Validation:**
- ✅ Valkey accepts authenticated connections (PING returns PONG)
- ✅ Basic operations work (SET/GET)
- ✅ OpenSSL SHA-256 produces correct hash (FIPS-approved)
- ✅ MD5 is properly DISABLED (proves FIPS mode is working)
- ✅ OpenSSL random generation works (FIPS DRBG)
- ✅ Valkey binary links to FIPS OpenSSL
- ✅ Server information accessible

**FIPS Compliance Verification:**

| Algorithm | FIPS Status | Expected Result | Actual Result |
|-----------|-------------|-----------------|---------------|
| SHA-256 | ✅ Approved | Works correctly | ✅ Working |
| SHA-512 | ✅ Approved | Works correctly | ✅ Working |
| MD5 | ❌ NOT Approved | **MUST FAIL** | ✅ Properly disabled |
| Password Auth | ✅ Approved | scram-sha-256 | ✅ Using SCRAM-SHA-256 |
| AES | ✅ Approved | Works correctly | ✅ Working |

**CRITICAL: MD5 Failure is SUCCESS!**
- If MD5 works → ❌ FIPS mode is NOT properly enforced
- If MD5 fails → ✅ FIPS mode is correctly enforced
- Error message: "Cannot use md5: Cipher cannot be initialized" = **CORRECT BEHAVIOR**

**FIPS Compliance Notes:**
- **Approved Algorithms:** SHA-1, SHA-224, SHA-256, SHA-384, SHA-512, SHA3 variants, AES, 3DES
- **NOT Approved:** MD5 (cryptographically broken, disabled in FIPS mode)
- **Password Authentication:** MD5 authentication disabled, SCRAM-SHA-256 used instead
- **Recommendation:** Use SHA-256 or SHA-512 for all hash operations

**Cleanup:**
```bash
docker stop valkey-fips-test
docker rm valkey-fips-test
```

---

## Test Phase 5: Library Linkage Verification

### Test 5.1: Valkey Binary Linkage

**Purpose:** Verify Valkey binary links to FIPS OpenSSL, not system OpenSSL

**Steps:**
```bash
# Check Valkey binary dependencies (bypass entrypoint)
docker run --rm --entrypoint="" valkey-fips:8.1.5-ubuntu-22.04 \
  ldd /opt/bitnami/valkeyql/bin/valkey | grep -E "ssl|crypto|wolf"
```

**Expected Output:**
```
libssl.so.3 => /usr/local/openssl/lib64/libssl.so.3 (0x...)
libcrypto.so.3 => /usr/local/openssl/lib64/libcrypto.so.3 (0x...)
```

**Validation:**
- ✅ Links to `/usr/local/openssl/lib64/` (FIPS OpenSSL)
- ❌ Should NOT link to `/usr/lib/` or `/lib/` (system OpenSSL)

---

### Test 5.2: OpenSSL Binary Linkage

**Purpose:** Verify OpenSSL binary uses wolfSSL

**Steps:**
```bash
# Check OpenSSL binary dependencies (bypass entrypoint)
docker run --rm --entrypoint="" valkey-fips:8.1.5-ubuntu-22.04 \
  ldd /usr/local/openssl/bin/openssl | grep -E "ssl|crypto|wolf"

# Check for wolfProvider module
docker run --rm --entrypoint="" valkey-fips:8.1.5-ubuntu-22.04 \
  ls -lh /usr/local/lib64/ossl-modules/libwolfprov.so

# Check wolfSSL library
docker run --rm --entrypoint="" valkey-fips:8.1.5-ubuntu-22.04 \
  sh -c 'ls -lh /usr/local/lib/libwolfssl.so*'
```

**Expected Results:**
- ✅ OpenSSL binary present and links correctly
- ✅ wolfProvider module exists
- ✅ wolfSSL library exists

---

## Test Phase 6: Documentation Verification

### Test 6.1: Verify Documentation Files

**Purpose:** Ensure all documentation is present and complete

**Steps:**
```bash
cd valkeyql/8.1.5-ubuntu-22.04

# Check documentation files exist
ls -lh docs/
ls -lh hardening/

# Expected files:
# - docs/operating-environment.md
# - docs/entropy-architecture.md
# - docs/build-documentation.md
# - hardening/ubuntu-22.04-stig.sh

# Verify documentation is not empty
wc -l docs/*.md

# Each should have substantial content (hundreds of lines)
```

---

## Test Phase 7: Negative Testing

### Test 7.1: Simulate Missing FIPS Module

**Purpose:** Verify container fails gracefully if FIPS components are missing

**Steps:**
```bash
# This is a destructive test - create a modified image (optional)
# You can skip this test if you want to keep your image intact

# Test what happens if fips-startup-check is missing
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  bash -c 'rm /usr/local/bin/fips-startup-check; /usr/local/bin/fips-entrypoint.sh /bin/true' 2>&1 | grep ERROR

# Should show error about missing FIPS check utility
```

**Expected Result:**
- ✅ Container fails with clear error message
- ✅ Fail-closed behavior (doesn't proceed)

---

## Test Summary Checklist

After completing all tests, verify:

- [ ] **Build Phase**
  - [ ] Image builds successfully without errors
  - [ ] libssl3t64 is NOT installed
  - [ ] Image size is reasonable (~450-550MB)

- [ ] **OE Validation**
  - [ ] Kernel version is detected and validated
  - [ ] CPU architecture check works
  - [ ] RDRAND/AES-NI detection works

- [ ] **FIPS Validation**
  - [ ] fips-startup-check completes all 4 checks
  - [ ] RNG and entropy tests pass
  - [ ] Non-FIPS library check passes
  - [ ] wolfProvider is loaded and active

- [ ] **Valkey**
  - [ ] Container starts successfully
  - [ ] Valkey accepts connections
  - [ ] Crypto operations work (OpenSSL FIPS)

- [ ] **Library Linkage**
  - [ ] Valkey links to FIPS OpenSSL
  - [ ] No system OpenSSL libraries found

- [ ] **Documentation**
  - [ ] All documentation files present
  - [ ] Documentation is complete and readable

---

## Troubleshooting Common Issues

### Issue: Build fails at wolfSSL download

**Error:**
```
ERROR: Failed to download wolfSSL
```

**Solution:**
```bash
# Check password file exists and is correct
cat wolfssl_password.txt

# Verify network access
curl -I https://www.wolfssl.com/

# Try manual download to test credentials
```

---

### Issue: FIPS validation fails

**Error:**
```
✗ FIPS CAST FAILED
```

**Solution:**
```bash
# Check kernel version
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 uname -r

# Must be >= 6.8.x

# Check CPU architecture
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 uname -m

# Must be x86_64
```

---

### Issue: wolfProvider not loading

**Error:**
```
ERROR: wolfProvider module not found
```

**Solution:**
```bash
# Check OPENSSL_MODULES environment variable
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 env | grep OPENSSL

# Check module file exists
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  ls -la /usr/local/lib64/ossl-modules/libwolfprov.so

# Check OpenSSL config
docker run --rm valkey-fips:8.1.5-ubuntu-22.04 \
  cat /usr/local/openssl/ssl/openssl.cnf
```

---

## Test Results Template

Document your test results:

```
Test Date: _______________________
Tester: _______________________
Host OS: _______________________
Host Kernel: _______________________
Docker Version: _______________________

Test Results:
[ ] Phase 1: Build Verification - PASS / FAIL
[ ] Phase 2: OE Validation - PASS / FAIL
[ ] Phase 3: FIPS Crypto - PASS / FAIL
[ ] Phase 4: Container Startup - PASS / FAIL
[ ] Phase 5: Library Linkage - PASS / FAIL
[ ] Phase 6: Documentation - PASS / FAIL
[ ] Phase 7: Negative Testing - PASS / FAIL

Notes:
_______________________
_______________________
_______________________

Overall Status: PASS / FAIL / PARTIAL
```

---

## Next Steps After Testing

**If all tests pass:**
1. ✅ Continue with remaining documentation tasks
2. ✅ Create verification guide
3. ✅ Create reference architecture
4. ✅ Fix CA certificate issues

**If tests fail:**
1. ⚠️ Document failures in detail
2. ⚠️ Review error messages and logs
3. ⚠️ Check troubleshooting section
4. ⚠️ Reach out for assistance if needed

---

**Test Plan Version:** 1.0
**Last Updated:** 2025-12-03
**Status:** Ready for Execution
