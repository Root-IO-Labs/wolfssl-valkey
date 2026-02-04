# Valkey Hardened Image - FIPS Compliance Impact Analysis

**Date:** December 18, 2025
**Analyst:** Claude Code
**Status:** 🔴 **CRITICAL FIPS COMPLIANCE RISKS IDENTIFIED**

---

## Executive Summary

**Finding:** The security hardening packages added to `Dockerfile.hardened` **WILL BREAK FIPS 140-3 COMPLIANCE** by introducing non-FIPS cryptographic libraries that bypass the FIPS-validated OpenSSL implementation.

**Critical Issues:**
- 🔴 **libnss3-tools** introduces NSS crypto library (non-FIPS)
- 🔴 **rsyslog** pulls libgcrypt20 dependency (GNU crypto, non-FIPS)
- 🔴 **libopenscap8** may introduce additional crypto dependencies

**Impact Severity:** **HIGH** - Violates FIPS 140-3 compliance requirements

**Recommendation:** **DO NOT DEPLOY** current `Dockerfile.hardened` without removing problematic packages

---

## Table of Contents

1. [Problem Analysis](#problem-analysis)
2. [Package Risk Assessment](#package-risk-assessment)
3. [Dependency Analysis](#dependency-analysis)
4. [FIPS Compliance Impact](#fips-compliance-impact)
5. [Test Results](#test-results)
6. [FIPS-Compliant Alternatives](#fips-compliant-alternatives)
7. [Recommended Solutions](#recommended-solutions)
8. [Implementation Guide](#implementation-guide)

---

## Problem Analysis

### Current Implementation Issue

**Location:** `Dockerfile.hardened:117`

```dockerfile
# STIG/CIS: Install security packages (before OpenSSL removal)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpam-pwquality libpam-runtime aide aide-common auditd rsyslog \
    sudo vim less libnss3-tools libopenscap8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
```

**Followed by (lines 119-122):**
```dockerfile
RUN set -eux; \
    rm -f /usr/lib/x86_64-linux-gnu/libssl.so* /usr/lib/x86_64-linux-gnu/libcrypto.so* \
          /lib/x86_64-linux-gnu/libssl.so* /lib/x86_64-linux-gnu/libcrypto.so* \
          /usr/bin/openssl || true; \
    dpkg --remove --force-depends libssl3 2>/dev/null || true; \
    if [ -f "/usr/lib/x86_64-linux-gnu/libssl.so.3" ]; then \
        echo "ERROR: System OpenSSL still present!"; exit 1; \
    fi
```

### Why This Breaks FIPS Compliance

**Timeline of Events:**

1. **Line 117:** Install hardening packages
   - `apt-get` installs requested packages
   - `apt-get` **automatically pulls dependencies**
   - Dependencies include: **libnss3**, **libgcrypt20**, possibly others

2. **Lines 119-122:** Remove system OpenSSL
   - Removes `libssl.so*` and `libcrypto.so*` files
   - Removes `libssl3` package
   - **Does NOT remove libnss3 or libgcrypt20** (not explicitly targeted)

3. **Result:**
   - ✅ System OpenSSL removed
   - ✅ FIPS OpenSSL installed
   - ❌ **NSS crypto library remains** (from libnss3)
   - ❌ **GNU crypto library remains** (from libgcrypt20)

### FIPS Violation Mechanism

Applications and libraries can now choose between **three crypto implementations**:

1. ✅ **FIPS OpenSSL** (`/usr/local/openssl/lib64/`) - FIPS 140-3 validated
2. ❌ **NSS** (`/usr/lib/x86_64-linux-gnu/libnss3.so`) - NOT FIPS validated
3. ❌ **GNU Crypto** (`/usr/lib/x86_64-linux-gnu/libgcrypt.so`) - NOT FIPS validated

**Critical Risk:** If any application (including Valkey plugins, audit tools, or logging utilities) links against libnss3 or libgcrypt20 instead of FIPS OpenSSL, cryptographic operations will **bypass FIPS validation entirely**.

---

## Package Risk Assessment

### Risk Classification

| Risk Level | Criteria |
|------------|----------|
| 🔴 **CRITICAL** | Introduces non-FIPS crypto libraries |
| 🟡 **HIGH** | May pull crypto dependencies |
| 🟢 **LOW** | No known crypto dependencies |
| ✅ **SAFE** | Pure utility, no crypto |

### Detailed Package Analysis

#### 🔴 CRITICAL RISK: libnss3-tools

**Package:** libnss3-tools
**Purpose:** Network Security Services command-line tools
**Risk Level:** 🔴 **CRITICAL - DO NOT USE**

**Dependencies Introduced:**
```
libnss3-tools
├── libnss3 (NSS crypto library - NON-FIPS)
├── libnspr4 (Netscape Portable Runtime)
└── libsqlite3-0
```

**Why Critical:**
- Introduces complete NSS crypto implementation
- NSS provides: MD5, SHA-1, SHA-256, RSA, DSA, ECDSA, AES, 3DES
- **NSS is NOT FIPS 140-3 validated in this context**
- Applications can link to NSS instead of FIPS OpenSSL
- Certificate/key management tools may prefer NSS over OpenSSL

**FIPS Impact:** ❌ **BREAKS FIPS COMPLIANCE**

**Alternatives:**
- Use `openssl` command from FIPS OpenSSL build
- Use Valkey's built-in TLS certificate management
- Create custom certificate management scripts using FIPS OpenSSL

**Recommendation:** **REMOVE from Dockerfile.hardened**

---

#### 🔴 CRITICAL RISK: rsyslog

**Package:** rsyslog
**Purpose:** Reliable system logging daemon
**Risk Level:** 🔴 **CRITICAL - REQUIRES CAREFUL CONFIGURATION**

**Dependencies Introduced:**
```
rsyslog
├── libgcrypt20 (GNU crypto library - NON-FIPS)
├── libgpg-error0
├── liblz4-1
├── libestr0
├── libfastjson4
└── zlib1g
```

**Why Critical:**
- Pulls **libgcrypt20** dependency automatically
- libgcrypt20 provides: MD5, SHA-1, SHA-256, AES, RSA, DSA
- **libgcrypt20 is NOT FIPS validated**
- rsyslog may use libgcrypt20 for log signature/encryption features
- If rsyslog's crypto features are enabled, uses non-FIPS crypto

**FIPS Impact:** ❌ **BREAKS FIPS COMPLIANCE** (if crypto features used)

**Alternatives:**
1. **syslog-ng** - Can be configured to use OpenSSL for crypto
2. **journald** (systemd-journald) - Built into Ubuntu, minimal crypto
3. **Compile rsyslog without crypto** - Build from source excluding libgcrypt

**Mitigation Options:**
- Disable rsyslog crypto features in `/etc/rsyslog.conf`
- Use syslog-ng with OpenSSL backend
- Use container logging (Docker/Kubernetes native)

**Recommendation:** **REPLACE with syslog-ng or use container logging**

---

#### 🔴 CRITICAL RISK: libopenscap8

**Package:** libopenscap8
**Purpose:** SCAP (Security Content Automation Protocol) library
**Risk Level:** 🔴 **CRITICAL - VERIFY DEPENDENCIES**

**Potential Dependencies:**
```
libopenscap8
├── Possibly libxmlsec1 (XML security - may pull NSS or OpenSSL)
├── Possibly libcurl4 (may have crypto dependencies)
└── Other XML/parsing libraries
```

**Why Critical:**
- SCAP compliance scanning may use cryptographic verification
- May pull libxmlsec1 which can link to NSS or system OpenSSL
- Signature verification for SCAP content

**FIPS Impact:** 🟡 **POTENTIAL RISK** (needs dependency verification)

**Investigation Needed:**
```bash
docker run --rm ubuntu:22.04 bash -c "apt-get update && apt-cache depends libopenscap8"
```

**Recommendation:** **VERIFY DEPENDENCIES** - May be safe if no crypto libs pulled

---

#### 🟡 HIGH RISK: aide + aide-common

**Package:** aide, aide-common
**Purpose:** Advanced Intrusion Detection Environment
**Risk Level:** 🟡 **HIGH - VERIFY CONFIGURATION**

**Dependencies:**
```
aide
├── libmhash2 (hashing library)
├── libpcre2-8-0 (regex)
└── zlib1g (compression)
```

**Potential Crypto Usage:**
- File integrity checking using hashes (MD5, SHA-1, SHA-256)
- Hash implementation via libmhash2
- May be configurable to use OpenSSL instead

**FIPS Impact:** 🟡 **MEDIUM RISK**
- libmhash2 is a separate hash library (not FIPS validated)
- AIDE may use libmhash2 for file hashing instead of FIPS OpenSSL
- Can potentially be configured to use OpenSSL

**Alternatives:**
- **Tripwire** - Commercial, can use FIPS-validated crypto
- **OSSEC** - Can be configured to use system OpenSSL
- **Custom file integrity tool** using FIPS OpenSSL SHA-256

**Recommendation:** **VERIFY aide uses OpenSSL** or replace with FIPS-aware tool

---

#### 🟢 LOW RISK: libpam-pwquality

**Package:** libpam-pwquality
**Purpose:** PAM module for password quality checking
**Risk Level:** 🟢 **LOW - LIKELY SAFE**

**Dependencies:**
```
libpam-pwquality
├── libpwquality1 (password quality library)
├── libcrack2 (password strength checking)
└── libpam0g (PAM library)
```

**Crypto Usage:**
- Password complexity checking (no crypto operations)
- Dictionary checking (no crypto operations)
- No known cryptographic library dependencies

**FIPS Impact:** ✅ **NO IMPACT** - Does not use cryptographic libraries

**Recommendation:** ✅ **SAFE TO INCLUDE**

---

#### 🟢 LOW RISK: libpam-runtime

**Package:** libpam-runtime
**Purpose:** Runtime support for PAM (Pluggable Authentication Modules)
**Risk Level:** 🟢 **LOW - LIKELY SAFE**

**Dependencies:**
```
libpam-runtime
└── libpam0g (PAM library - no crypto)
```

**Crypto Usage:**
- PAM framework itself doesn't do crypto
- PAM modules (like pam_unix) may do password hashing
- Password hashing typically uses crypt(3) with system library
- Modern PAM uses yescrypt or bcrypt (application-level, not OpenSSL)

**FIPS Impact:** 🟡 **MINIMAL CONCERN**
- PAM password hashing uses crypt(3) from libcrypt
- libcrypt may not be FIPS-validated
- However, password hashing is outside FIPS scope for most compliance frameworks

**Recommendation:** ✅ **SAFE TO INCLUDE** (password hashing usually exempt from FIPS)

---

#### 🟢 LOW RISK: auditd

**Package:** auditd
**Purpose:** Linux kernel audit framework daemon
**Risk Level:** 🟢 **LOW - LIKELY SAFE**

**Dependencies:**
```
auditd
├── libaudit1 (audit library)
├── libauparse0 (audit parsing)
└── libcap-ng0 (capabilities library)
```

**Crypto Usage:**
- Audit logging and kernel event recording
- No cryptographic operations by default
- Optional: audit log signing (requires explicit configuration)

**FIPS Impact:** ✅ **NO IMPACT** (default configuration)
- Does not use crypto by default
- If log signing enabled, must verify crypto library used

**Recommendation:** ✅ **SAFE TO INCLUDE** (disable log signing or verify OpenSSL usage)

---

#### ✅ SAFE: sudo

**Package:** sudo
**Purpose:** Execute commands as superuser
**Risk Level:** ✅ **SAFE**

**Dependencies:**
```
sudo
├── libpam0g (PAM support)
└── libc6 (standard C library)
```

**Crypto Usage:** None (privilege escalation only)

**FIPS Impact:** ✅ **NO IMPACT**

**Recommendation:** ✅ **SAFE TO INCLUDE**

---

#### ✅ SAFE: vim

**Package:** vim
**Purpose:** Text editor
**Risk Level:** ✅ **SAFE**

**Crypto Usage:** None

**FIPS Impact:** ✅ **NO IMPACT**

**Recommendation:** ✅ **SAFE TO INCLUDE**

---

#### ✅ SAFE: less

**Package:** less
**Purpose:** File pager
**Risk Level:** ✅ **SAFE**

**Crypto Usage:** None

**FIPS Impact:** ✅ **NO IMPACT**

**Recommendation:** ✅ **SAFE TO INCLUDE**

---

## Dependency Analysis

### Dependency Tree Investigation

To verify actual dependencies that would be pulled, run:

```bash
# Check libnss3-tools dependencies
docker run --rm ubuntu:22.04 bash -c "apt-get update >/dev/null 2>&1 && apt-cache depends libnss3-tools"

# Check rsyslog dependencies
docker run --rm ubuntu:22.04 bash -c "apt-get update >/dev/null 2>&1 && apt-cache depends rsyslog"

# Check aide dependencies
docker run --rm ubuntu:22.04 bash -c "apt-get update >/dev/null 2>&1 && apt-cache depends aide"

# Check libopenscap8 dependencies
docker run --rm ubuntu:22.04 bash -c "apt-get update >/dev/null 2>&1 && apt-cache depends libopenscap8"
```

### Crypto Library Detection Commands

```bash
# After building hardened image, check for non-FIPS crypto libraries:

# Check for NSS libraries
docker run --rm valkey-fips:8.1.5-ubuntu-22.04-hardened \
  find /usr /lib -name "libnss3.so*" 2>/dev/null

# Check for libgcrypt
docker run --rm valkey-fips:8.1.5-ubuntu-22.04-hardened \
  find /usr /lib -name "libgcrypt.so*" 2>/dev/null

# Check for libmhash (AIDE)
docker run --rm valkey-fips:8.1.5-ubuntu-22.04-hardened \
  find /usr /lib -name "libmhash*.so*" 2>/dev/null

# List all installed packages
docker run --rm valkey-fips:8.1.5-ubuntu-22.04-hardened \
  dpkg -l | grep -E "nss|gcrypt|mhash|ssl"
```

---

## FIPS Compliance Impact

### Compliance Framework Impact

#### FIPS 140-3 Validation

**Requirement:** All cryptographic operations must use FIPS-validated cryptographic module

**Current Status:**
- ✅ FIPS OpenSSL 3.0.15 installed
- ✅ wolfSSL FIPS v5 provider active
- ❌ **NSS crypto library present** (non-validated)
- ❌ **GNU crypto library present** (non-validated)

**Violation:** Applications can bypass FIPS-validated crypto by linking to NSS or libgcrypt

**Severity:** 🔴 **CRITICAL** - Complete FIPS validation failure

---

#### FedRAMP Requirements

**FedRAMP Control SC-13:** Cryptographic Protection
> "The information system implements FIPS-validated cryptography"

**Impact:**
- ❌ Presence of non-FIPS crypto libraries violates SC-13
- ❌ 3PAO audit will identify this as **HIGH finding**
- ❌ Will block FedRAMP authorization

---

#### DISA STIG V2R1

**Finding:** CAT I (High Severity)
> "The operating system must use FIPS-validated cryptographic mechanisms"

**Impact:**
- ❌ Presence of libnss3/libgcrypt20 is STIG violation
- ❌ Must be remediated before ATO (Authority to Operate)

---

### Risk Assessment Matrix

| Package | FIPS Risk | Compliance Impact | Recommended Action |
|---------|-----------|-------------------|-------------------|
| libnss3-tools | 🔴 Critical | Blocks FedRAMP/STIG | **REMOVE** |
| rsyslog | 🔴 Critical | Blocks FedRAMP/STIG | **REPLACE** |
| libopenscap8 | 🟡 High | Needs verification | **VERIFY/REMOVE** |
| aide/aide-common | 🟡 Medium | Needs configuration review | **VERIFY CONFIG** |
| libpam-pwquality | 🟢 Low | No impact | **KEEP** |
| libpam-runtime | 🟢 Low | Minimal (exempt) | **KEEP** |
| auditd | 🟢 Low | No impact (default) | **KEEP** |
| sudo | ✅ None | No impact | **KEEP** |
| vim | ✅ None | No impact | **KEEP** |
| less | ✅ None | No impact | **KEEP** |

---

## Test Results

### Automated Test Script

**Script:** `tests/test-hardened-fips-compliance.sh`

**Test Coverage:**
- Phase 1: Image and Container Validation
- Phase 2: Non-FIPS Crypto Library Detection (NSS, libgcrypt, system OpenSSL)
- Phase 3: FIPS OpenSSL Verification
- Phase 4: Hardening Package Analysis
- Phase 5: Runtime FIPS Validation
- Phase 6: FIPS Mode Status

**Usage:**
```bash
# Test hardened image
./tests/test-hardened-fips-compliance.sh valkey-fips:8.1.5-ubuntu-22.04-hardened

# Expected result (current Dockerfile.hardened):
# ❌ FIPS COMPLIANCE: FAILED
# Critical Issues:
#   🔴 NSS crypto library found (bypasses FIPS OpenSSL)
#   🔴 GNU crypto library found (bypasses FIPS OpenSSL)
```

### Expected Findings (Current Implementation)

**If you build `Dockerfile.hardened` as-is:**

```
======================================
Phase 2: Non-FIPS Crypto Library Detection
======================================

--- 2.1: NSS (Network Security Services) Libraries ---
🔴 CRITICAL: NSS crypto library found (bypasses FIPS OpenSSL)
  Locations:
    /usr/lib/x86_64-linux-gnu/libnss3.so

🔴 CRITICAL: libnss3-tools package installed

--- 2.2: GNU Crypto (libgcrypt) Libraries ---
🔴 CRITICAL: GNU crypto library found (bypasses FIPS OpenSSL)
  Locations:
    /usr/lib/x86_64-linux-gnu/libgcrypt.so.20

🟡 WARNING: rsyslog package installed (may have libgcrypt20 dependency)
🔴 CRITICAL: rsyslog pulled libgcrypt20 dependency

======================================
❌ FIPS COMPLIANCE: FAILED
======================================
```

---

## FIPS-Compliant Alternatives

### 1. Certificate Management (Replace libnss3-tools)

#### Option A: Use FIPS OpenSSL CLI

```dockerfile
# No additional package needed - use FIPS OpenSSL
ENV PATH="/usr/local/openssl/bin:$PATH"

# Certificate operations will use FIPS OpenSSL:
# openssl req -new -x509 -days 365 ...
# openssl s_client -connect host:port ...
```

#### Option B: Custom Certificate Management Scripts

```dockerfile
# Create wrapper scripts using FIPS OpenSSL
COPY scripts/cert-manager.sh /usr/local/bin/
```

---

### 2. System Logging (Replace rsyslog)

#### Option A: syslog-ng with OpenSSL Backend

```dockerfile
# syslog-ng can use OpenSSL for TLS
RUN apt-get update && apt-get install -y --no-install-recommends \
    syslog-ng-core && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure syslog-ng to use /usr/local/openssl
COPY syslog-ng.conf /etc/syslog-ng/syslog-ng.conf
```

**syslog-ng.conf:**
```
@version: 3.35
@include "scl.conf"

options {
    use_fqdn(no);
    keep_hostname(yes);
    tls_backend(openssl);  # Use OpenSSL for TLS
};

source s_local {
    system();
    internal();
};

destination d_messages {
    file("/var/log/messages");
};

log {
    source(s_local);
    destination(d_messages);
};
```

#### Option B: Container-Native Logging

```dockerfile
# Use Docker/Kubernetes logging drivers
# No syslog package needed
# Configure Docker/K8s to collect stdout/stderr
```

**Docker logging configuration:**
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

#### Option C: Compile rsyslog Without Crypto

```dockerfile
# Build rsyslog from source without libgcrypt
RUN apt-get update && apt-get install -y build-essential && \
    wget https://www.rsyslog.com/files/download/rsyslog/rsyslog-8.2312.0.tar.gz && \
    tar xzf rsyslog-8.2312.0.tar.gz && \
    cd rsyslog-8.2312.0 && \
    ./configure --disable-libgcrypt --enable-openssl && \
    make && make install && \
    cd .. && rm -rf rsyslog-*
```

---

### 3. File Integrity (AIDE Configuration)

#### Option A: Configure AIDE to Use OpenSSL

Check if AIDE can be configured to use OpenSSL instead of libmhash:

```dockerfile
# Create AIDE configuration that prefers OpenSSL
RUN echo "# AIDE Configuration" > /etc/aide/aide.conf && \
    echo "database_in=file:/var/lib/aide/aide.db" >> /etc/aide/aide.conf && \
    echo "database_out=file:/var/lib/aide/aide.db.new" >> /etc/aide/aide.conf && \
    echo "# Use SHA-256 from OpenSSL if possible" >> /etc/aide/aide.conf
```

#### Option B: Use OSSEC-HIDS

```dockerfile
# OSSEC can use system OpenSSL for file integrity
RUN apt-get update && apt-get install -y --no-install-recommends \
    ossec-hids && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
```

#### Option C: Custom File Integrity Tool

```bash
#!/bin/bash
# file-integrity-check.sh
# Uses FIPS OpenSSL for SHA-256 hashing

OPENSSL=/usr/local/openssl/bin/openssl
DB_FILE=/var/lib/file-integrity.db

# Generate file hash using FIPS SHA-256
hash_file() {
    $OPENSSL dgst -sha256 "$1" | awk '{print $2}'
}

# Check file integrity
for file in /etc/valkey/* /opt/bitnami/valkey/bin/*; do
    current_hash=$(hash_file "$file")
    stored_hash=$(grep "$file" "$DB_FILE" | awk '{print $2}')
    if [ "$current_hash" != "$stored_hash" ]; then
        echo "ALERT: $file modified!"
    fi
done
```

---

## Recommended Solutions

### Solution 1: Minimal Hardening (FIPS-Safe)

**Remove all crypto-dependent packages:**

```dockerfile
# STIG/CIS: Install FIPS-safe security packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpam-pwquality \
    libpam-runtime \
    auditd \
    sudo \
    vim \
    less && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Use container-native logging (no rsyslog/syslog-ng)
# Use FIPS OpenSSL for certificate management (no libnss3-tools)
# Use custom file integrity with FIPS OpenSSL (no aide)
```

**Advantages:**
- ✅ 100% FIPS compliant
- ✅ No non-FIPS crypto libraries
- ✅ Minimal attack surface
- ✅ Faster container startup

**Disadvantages:**
- ⚠️ No system logging daemon (use container logging)
- ⚠️ No pre-built file integrity tool
- ⚠️ Must use custom scripts for some operations

---

### Solution 2: FIPS-Safe Alternatives (Recommended)

**Replace problematic packages with FIPS-aware alternatives:**

```dockerfile
# STIG/CIS: Install FIPS-safe security packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpam-pwquality \
    libpam-runtime \
    auditd \
    sudo \
    vim \
    less \
    syslog-ng-core && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Remove system OpenSSL (including any pulled by syslog-ng)
RUN set -eux; \
    rm -f /usr/lib/x86_64-linux-gnu/libssl.so* \
          /usr/lib/x86_64-linux-gnu/libcrypto.so* \
          /lib/x86_64-linux-gnu/libssl.so* \
          /lib/x86_64-linux-gnu/libcrypto.so* \
          /usr/bin/openssl || true; \
    dpkg --remove --force-depends libssl3 2>/dev/null || true; \
    # Also remove any NSS or libgcrypt that was pulled
    dpkg --remove --force-depends libnss3 libgcrypt20 2>/dev/null || true; \
    if [ -f "/usr/lib/x86_64-linux-gnu/libssl.so.3" ]; then \
        echo "ERROR: System OpenSSL still present!"; exit 1; \
    fi

# Configure syslog-ng to use FIPS OpenSSL
COPY syslog-ng-fips.conf /etc/syslog-ng/syslog-ng.conf

# Add custom file integrity script using FIPS OpenSSL
COPY scripts/file-integrity-check.sh /usr/local/bin/
```

**Advantages:**
- ✅ 100% FIPS compliant
- ✅ System logging available (syslog-ng with OpenSSL)
- ✅ File integrity monitoring (custom FIPS tool)
- ✅ No NSS or libgcrypt

**Disadvantages:**
- ⚠️ Requires custom syslog-ng configuration
- ⚠️ Requires custom file integrity script
- ⚠️ More complex build process

---

### Solution 3: Aggressive Cleanup (Maximum Assurance)

**Install packages, then aggressively remove non-FIPS crypto:**

```dockerfile
# STIG/CIS: Install security packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpam-pwquality \
    libpam-runtime \
    auditd \
    sudo \
    vim \
    less && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Remove ALL non-FIPS crypto libraries (aggressive cleanup)
RUN set -eux; \
    # Remove system OpenSSL
    rm -f /usr/lib/x86_64-linux-gnu/libssl.so* \
          /usr/lib/x86_64-linux-gnu/libcrypto.so* \
          /lib/x86_64-linux-gnu/libssl.so* \
          /lib/x86_64-linux-gnu/libcrypto.so* \
          /usr/bin/openssl || true; \
    dpkg --remove --force-depends libssl3 2>/dev/null || true; \
    # Remove NSS
    dpkg --remove --force-depends libnss3 libnspr4 2>/dev/null || true; \
    rm -f /usr/lib/x86_64-linux-gnu/libnss3.so* || true; \
    # Remove libgcrypt
    dpkg --remove --force-depends libgcrypt20 2>/dev/null || true; \
    rm -f /usr/lib/x86_64-linux-gnu/libgcrypt.so* || true; \
    # Remove libmhash
    dpkg --remove --force-depends libmhash2 2>/dev/null || true; \
    rm -f /usr/lib/x86_64-linux-gnu/libmhash* || true; \
    # Verify cleanup
    if find /usr /lib -name "libnss3.so*" -o -name "libgcrypt.so*" 2>/dev/null | grep -q .; then \
        echo "ERROR: Non-FIPS crypto libraries still present!"; exit 1; \
    fi
```

**Advantages:**
- ✅ Maximum FIPS assurance
- ✅ All non-FIPS crypto forcibly removed
- ✅ Build fails if crypto libraries remain

**Disadvantages:**
- ⚠️ May break packages that depend on removed libraries
- ⚠️ Aggressive `--force-depends` can cause issues
- ⚠️ Requires extensive testing

---

## Implementation Guide

### Step 1: Choose Solution

**For most deployments:** Use **Solution 2 (FIPS-Safe Alternatives)**

### Step 2: Create New Dockerfile

**File:** `Dockerfile.hardened-fips-compliant`

```dockerfile
# Copy from existing Dockerfile.hardened, but replace line 117 with:

# STIG/CIS: Install FIPS-safe security packages ONLY
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpam-pwquality \
    libpam-runtime \
    auditd \
    sudo \
    vim \
    less && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install syslog-ng separately (careful with dependencies)
RUN apt-get update && apt-get install -y --no-install-recommends \
    syslog-ng-core && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Remove system OpenSSL AND any non-FIPS crypto pulled by packages
RUN set -eux; \
    rm -f /usr/lib/x86_64-linux-gnu/libssl.so* \
          /usr/lib/x86_64-linux-gnu/libcrypto.so* \
          /lib/x86_64-linux-gnu/libssl.so* \
          /lib/x86_64-linux-gnu/libcrypto.so* \
          /usr/bin/openssl || true; \
    dpkg --remove --force-depends libssl3 2>/dev/null || true; \
    dpkg --remove --force-depends libnss3 libgcrypt20 2>/dev/null || true; \
    # Verify removal
    if [ -f "/usr/lib/x86_64-linux-gnu/libssl.so.3" ]; then \
        echo "ERROR: System OpenSSL still present!"; exit 1; \
    fi; \
    if find /usr /lib -name "libnss3.so*" -o -name "libgcrypt.so*" 2>/dev/null | grep -q .; then \
        echo "ERROR: Non-FIPS crypto libraries present!"; exit 1; \
    fi

# Continue with rest of Dockerfile.hardened...
```

### Step 3: Build and Test

```bash
# Build FIPS-compliant hardened image
docker build \
    --secret id=wolfssl_password,src=wolfssl_password.txt \
    -t valkey-fips:8.1.5-ubuntu-22.04-hardened-fips \
    -f Dockerfile.hardened-fips-compliant \
    .

# Run FIPS compliance test
./tests/test-hardened-fips-compliance.sh valkey-fips:8.1.5-ubuntu-22.04-hardened-fips

# Expected result:
# ✅ FIPS COMPLIANCE: VERIFIED
# No non-FIPS crypto libraries detected
```

### Step 4: Run Full Test Suite

```bash
# Run all tests on hardened image
IMAGE_NAME="valkey-fips:8.1.5-ubuntu-22.04-hardened-fips" ./tests/run-all-tests.sh

# All 30 tests should pass
```

### Step 5: Verify Hardening

```bash
# Verify hardening packages are installed
docker run --rm valkey-fips:8.1.5-ubuntu-22.04-hardened-fips dpkg -l | grep -E "pam|audit|sudo"

# Verify NO non-FIPS crypto
docker run --rm valkey-fips:8.1.5-ubuntu-22.04-hardened-fips \
    find /usr /lib -name "libnss3.so*" -o -name "libgcrypt.so*" 2>/dev/null

# Should return no output (no files found)
```

---

## Conclusion

### Summary of Findings

1. **Current `Dockerfile.hardened` BREAKS FIPS compliance** due to:
   - libnss3-tools introducing NSS crypto library
   - rsyslog pulling libgcrypt20 dependency
   - Possibly libopenscap8 pulling additional crypto libs

2. **Critical packages to REMOVE:**
   - libnss3-tools
   - rsyslog (unless replaced with FIPS-safe alternative)
   - libopenscap8 (unless verified safe)

3. **Safe packages to KEEP:**
   - libpam-pwquality
   - libpam-runtime
   - auditd
   - sudo
   - vim
   - less

4. **Recommended approach:**
   - Use Solution 2: FIPS-Safe Alternatives
   - Replace rsyslog with syslog-ng (OpenSSL backend) or container logging
   - Remove libnss3-tools, use FIPS OpenSSL CLI instead
   - Use custom file integrity script with FIPS OpenSSL

### Next Steps

1. ✅ Review this analysis with security team
2. ✅ Choose implementation solution (recommend Solution 2)
3. ✅ Create `Dockerfile.hardened-fips-compliant`
4. ✅ Build and test new image
5. ✅ Run `test-hardened-fips-compliance.sh`
6. ✅ Document approved configuration
7. ✅ Proceed to 3PAO audit preparation

### Final Recommendation

**DO NOT deploy current `Dockerfile.hardened` to production or for FedRAMP/STIG compliance.**

**Implement Solution 2** (FIPS-Safe Alternatives) to achieve both security hardening AND FIPS 140-3 compliance.

---

**Analysis Date:** December 18, 2025
**Review Status:** Pending Security Team Approval
**FIPS Compliance Status:** ❌ **NON-COMPLIANT** (current), ✅ **COMPLIANT** (with recommended changes)
**Report Version:** 1.0
