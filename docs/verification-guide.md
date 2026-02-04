# FIPS 140-3 Verification Guide for Valkey Container

**Document Version:** 1.0
**Last Updated:** 2025-12-03
**Purpose:** 3PAO Audit and Internal Compliance Validation

---

## 1. Overview

This guide provides comprehensive verification procedures for validating FIPS 140-3 compliance and FedRAMP readiness of the Valkey 8.1.5 FIPS-enabled container image. This document is designed for:

- **3PAO Assessors** - FedRAMP audit validation
- **Internal Security Teams** - Pre-deployment verification
- **Compliance Officers** - Evidence collection for audits
- **DevOps Teams** - Production deployment validation

---

## 2. Verification Checklist

### 2.1 Pre-Verification Requirements

Before beginning verification:

- [ ] Container image built successfully: `valkey-fips:8.1.5-ubuntu22.04`
- [ ] Docker or compatible container runtime available
- [ ] Host system meets OE requirements (kernel >= 6.8.x, x86_64)
- [ ] wolfSSL CMVP certificate available for review
- [ ] Access to build logs and documentation

---

## 3. Core FIPS Compliance Verification

### 3.1 Cryptographic Module Verification

**Objective:** Confirm wolfSSL FIPS v5.2.3 is properly installed and operational

#### Test 3.1.1: Verify wolfSSL FIPS Installation

```bash
# Check wolfSSL library presence
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  ls -lh /usr/local/lib/libwolfssl.so*

# Expected output:
# libwolfssl.so -> libwolfssl.so.42
# libwolfssl.so.42 -> libwolfssl.so.42.0.0
# libwolfssl.so.42.0.0 (actual library file)
```

**Pass Criteria:**
- ✓ wolfSSL library files present
- ✓ Symbolic links correct
- ✓ File size reasonable (~2-3MB)

**Evidence to Collect:**
- Screenshot of command output
- Library file sizes and timestamps

---

#### Test 3.1.2: Verify FIPS Compile-Time Configuration

```bash
# Run FIPS startup check
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  /usr/local/bin/fips-startup-check

# Check for FIPS mode enabled
docker run --rm --entrypoint /bin/bash valkey-fips:8.1.5-ubuntu22.04 \
  -c "strings /usr/local/lib/libwolfssl.so.42 | grep -i 'FIPS'"
```

**Pass Criteria:**
- ✓ Output shows "FIPS mode: ENABLED"
- ✓ FIPS version: 5 or higher
- ✓ Strings output contains "FIPS" references

**Evidence to Collect:**
- Full output of fips-startup-check
- FIPS version information
- Build-time configuration flags

---

#### Test 3.1.3: FIPS Known Answer Tests (CAST)

```bash
# CAST tests are run automatically in fips-startup-check
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  /usr/local/bin/fips-startup-check 2>&1 | grep -A 3 "FIPS CAST"
```

**Expected Output:**
```
[2/4] Running FIPS Known Answer Tests (CAST)...
      ✓ FIPS CAST: PASSED
```

**Pass Criteria:**
- ✓ CAST tests execute without errors
- ✓ Return code: 0 (success)
- ✓ No error messages in output

**Evidence to Collect:**
- CAST test results
- Execution timestamp
- No failures or warnings

---

### 3.2 Operating Environment (OE) Verification

**Objective:** Confirm container operates within CMVP-validated OE

#### Test 3.2.1: Kernel Version Validation

```bash
# Check kernel version
docker run --rm valkey-fips:8.1.5-ubuntu22.04 uname -r

# Verify OE validation at startup
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  /usr/local/bin/fips-entrypoint.sh /bin/true 2>&1 | grep -A 5 "Operating Environment"
```

**Expected Output:**
```
[1/6] Validating Operating Environment (OE) for CMVP compliance...
      Detected kernel: 6.x.x-xx-generic
      ✓ Kernel version: 6.x.x (validated range)
      ✓ CPU architecture: x86_64
```

**Pass Criteria:**
- ✓ Kernel >= 6.8.x (per wolfSSL CMVP requirements)
- ✓ Kernel within validated range
- ✓ OE validation passes without errors

**Evidence to Collect:**
- Kernel version output
- OE validation log
- wolfSSL CMVP certificate showing validated kernels

---

#### Test 3.2.2: CPU Architecture Verification

```bash
# Verify CPU architecture
docker run --rm valkey-fips:8.1.5-ubuntu22.04 uname -m

# Check for required CPU features
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  grep -E "rdrand|aes" /proc/cpuinfo | head -5
```

**Pass Criteria:**
- ✓ Architecture: x86_64
- ✓ RDRAND available (recommended, not required)
- ✓ AES-NI available (recommended, not required)

**Evidence to Collect:**
- CPU architecture output
- CPU features (flags) from /proc/cpuinfo
- OE mapping to wolfSSL CMVP certificate

---

### 3.3 Entropy Source Verification

**Objective:** Validate RNG and entropy sources meet FIPS requirements

#### Test 3.3.1: RNG Initialization Test

```bash
# Full entropy validation (part of fips-startup-check)
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  /usr/local/bin/fips-startup-check 2>&1 | grep -A 10 "entropy source"
```

**Expected Output:**
```
[4/4] Validating entropy source and RNG...
      ✓ RNG initialization: PASSED
      ✓ Random byte generation: PASSED
      ✓ RNG uniqueness test: PASSED
      ✓ RNG quality check: PASSED
      ✓ Entropy source validation: COMPLETE
```

**Pass Criteria:**
- ✓ All 5 entropy checks pass
- ✓ RNG produces unique, non-trivial output
- ✓ No entropy starvation warnings

**Evidence to Collect:**
- Complete entropy validation output
- RNG test results
- Entropy source configuration (Configuration A or B)

---

#### Test 3.3.2: RDRAND Availability Check

```bash
# Check hardware entropy source
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  grep rdrand /proc/cpuinfo
```

**Pass Criteria:**
- ✓ RDRAND present: Preferred (hardware entropy)
- ⚠️ RDRAND absent: Acceptable (uses kernel entropy)

**Evidence to Collect:**
- RDRAND availability status
- Entropy configuration (see docs/entropy-architecture.md)

---

### 3.4 Non-FIPS Library Exclusion Verification

**Objective:** Confirm NO non-FIPS crypto libraries are present

#### Test 3.4.1: System OpenSSL Absence

```bash
# Check for system OpenSSL libraries (should be ABSENT)
docker run --rm --entrypoint /bin/bash valkey-fips:8.1.5-ubuntu22.04 \
  -c "find /usr/lib /lib -name 'libssl.so*' -o -name 'libcrypto.so*' 2>/dev/null"
```

**Expected Output:** (empty - no files found)

**Pass Criteria:**
- ✓ No system OpenSSL libraries in `/usr/lib` or `/lib`
- ✓ No files matching `libssl.so*` or `libcrypto.so*`

**Evidence to Collect:**
- Screenshot showing empty output
- Runtime validation log from entrypoint (Check 5.5)

---

#### Test 3.4.2: Runtime Non-FIPS Library Check

```bash
# Runtime check performed by entrypoint
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  /usr/local/bin/fips-entrypoint.sh /bin/true 2>&1 | grep -A 3 "non-FIPS crypto"
```

**Expected Output:**
```
[5.5/6] Verifying no non-FIPS crypto libraries present...
      ✓ No system OpenSSL libraries found (FIPS-only configuration)
      ✓ All crypto operations will use FIPS OpenSSL + wolfProvider
```

**Pass Criteria:**
- ✓ Check passes without errors
- ✓ No warnings about non-FIPS libraries

**Evidence to Collect:**
- Entrypoint validation log
- Confirmation of FIPS-only enforcement

---

#### Test 3.4.3: Verify libssl3t64 Package Removal

```bash
# Check package status
docker run --rm --entrypoint /bin/bash valkey-fips:8.1.5-ubuntu22.04 \
  -c "dpkg -l | grep libssl"
```

**Expected Output:**
```
(no libssl3t64 package listed, or marked as removed)
```

**Pass Criteria:**
- ✓ libssl3t64 not installed or marked as removed
- ✓ No unexpected SSL/crypto packages present

**Evidence to Collect:**
- Package list output
- dpkg status of crypto-related packages

---

### 3.5 OpenSSL 3 and wolfProvider Verification

**Objective:** Verify OpenSSL 3 with wolfProvider integration

#### Test 3.5.1: OpenSSL Version Check

```bash
# Check OpenSSL version
docker run --rm valkey-fips:8.1.5-ubuntu22.04 openssl version

# Detailed version info
docker run --rm valkey-fips:8.1.5-ubuntu22.04 openssl version -a
```

**Expected Output:**
```
OpenSSL 3.0.15 3 Sep 2024 (Library: OpenSSL 3.0.15 3 Sep 2024)
```

**Pass Criteria:**
- ✓ OpenSSL version: 3.0.15
- ✓ Custom build (not system package)
- ✓ OPENSSLDIR: /usr/local/openssl/ssl

**Evidence to Collect:**
- Full version output
- Build configuration
- Installation paths

---

#### Test 3.5.2: wolfProvider Loading Verification

```bash
# List loaded providers
docker run --rm valkey-fips:8.1.5-ubuntu22.04 openssl list -providers

# Verbose provider info
docker run --rm valkey-fips:8.1.5-ubuntu22.04 openssl list -providers -verbose
```

**Expected Output:**
```
Providers:
  wolfprov
    name: wolfSSL Provider
    version: 1.1.0
    status: active
```

**Pass Criteria:**
- ✓ wolfprov provider listed
- ✓ Status: active
- ✓ Version: 1.1.0 or compatible

**Evidence to Collect:**
- Provider list output
- Provider version and status
- Configuration file (openssl-wolfprov.cnf)

---

#### Test 3.5.3: OpenSSL Configuration File

```bash
# View OpenSSL configuration
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  cat /usr/local/openssl/ssl/openssl.cnf | head -50
```

**Pass Criteria:**
- ✓ Configuration loads wolfprov provider
- ✓ wolfprov is activated
- ✓ Default provider disabled (for strict FIPS mode)

**Evidence to Collect:**
- Full openssl.cnf file
- Provider activation settings

---

### 3.6 Cryptographic Operations Verification

**Objective:** Verify FIPS cryptographic operations work correctly

#### Test 3.6.1: SHA-256 Hash Test

```bash
# Test SHA-256 (FIPS-approved algorithm)
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  bash -c 'echo -n "test" | openssl dgst -sha256'

# Expected: SHA2-256(stdin)= 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
```

**Pass Criteria:**
- ✓ Hash matches known test vector
- ✓ No errors or warnings
- ✓ Operation uses wolfProvider

**Evidence to Collect:**
- Hash output
- Confirmation of correct test vector

---

#### Test 3.6.2: Random Number Generation

```bash
# Generate random bytes
docker run --rm valkey-fips:8.1.5-ubuntu22.04 openssl rand -hex 32

# Multiple runs to verify uniqueness
docker run --rm valkey-fips:8.1.5-ubuntu22.04 openssl rand -hex 32
```

**Pass Criteria:**
- ✓ Generates 32 bytes (64 hex chars)
- ✓ Different output on each run
- ✓ No obvious patterns

**Evidence to Collect:**
- Sample random outputs (multiple runs)
- Confirmation of uniqueness

---

#### Test 3.6.3: AES Encryption/Decryption

```bash
# Test AES-256-CBC encryption
echo "sensitive data" | docker run --rm -i valkey-fips:8.1.5-ubuntu22.04 \
  openssl enc -aes-256-cbc -pass pass:testpass -pbkdf2 -out /tmp/test.enc

# Note: Direct AES without PBKDF2 may be more reliable with wolfProvider 1.1.0
```

**Pass Criteria:**
- ✓ Encryption succeeds
- ✓ Decryption recovers original data
- ✓ Uses FIPS-approved AES

**Evidence to Collect:**
- Encryption/decryption success
- Any warnings (document if PBKDF2 limitations exist)

---

## 4. Valkey-Specific Verification

### 4.1 Valkey Build Verification

**Objective:** Confirm Valkey is built with FIPS OpenSSL

#### Test 4.1.1: Valkey Version

```bash
# Check Valkey version
docker run --rm valkey-fips:8.1.5-ubuntu22.04 valkey --version
```

**Expected Output:**
```
valkey (Valkey) 8.1.5
```

**Pass Criteria:**
- ✓ Valkey version: 8.1.5
- ✓ Custom build (not system package)

**Evidence to Collect:**
- Version output
- Build date and compiler info

---

#### Test 4.1.2: Valkey SSL Linkage

```bash
# Verify Valkey links to FIPS OpenSSL
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  ldd /opt/bitnami/valkeyql/bin/valkey | grep -E "ssl|crypto"
```

**Expected Output:**
```
libssl.so.3 => /usr/local/openssl/lib64/libssl.so.3
libcrypto.so.3 => /usr/local/openssl/lib64/libcrypto.so.3
```

**Pass Criteria:**
- ✓ Links to `/usr/local/openssl/lib64/` (FIPS OpenSSL)
- ✓ Does NOT link to `/usr/lib/` or `/lib/` (system OpenSSL)
- ✓ Correct library versions

**Evidence to Collect:**
- Full ldd output
- Library paths and versions

---

#### Test 4.1.3: Valkey Build Configuration

```bash
# Check Valkey was built with SSL support
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  bash -c "strings /opt/bitnami/valkeyql/bin/valkey | grep -i 'OpenSSL' | head -5"
```

**Pass Criteria:**
- ✓ Shows OpenSSL references
- ✓ Indicates SSL/TLS support compiled in

**Evidence to Collect:**
- OpenSSL references in binary
- Build configuration (from build logs)

---

### 4.2 Valkey Runtime Verification

**Objective:** Verify Valkey operates correctly with FIPS crypto

#### Test 4.2.1: Container Startup Test

```bash
# Start Valkey container
docker run -d --name test-valkey-fips \
  -e ALLOW_EMPTY_PASSWORD=yes \
  valkey-fips:8.1.5-ubuntu22.04

# Wait for initialization
sleep 30

# Check status
docker ps | grep test-valkey-fips

# Check logs for FIPS validation
docker logs test-valkey-fips 2>&1 | grep "FIPS VALIDATION"
```

**Pass Criteria:**
- ✓ Container starts successfully
- ✓ FIPS validation passes in logs
- ✓ Valkey initializes cache
- ✓ No errors in logs

**Evidence to Collect:**
- Container startup logs
- FIPS validation output from logs
- Valkey initialization success

**Cleanup:**
```bash
docker stop test-valkey-fips && docker rm test-valkey-fips
```

---

#### Test 4.2.2: Valkey SSL Configuration

```bash
# Start container (reuse from Test 4.2.1 if still running)
docker run -d --name test-valkey-fips \
  -e ALLOW_EMPTY_PASSWORD=yes \
  valkey-fips:8.1.5-ubuntu22.04

sleep 30

# Check SSL setting
docker exec test-valkey-fips valkey-cli INFO server | grep ssl

# Expected output: on
```

**Pass Criteria:**
- ✓ SSL parameter shows: on
- ✓ Valkey accepts connections

**Evidence to Collect:**
- SSL configuration output
- Valkey configuration file settings

---

#### Test 4.2.3: Valkey Operations with FIPS Crypto

```bash
# Test OpenSSL SHA-256 (used by Valkey for TLS)
docker exec test-valkey-fips \
  bash -c 'echo -n "test" | openssl dgst -sha256'

# Expected: 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08

# Test OpenSSL random number generation (used by Valkey)
docker exec test-valkey-fips \
  openssl rand -hex 16

# Should output 32 hex characters

# Test Valkey SET/GET operations (validates TLS if enabled)
docker exec test-valkey-fips valkey-cli SET fips_test "hello_fips"
docker exec test-valkey-fips valkey-cli GET fips_test

# Expected: "hello_fips"
```

**Pass Criteria:**
- ✓ OpenSSL SHA-256 produces correct hash (FIPS crypto working)
- ✓ OpenSSL random generation works (FIPS DRBG)
- ✓ Valkey operations work correctly
- ✓ All operations use FIPS crypto (via OpenSSL → wolfProvider → wolfSSL)

**Evidence to Collect:**
- OpenSSL crypto test results
- Hash verification
- Random output samples
- Valkey operation logs

---

#### Test 4.2.4: Valkey Connection Test

```bash
# Test client connection
docker exec test-valkey-fips valkey-cli PING

# Expected output: PONG

# Test server info to get version
docker exec test-valkey-fips valkey-cli INFO server | grep valkey_version

# Expected output: valkey_version:8.1.5
```

**Pass Criteria:**
- ✓ valkey-cli PING returns PONG (server accepting connections)
- ✓ INFO command shows correct Valkey version

**Evidence to Collect:**
- Connection status
- Query results
- No SSL/TLS errors

**Cleanup:**
```bash
docker stop test-valkey-fips && docker rm test-valkey-fips
```

---

## 5. FedRAMP Compliance Verification

### 5.1 SCAP/STIG Readiness

**Objective:** Verify hardening baseline is ready to apply

#### Test 5.1.1: Hardening Script Availability

```bash
# Check hardening script exists
ls -lh valkeyql/8.1.5-ubuntu22.04/hardening/ubuntu22.04-stig.sh

# Review script contents
head -50 valkeyql/8.1.5-ubuntu22.04/hardening/ubuntu22.04-stig.sh
```

**Pass Criteria:**
- ✓ Hardening script present
- ✓ Script is executable
- ✓ Script includes:
  - File system hardening
  - Kernel parameter tuning
  - Network hardening
  - SSH hardening
  - Password policies
  - Logging configuration

**Evidence to Collect:**
- Hardening script
- Script documentation
- Hardening baseline checklist

---

#### Test 5.1.2: Security Baseline Checks

```bash
# Check for SUID/SGID files (should be minimal)
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  find / -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | wc -l

# Check for world-writable files (should be minimal/none)
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  find / -type f -perm -0002 ! -path "/proc/*" ! -path "/sys/*" 2>/dev/null | wc -l
```

**Pass Criteria:**
- ✓ Minimal SUID/SGID binaries
- ✓ No unexpected world-writable files
- ✓ Security hardening applied

**Evidence to Collect:**
- SUID/SGID file list
- World-writable file list
- Security baseline comparison

---

### 5.2 Audit Logging Readiness

**Objective:** Verify logging is configured for audit purposes

#### Test 5.2.1: Check Log Configuration

```bash
# Check log directories exist
docker run --rm valkey-fips:8.1.5-ubuntu22.04 ls -la /var/log/

# Check Valkey logging
docker run -d --name test-pg-logs \
  -e ALLOW_EMPTY_PASSWORD=yes \
  valkey-fips:8.1.5-ubuntu22.04

sleep 30

docker exec test-pg-logs ls -la /opt/bitnami/valkeyql/logs/ 2>/dev/null || \
docker exec test-pg-logs ls -la /bitnami/valkeyql/logs/ 2>/dev/null

docker stop test-pg-logs && docker rm test-pg-logs
```

**Pass Criteria:**
- ✓ Log directories configured
- ✓ Valkey logs being written
- ✓ Appropriate permissions on logs

**Evidence to Collect:**
- Log directory structure
- Sample log files
- Log rotation configuration

---

## 6. Documentation Verification

### 6.1 Required Documentation Checklist

**Objective:** Ensure all compliance documentation is present

- [ ] **Operating Environment Documentation**
  - Location: `docs/operating-environment.md`
  - Content: OE specifications, kernel requirements, CPU requirements

- [ ] **Entropy Architecture Documentation**
  - Location: `docs/entropy-architecture.md`
  - Content: RNG configuration, entropy sources, validation

- [ ] **Build Documentation**
  - Location: `docs/build-documentation.md`
  - Content: Build process, component versions, reproduction steps

- [ ] **Verification Guide** (this document)
  - Location: `docs/verification-guide.md`
  - Content: Validation procedures, test cases, evidence collection

- [ ] **Reference Architecture**
  - Location: `docs/reference-architecture.md`
  - Content: Deployment patterns, infrastructure requirements

- [ ] **Hardening Documentation**
  - Location: `hardening/ubuntu22.04-stig.sh`
  - Content: STIG/SCAP baseline implementation

---

### 6.2 wolfSSL CMVP Certificate

**Objective:** Verify CMVP certificate availability and applicability

**Required Documents:**
- [ ] wolfSSL FIPS 140-3 CMVP certificate (PDF)
- [ ] Security Policy document
- [ ] OE list from certificate
- [ ] Algorithm validation certificates

**Verification Steps:**
1. Obtain certificate from wolfSSL or CMVP website
2. Verify certificate number matches wolfSSL version (5.8.2 FIPS v5.2.3)
3. Confirm OE list includes Ubuntu 22.04 kernel range
4. Map container OE to certificate OE

**Evidence to Collect:**
- CMVP certificate copy
- OE mapping document
- Validation date and expiration

---

## 7. Evidence Collection Summary

### 7.1 For 3PAO Audit Package

Collect and organize the following evidence:

**1. Build Evidence:**
- [ ] Build logs showing successful compilation
- [ ] Dockerfile with annotations
- [ ] Component version manifest
- [ ] Build date and builder information

**2. FIPS Validation Evidence:**
- [ ] fips-startup-check full output
- [ ] CAST test results
- [ ] Entropy validation results
- [ ] wolfProvider loading confirmation

**3. OE Evidence:**
- [ ] Kernel version output
- [ ] CPU architecture and features
- [ ] OE validation logs
- [ ] Mapping to wolfSSL CMVP OE

**4. Library Verification Evidence:**
- [ ] ldd output showing FIPS OpenSSL linkage
- [ ] System OpenSSL absence confirmation
- [ ] Package list (dpkg -l)
- [ ] Library inventory

**5. Cryptographic Operation Evidence:**
- [ ] SHA-256 test results
- [ ] RNG test outputs
- [ ] AES encryption tests
- [ ] TLS cipher suites test results

**6. Valkey Evidence:**
- [ ] Container startup logs
- [ ] Valkey version
- [ ] SSL configuration
- [ ] Connection tests

**7. Hardening Evidence:**
- [ ] Security baseline checks
- [ ] SUID/SGID file list
- [ ] Hardening script
- [ ] SCAP scan results (when available)

**8. Documentation:**
- [ ] All docs/*.md files
- [ ] wolfSSL CMVP certificate
- [ ] This verification guide with results

---

## 8. Test Results Template

### 8.1 Verification Report

```
FIPS 140-3 VERIFICATION REPORT
Valkey 8.1.5 FIPS Container

Date: __________________
Tester: __________________
Environment: __________________

CORE FIPS COMPLIANCE:
[ ] 3.1 Cryptographic Module         PASS / FAIL
[ ] 3.2 Operating Environment        PASS / FAIL
[ ] 3.3 Entropy Source               PASS / FAIL
[ ] 3.4 Non-FIPS Exclusion           PASS / FAIL
[ ] 3.5 OpenSSL & wolfProvider       PASS / FAIL
[ ] 3.6 Crypto Operations            PASS / FAIL

VALKEY VERIFICATION:
[ ] 4.1 Build Verification           PASS / FAIL
[ ] 4.2 Runtime Verification         PASS / FAIL

FEDRAMP READINESS:
[ ] 5.1 SCAP/STIG Readiness         PASS / FAIL
[ ] 5.2 Audit Logging               PASS / FAIL

DOCUMENTATION:
[ ] 6.1 Required Documents          COMPLETE / INCOMPLETE
[ ] 6.2 CMVP Certificate            AVAILABLE / PENDING

OVERALL RESULT: PASS / FAIL / PARTIAL

NOTES:
_______________________________________
_______________________________________
_______________________________________

RECOMMENDATIONS:
_______________________________________
_______________________________________
_______________________________________

NEXT STEPS:
_______________________________________
_______________________________________
_______________________________________
```

---

## 9. Troubleshooting Failed Tests

### 9.1 FIPS Validation Failures

**Issue:** FIPS startup check fails

**Common Causes:**
- Kernel version < 6.8.x
- Wrong CPU architecture
- Entropy not available
- wolfSSL not properly installed

**Resolution:**
1. Check kernel version: `uname -r`
2. Verify OE requirements in `docs/operating-environment.md`
3. Review build logs for wolfSSL compilation errors
4. Ensure container runs on compatible host

---

### 9.2 System OpenSSL Still Present

**Issue:** Non-FIPS libraries detected

**Common Causes:**
- Image built before fix
- Dockerfile not updated
- Package dependencies restored OpenSSL

**Resolution:**
1. Rebuild image with latest Dockerfile
2. Verify removal step in build logs
3. Check for unexpected package installations

---

### 9.3 wolfProvider Not Loading

**Issue:** Provider list doesn't show wolfprov

**Common Causes:**
- OPENSSL_MODULES not set
- wolfProvider not installed
- Configuration file error

**Resolution:**
1. Check `$OPENSSL_MODULES` environment variable
2. Verify libwolfprov.so exists
3. Review openssl.cnf syntax

---

## 10. Automated Testing

### 10.1 Quick Test Suite

```bash
# Run automated quick tests
cd valkeyql/8.1.5-ubuntu22.04
./tests/quick-test.sh valkey-fips:8.1.5-ubuntu22.04
```

This runs ~25 automated tests covering:
- Image structure verification
- FIPS validation
- OE validation
- OpenSSL configuration
- Valkey functionality
- Container startup

**Expected Duration:** 2-3 minutes

---

### 10.2 Comprehensive Test Plan

```bash
# Follow detailed test plan
less tests/TEST-PLAN.md
```

This provides manual step-by-step procedures for thorough validation.

---

## 11. Certification and Approval

### 11.1 Sign-Off Checklist

**For Internal Approval:**
- [ ] All verification tests passed
- [ ] Evidence collected and organized
- [ ] Documentation reviewed and complete
- [ ] Security team approval obtained
- [ ] Compliance officer sign-off

**For 3PAO Submission:**
- [ ] Verification report completed
- [ ] wolfSSL CMVP certificate provided
- [ ] All evidence packaged
- [ ] OE mapping documented
- [ ] SCAP scan results included (when available)

---

### 11.2 Ongoing Validation

**Recommendation:** Re-run verification procedures:
- After any container image updates
- After Valkey version upgrades
- After OpenSSL/wolfSSL updates
- Before each major deployment
- As part of continuous compliance program

---

## 12. Contact Information

### 12.1 Support Resources

**Internal Team:**
- Implementation Team: [Contact Info]
- Security Team: [Contact Info]
- Compliance Office: [Contact Info]

**External Resources:**
- wolfSSL Support: support@wolfssl.com
- wolfSSL FIPS Questions: fips@wolfssl.com
- CMVP Information: https://csrc.nist.gov/projects/cryptographic-module-validation-program

---

## Appendices

### Appendix A: Quick Reference Commands

```bash
# FIPS validation
docker run --rm valkey-fips:8.1.5-ubuntu22.04 /usr/local/bin/fips-startup-check

# Check system OpenSSL absence
docker run --rm --entrypoint bash valkey-fips:8.1.5-ubuntu22.04 \
  -c "find /usr/lib /lib -name 'libssl.so*' 2>/dev/null"

# Verify Valkey linkage
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  ldd /opt/bitnami/valkeyql/bin/valkey | grep ssl

# Full entrypoint validation
docker run --rm valkey-fips:8.1.5-ubuntu22.04 \
  /usr/local/bin/fips-entrypoint.sh valkey --version

# Run automated tests
./tests/quick-test.sh valkey-fips:8.1.5-ubuntu22.04
```

### Appendix B: Expected Test Outputs

See individual test sections for detailed expected outputs.

### Appendix C: Evidence Naming Convention

Recommended naming for evidence files:
```
FIPS-VERIFY-<test-section>-<date>.txt
Example: FIPS-VERIFY-3.1.1-20251203.txt
```

---

**Document Status:** Complete - Ready for 3PAO Review

**Version History:**
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-03 | Initial comprehensive verification guide |

**Next Review:** Upon Valkey version update or FIPS module change

**Owner:** Root FIPS Implementation Team

**Classification:** Internal - For Audit/3PAO Review
