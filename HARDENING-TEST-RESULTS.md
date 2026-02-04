# Hardened Image - FIPS Compliance Test Results

**Date:** December 18, 2025
**Image Tested:** valkey-fips-hardened:8.1.5-ubuntu-22.04
**Test Status:** 🔴 **FAILED - FIPS COMPLIANCE VIOLATIONS DETECTED**

---

## Test Execution Summary

### Image Information
- **Image Name:** valkey-fips-hardened:8.1.5-ubuntu-22.04
- **Image Size:** 405 MB
- **Created:** 34 minutes before test (December 18, 2025)
- **Base Image:** Ubuntu 22.04

---

## Critical Findings

### ❌ Non-FIPS Crypto Libraries Detected

**Test Command:**
```bash
docker run --rm --entrypoint /bin/bash valkey-fips-hardened:8.1.5-ubuntu-22.04 \
  -c "find /usr /lib -name 'libnss3.so*' -o -name 'libgcrypt.so*' 2>/dev/null"
```

**Result:**
```
/usr/lib/x86_64-linux-gnu/libgcrypt.so.20
/usr/lib/x86_64-linux-gnu/libgcrypt.so.20.3.4
/usr/lib/x86_64-linux-gnu/libnss3.so
```

**Impact:** 🔴 **CRITICAL FIPS VIOLATION**
- NSS crypto library present (bypasses FIPS OpenSSL)
- GNU crypto library present (bypasses FIPS OpenSSL)
- Applications can use non-FIPS validated cryptography

---

### ⚠️ System OpenSSL Partially Removed

**Test Command:**
```bash
docker run --rm --entrypoint /bin/bash valkey-fips-hardened:8.1.5-ubuntu-22.04 \
  -c "ls -la /usr/lib/x86_64-linux-gnu/libssl* /usr/lib/x86_64-linux-gnu/libcrypto* 2>&1"
```

**Result:**
```
ls: cannot access '/usr/lib/x86_64-linux-gnu/libcrypto*': No such file or directory
-rw-r--r-- 1 root root 434928 Apr 11  2024 /usr/lib/x86_64-linux-gnu/libssl3.so
```

**Findings:**
- ✅ Main system OpenSSL libraries removed (libssl.so, libcrypto.so)
- ⚠️ Static library file libssl3.so remains
- ✅ Crypto functionality not compromised (Valkey uses FIPS OpenSSL)

**Impact:** 🟡 **MINOR ISSUE** - Static file remains but not used

---

### ✅ Valkey Binary Correctly Linked

**Test Command:**
```bash
docker run --rm --entrypoint /bin/bash valkey-fips-hardened:8.1.5-ubuntu-22.04 \
  -c "ldd /opt/bitnami/valkey/bin/valkey-server | grep -E 'ssl|crypto'"
```

**Result:**
```
libssl.so.3 => /usr/local/openssl/lib64/libssl.so.3 (0x00007613e1d08000)
libcrypto.so.3 => /usr/local/openssl/lib64/libcrypto.so.3 (0x00007613e1884000)
```

**Findings:**
- ✅ Valkey linked to FIPS OpenSSL (/usr/local/openssl/lib64/)
- ✅ NOT linked to system OpenSSL
- ✅ NOT linked to NSS or libgcrypt

**Impact:** ✅ **GOOD** - Valkey itself uses FIPS crypto

---

## Detailed Analysis

### Root Cause

**Dockerfile.hardened:117** installs packages that pull non-FIPS crypto dependencies:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpam-pwquality libpam-runtime aide aide-common auditd rsyslog \
    sudo vim less libnss3-tools libopenscap8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
```

**Problematic packages:**
1. **libnss3-tools** → pulls libnss3 (NSS crypto library)
2. **rsyslog** → pulls libgcrypt20 (GNU crypto library)
3. **libopenscap8** → may pull additional crypto dependencies

**Subsequent cleanup (lines 119-122)** only removes system OpenSSL:
```dockerfile
RUN set -eux; \
    rm -f /usr/lib/x86_64-linux-gnu/libssl.so* /usr/lib/x86_64-linux-gnu/libcrypto.so* \
          /lib/x86_64-linux-gnu/libssl.so* /lib/x86_64-linux-gnu/libcrypto.so* \
          /usr/bin/openssl || true; \
    dpkg --remove --force-depends libssl3 2>/dev/null || true;
```

**Result:** NSS and libgcrypt libraries remain in the image

---

## Compliance Impact Assessment

### FIPS 140-3 Compliance

| Requirement | Status | Details |
|-------------|--------|---------|
| Only FIPS-validated crypto | ❌ **FAIL** | NSS and libgcrypt present |
| No non-FIPS crypto libraries | ❌ **FAIL** | Multiple non-FIPS libs found |
| All apps use FIPS crypto | ⚠️ **PARTIAL** | Valkey uses FIPS, but other tools could use NSS/libgcrypt |
| FIPS OpenSSL installed | ✅ **PASS** | /usr/local/openssl present and active |

**Overall FIPS 140-3 Compliance:** ❌ **NON-COMPLIANT**

---

### FedRAMP Impact

**SC-13 (Cryptographic Protection):**
- Status: ❌ **FAILED**
- Finding: Presence of non-FIPS validated cryptographic libraries (NSS, libgcrypt)
- Severity: **HIGH**
- Impact: **Blocks FedRAMP Authorization**

**3PAO Audit Expectation:**
- Finding will be raised during vulnerability scan
- Must be remediated before ATO (Authority to Operate)
- Required action: Remove all non-FIPS crypto libraries

---

### DISA STIG V2R1 Impact

**V-230221: Operating System Must Use FIPS-Validated Crypto**
- Status: ❌ **OPEN FINDING**
- Category: **CAT I (High Severity)**
- Finding: Non-FIPS crypto libraries present on system
- Remediation: Remove libnss3, libgcrypt20, or provide justification

**STIG Audit Expectation:**
- Automated SCAP scan will detect libnss3 and libgcrypt20
- Manual verification will confirm non-FIPS crypto presence
- Must be fixed for STIG compliance

---

## Comparison: Non-Hardened vs Hardened Images

### Non-Hardened Image (FIPS Compliant)

**Image:** valkey-fips:8.1.5-ubuntu-22.04
**Size:** 182 MB
**FIPS Status:** ✅ **COMPLIANT**

**Crypto Libraries Present:**
```
/usr/local/openssl/lib64/libssl.so.3      (FIPS OpenSSL)
/usr/local/openssl/lib64/libcrypto.so.3   (FIPS OpenSSL)
```

**Non-FIPS Crypto:** None detected
**Test Result:** All 30 tests passed (15 FIPS + 15 functionality)

---

### Hardened Image (FIPS Non-Compliant)

**Image:** valkey-fips-hardened:8.1.5-ubuntu-22.04
**Size:** 405 MB (+223 MB)
**FIPS Status:** ❌ **NON-COMPLIANT**

**Crypto Libraries Present:**
```
/usr/local/openssl/lib64/libssl.so.3           (FIPS OpenSSL) ✅
/usr/local/openssl/lib64/libcrypto.so.3        (FIPS OpenSSL) ✅
/usr/lib/x86_64-linux-gnu/libnss3.so           (NSS crypto) ❌
/usr/lib/x86_64-linux-gnu/libgcrypt.so.20      (GNU crypto) ❌
/usr/lib/x86_64-linux-gnu/libssl3.so           (Static lib) ⚠️
```

**Non-FIPS Crypto:** 2 libraries detected (NSS, libgcrypt)
**Test Result:** FIPS compliance FAILED

---

## Recommended Actions

### Immediate Action Required

**Priority 1: Remove Non-FIPS Crypto Packages**

Create `Dockerfile.hardened-fips-compliant` with corrected package list:

```dockerfile
# STIG/CIS: Install FIPS-safe security packages ONLY
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpam-pwquality \
    libpam-runtime \
    auditd \
    sudo \
    vim \
    less && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# DO NOT INSTALL:
# - libnss3-tools (pulls NSS crypto)
# - rsyslog (pulls libgcrypt20)
# - libopenscap8 (may pull crypto deps)

# Remove system OpenSSL and verify no non-FIPS crypto
RUN set -eux; \
    rm -f /usr/lib/x86_64-linux-gnu/libssl* \
          /usr/lib/x86_64-linux-gnu/libcrypto* \
          /lib/x86_64-linux-gnu/libssl* \
          /lib/x86_64-linux-gnu/libcrypto* \
          /usr/bin/openssl || true; \
    dpkg --remove --force-depends libssl3 2>/dev/null || true; \
    dpkg --remove --force-depends libnss3 libgcrypt20 2>/dev/null || true; \
    # Verify cleanup
    if find /usr /lib -name "libnss3.so*" -o -name "libgcrypt.so*" 2>/dev/null | grep -q .; then \
        echo "ERROR: Non-FIPS crypto libraries present!"; exit 1; \
    fi
```

---

### Alternative Solutions

**Option 1: Minimal Hardening (Recommended)**
- Include: PAM, auditd, sudo, vim, less
- Exclude: rsyslog, libnss3-tools, aide
- Logging: Use container-native logging (Docker/K8s)
- Certificates: Use FIPS OpenSSL CLI
- File integrity: Custom script with FIPS OpenSSL

**Option 2: FIPS-Safe Alternatives**
- Replace rsyslog with syslog-ng (OpenSSL backend)
- Replace libnss3-tools with FIPS OpenSSL CLI
- Replace aide with custom file integrity using FIPS OpenSSL
- Verify all dependencies before installation

**Option 3: Aggressive Cleanup**
- Install packages as needed
- Aggressively remove all non-FIPS crypto libraries
- Use `--force-depends` with caution
- Verify removal with build-time checks

---

## Testing Verification

### After Implementing Fix

**Step 1: Build corrected image**
```bash
docker build \
    --secret id=wolfssl_password,src=wolfssl_password.txt \
    -t valkey-fips:8.1.5-ubuntu-22.04-hardened-fips \
    -f Dockerfile.hardened-fips-compliant \
    .
```

**Step 2: Run FIPS compliance verification**
```bash
./tests/test-hardened-fips-compliance.sh valkey-fips:8.1.5-ubuntu-22.04-hardened-fips
```

**Expected result:**
```
✅ FIPS COMPLIANCE: VERIFIED
No non-FIPS crypto libraries detected
Valkey functionality intact
```

**Step 3: Run full test suite**
```bash
IMAGE_NAME="valkey-fips:8.1.5-ubuntu-22.04-hardened-fips" ./tests/run-all-tests.sh
```

**Expected result:**
```
✅ ALL TEST SUITES PASSED
Test Suite 1 (Valkey Functionality): ✓ PASSED
Test Suite 2 (FIPS SHA-256): ✓ PASSED
Test Suite 3 (Quick Test): ✓ PASSED
Test Suite 4 (Algorithm Check): ✓ PASSED
```

---

## Conclusion

**Current Status:** ❌ **DO NOT DEPLOY TO PRODUCTION**

The current hardened image (`valkey-fips-hardened:8.1.5-ubuntu-22.04`) has **CRITICAL FIPS 140-3 compliance violations** due to the presence of non-FIPS cryptographic libraries (NSS and libgcrypt).

**Impact:**
- ❌ Blocks FedRAMP authorization
- ❌ DISA STIG CAT I finding
- ❌ FIPS 140-3 validation failure
- ❌ 3PAO audit rejection

**Required Action:**
- Remove libnss3-tools, rsyslog, and libopenscap8 from Dockerfile.hardened
- Use FIPS-safe alternatives for logging and certificate management
- Rebuild and retest image
- Verify FIPS compliance before production deployment

**Documentation Reference:**
- See `HARDENING-FIPS-IMPACT-ANALYSIS.md` for detailed package analysis and recommendations
- See `tests/test-hardened-fips-compliance.sh` for automated compliance testing

---

**Test Date:** December 18, 2025
**Test Status:** ❌ **FAILED**
**Next Action:** Implement FIPS-compliant hardening approach
**Approval Status:** 🔴 **NOT APPROVED FOR PRODUCTION**
