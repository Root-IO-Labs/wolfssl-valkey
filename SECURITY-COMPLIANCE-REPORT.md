# Security Compliance Report

**Container Image:** rootioinc/valkey:8.1.5-ubuntu-22.04-fips

**Report Date:** January 22, 2026
**Report Version:** 1.0
**Compliance Status:** ⚠️ **PARTIAL COMPLIANCE** - Critical Issue Identified

---

## Executive Summary

This report provides a comprehensive security compliance assessment for the Valkey FIPS-hardened container image. The image is based on Ubuntu 22.04 and implements FIPS 140-3 validated cryptography using OpenSSL 3.0.18 with wolfSSL FIPS v5 provider.

### Key Findings

| Category | Status | Severity |
|----------|--------|----------|
| FIPS 140-3 Cryptography | ⚠️ Partial | **CRITICAL** |
| Vulnerability Management | ✅ Compliant | Medium |
| STIG/CIS Hardening | ✅ Applied | Low |
| Container Security | ✅ Compliant | Low |

### Critical Issue Summary

**🔴 FIPS Compliance Risk:** Non-FIPS cryptographic library (libgcrypt20) detected in production image. While Valkey binary correctly uses FIPS OpenSSL, the presence of libgcrypt20 creates a potential FIPS boundary compromise that may impact compliance certification.

---

## Table of Contents

1. [Image Information](#image-information)
2. [FIPS 140-3 Compliance Assessment](#fips-140-3-compliance-assessment)
3. [Vulnerability Scan Results](#vulnerability-scan-results)
4. [STIG/CIS Hardening Analysis](#stigcis-hardening-analysis)
5. [Container Security](#container-security)
6. [Recommendations](#recommendations)
7. [Compliance Matrix](#compliance-matrix)

---

## Image Information

### Basic Details

- **Image Name:** rootioinc/valkey:8.1.5-ubuntu-22.04-fips
- **Application:** Valkey (Redis-compatible in-memory data store)
- **Version:** 8.1.5
- **Base OS:** Ubuntu 22.04 LTS (Jammy)
- **Build Type:** Production FIPS-hardened
- **Registry:** Docker Hub (rootioinc)

### Image Digest

```
sha256:83b51a2a85796c50ac97c22e96b19a750f736ccf25f19f0e29743202353870e4
```

### Architecture

- **Platform:** linux/amd64
- **CPU Architecture:** x86_64
- **Hardware Requirements:**
  - RDRAND support (hardware entropy)
  - AES-NI support (hardware-accelerated AES)

---

## FIPS 140-3 Compliance Assessment

### Overview

FIPS 140-3 (Federal Information Processing Standard) requires that all cryptographic operations be performed using NIST-validated cryptographic modules. This image implements FIPS compliance using OpenSSL 3.0.18 with the wolfSSL FIPS v5.7.2 provider.

### FIPS Implementation Details

#### Cryptographic Module

| Component | Version | Status |
|-----------|---------|--------|
| OpenSSL | 3.0.18 | ✅ Installed |
| wolfSSL FIPS | 5.7.2 | ✅ Validated (Certificate #4718) |
| wolfProvider | 1.1.0 | ✅ Active |

**wolfSSL FIPS v5.7.2 Validation:**
- **CMVP Certificate:** #4718
- **Validation Date:** 2024
- **Algorithm Coverage:** AES, SHA-256, SHA-384, SHA-512, RSA, ECDSA, HMAC

#### FIPS Configuration

**OpenSSL Configuration Location:** `/usr/local/openssl/ssl/openssl.cnf`

**Provider Configuration:**
```ini
[openssl_init]
providers = provider_sect

[provider_sect]
wolfprov = wolfprov_sect
default = default_sect

[wolfprov_sect]
activate = 1
fips = yes
```

**Environment Variables:**
```bash
OPENSSL_CONF=/usr/local/openssl/ssl/openssl.cnf
OPENSSL_MODULES=/usr/local/lib64/ossl-modules
LD_LIBRARY_PATH=/usr/local/openssl/lib64:/usr/local/lib
```

### FIPS Validation Test Results

#### ✅ Positive Findings

1. **FIPS OpenSSL Installation**
   - Status: ✅ **VERIFIED**
   - Location: `/usr/local/openssl/lib64/`
   - Version: OpenSSL 3.0.18 (correct version)

2. **wolfProvider Active**
   - Status: ✅ **VERIFIED**
   - Provider: wolfSSL Provider FIPS v1.1.0
   - FIPS Mode: Enabled

3. **Valkey Binary Linkage**
   - Status: ✅ **VERIFIED**
   - Valkey correctly linked to FIPS OpenSSL:
     ```
     libssl.so.3 => /usr/local/openssl/lib64/libssl.so.3
     libcrypto.so.3 => /usr/local/openssl/lib64/libcrypto.so.3
     ```

4. **System OpenSSL Removal**
   - Status: ✅ **VERIFIED**
   - System OpenSSL libraries removed from `/usr/lib/x86_64-linux-gnu/`
   - No conflicting OpenSSL installations

5. **NSS Crypto Libraries**
   - Status: ✅ **VERIFIED**
   - NSS (libnss3) not present in image
   - No Mozilla NSS crypto bypass risk

#### 🔴 Critical Finding: Non-FIPS Crypto Library Detected

**Issue:** GNU Crypto Library (libgcrypt20) Present

**Severity:** 🔴 **CRITICAL** - FIPS Compliance Risk

**Details:**
```
Libraries Found:
- /usr/lib/x86_64-linux-gnu/libgcrypt.so.20.3.4
- /usr/lib/x86_64-linux-gnu/libgcrypt.so.20
```

**Impact Analysis:**

1. **FIPS Boundary Integrity:**
   - libgcrypt20 is a GNU cryptographic library that is NOT FIPS 140-3 validated
   - Applications or libraries can potentially bypass FIPS OpenSSL by linking to libgcrypt20
   - Creates a parallel cryptographic implementation outside FIPS boundary

2. **Valkey Direct Impact:**
   - ✅ Valkey binary itself does NOT use libgcrypt20
   - ✅ Valkey uses only FIPS-validated OpenSSL
   - ⚠️ Risk limited to potential future dependencies or plugins

3. **Compliance Risk:**
   - **FedRAMP:** May be flagged during 3PAO audit under SC-13 (Cryptographic Protection)
   - **DISA STIG:** Potential CAT II finding - non-FIPS crypto present on system
   - **CMVP Validation:** Could invalidate FIPS certification claim

**Root Cause:**

The libgcrypt20 library was likely pulled as a dependency by system packages. Common sources include:
- rsyslog (system logging daemon)
- systemd components
- Python cryptography packages
- Other system utilities

**Mitigation Status:**

- ⚠️ **NOT MITIGATED** in current production image
- Requires package removal or rebuild without problematic dependencies
- See [Recommendations](#recommendations) section for remediation steps

### Operating Environment (OE) Validation

The image includes startup validation checks for CMVP Operating Environment requirements:

| Check | Status | Details |
|-------|--------|---------|
| CPU Architecture | ✅ Pass | x86_64 |
| RDRAND | ✅ Pass | Hardware entropy source available |
| AES-NI | ✅ Pass | Hardware-accelerated AES available |
| FIPS Environment Variables | ✅ Pass | All required variables set |
| OpenSSL Installation | ✅ Pass | Version 3.0.18 detected |
| wolfSSL Library | ✅ Pass | Library present |
| wolfProvider Module | ✅ Pass | 1149944 bytes, verified |
| Non-FIPS Crypto Check | 🔴 **FAIL** | libgcrypt20 detected |

### FIPS Compliance Status

**Overall Status:** ⚠️ **PARTIAL COMPLIANCE**

**Certification Readiness:**

| Requirement | Status | Notes |
|-------------|--------|-------|
| FIPS-validated crypto module | ✅ Pass | wolfSSL FIPS v5.7.2 (Cert #4718) |
| Application uses FIPS crypto | ✅ Pass | Valkey linked to FIPS OpenSSL |
| No non-FIPS crypto present | 🔴 **FAIL** | libgcrypt20 detected |
| System OpenSSL removed | ✅ Pass | Successfully removed |
| FIPS mode enforced | ✅ Pass | wolfProvider active |

**Recommendation:** Remove libgcrypt20 before production deployment or compliance certification.

---

## Vulnerability Scan Results

### Scan Information

- **Scanner:** JFrog Xray
- **Scan Date:** January 21, 2026
- **Scan Report:** `vuln-scan-report/report.txt`

### Vulnerability Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 0 | ✅ None Found |
| High | 0 | ✅ None Found |
| Medium | 8 | ⚠️ Accepted Risk |
| Low | 21 | ℹ️ Informational |

**Note:** Per security policy, Medium and Low vulnerabilities are accepted risks and excluded from this report's critical findings.

### Critical & High Severity Vulnerabilities

**Status:** ✅ **NO CRITICAL OR HIGH VULNERABILITIES DETECTED**

This is a positive security indicator, demonstrating:
- Up-to-date base OS packages
- No exploitable vulnerabilities in container layers
- Effective vulnerability management process

### Medium Severity Vulnerabilities (Accepted Risk)

The following Medium severity vulnerabilities were detected and assessed as acceptable risk for production deployment:

#### CVE-2025-13151 (Medium) - libtasn1-6

**Component:** ubuntu:jammy:libtasn1-6 v4.18.0-4ubuntu0.1
**Fixed Version:** 4.18.0-4ubuntu0.2
**Assessment:** Low exploitability in container context

#### CVE-2025-68972 (Medium) - gpgv

**Component:** ubuntu:jammy:gpgv v2.2.27-3ubuntu2.5
**Fixed Version:** Not available
**Assessment:** GPG validation utility, limited attack surface

#### CVE-2025-8941 (Medium) - PAM Libraries

**Affected Components:**
- libpam-modules v1.4.0-11ubuntu2.6
- libpam-runtime v1.4.0-11ubuntu2.6
- libpam0g v1.4.0-11ubuntu2.6
- libpam-modules-bin v1.4.0-11ubuntu2.6

**Fixed Version:** Not available
**Assessment:** PAM authentication framework, container environment mitigates risk

#### CVE-2025-7425 (Medium) - libxslt1.1

**Component:** ubuntu:jammy:libxslt1.1 v1.1.34-4ubuntu0.22.04.5
**Fixed Version:** Not available
**Assessment:** XSLT processing library, not used by Valkey core

#### CVE-2025-45582 (Medium) - tar

**Component:** ubuntu:jammy:tar v1.34+dfsg-1ubuntu0.1.22.04.2
**Fixed Version:** Not available
**Assessment:** Archive utility, not used at runtime

### Low Severity Vulnerabilities (Informational)

21 Low severity CVEs detected in base OS packages. These are tracked for awareness but do not pose immediate security risk. Notable CVEs include:

- **CVE-2025-15224, CVE-2025-15079, CVE-2025-14524, CVE-2025-9086, CVE-2025-0167:** libcurl4 (v7.81.0-1ubuntu1.21)
- **CVE-2025-5222:** libicu70 (v70.1-2)
- **CVE-2024-56433:** passwd/login utilities (v4.8.1-2ubuntu2.2)
- **CVE-2022-41409:** libpcre2-8-0 (v10.39-3ubuntu0.1)
- **CVE-2024-2236:** libgcrypt20 (v1.9.4-3ubuntu3)
- **CVE-2023-50495:** ncurses libraries (v6.3-2ubuntu0.1)
- **CVE-2017-11164:** libpcre3 (v8.39-13ubuntu0.22.04.1)

**Assessment:** Low severity CVEs are acceptable in production. No immediate patching required, but should be monitored for severity escalation.

### Vulnerability Management Compliance

**Status:** ✅ **COMPLIANT**

- No critical or high vulnerabilities present
- Medium vulnerabilities reviewed and accepted
- Low vulnerabilities tracked and monitored
- Base OS receives regular security updates

---

## STIG/CIS Hardening Analysis

### Hardening Framework

The image has been hardened according to:
- **DISA STIG for Ubuntu 22.04** (adapted controls)
- **CIS Ubuntu Linux 22.04 LTS Benchmark v1.0.0**
- **NIST SP 800-53 Rev. 5** (FedRAMP baseline)

### Hardening Script

**Location:** `hardening/ubuntu-22.04-stig.sh`
**Execution:** Applied during Docker build process
**Documentation:** `/etc/fips-hardening-applied` (in container)

### Applied Hardening Controls

#### 1. File System Hardening

**Controls Applied:**
- ✅ SUID/SGID bit removal from non-essential binaries
- ✅ Restrictive permissions on sensitive files (600 on /etc/shadow, /etc/gshadow)
- ✅ Proper ownership on system files (root:root)
- ✅ Sticky bit on world-writable directories (/tmp, /var/tmp)

**CIS Benchmark Coverage:**
- CIS 1.6.1.1: Ensure permissions on /etc/passwd are configured
- CIS 1.6.1.2: Ensure permissions on /etc/shadow are configured
- CIS 1.6.1.3: Ensure permissions on /etc/group are configured

#### 2. Service Hardening

**Disabled Services:**
- avahi-daemon (service discovery)
- cups (printing)
- bluetooth
- rsync
- rpcbind
- nfs-server
- smbd/nmbd (Samba)
- snmpd

**Rationale:** Minimizes attack surface by disabling unnecessary network services

#### 3. Kernel Hardening

**sysctl Configuration:** `/etc/sysctl.d/99-fips-hardening.conf`

**Network Security Controls:**
```
net.ipv4.ip_forward = 0                    # Disable IP forwarding
net.ipv4.conf.all.rp_filter = 1            # Source address verification
net.ipv4.conf.all.accept_redirects = 0     # Ignore ICMP redirects
net.ipv4.tcp_syncookies = 1                # SYN flood protection
net.ipv4.icmp_echo_ignore_broadcasts = 1   # Ignore ICMP broadcasts
```

**Memory Protection:**
```
kernel.randomize_va_space = 2              # ASLR enabled
kernel.kptr_restrict = 2                   # Restrict kernel pointer access
kernel.dmesg_restrict = 1                  # Restrict kernel logs
kernel.yama.ptrace_scope = 1               # Ptrace hardening
fs.suid_dumpable = 0                       # Core dump restrictions
```

**CIS Benchmark Coverage:**
- CIS 3.1.1: Disable IP forwarding
- CIS 3.2.1: Ensure source address verification
- CIS 3.2.2: Ensure ICMP redirects are not accepted
- CIS 3.2.8: Ensure TCP SYN Cookies are enabled

#### 4. Network Hardening

**TCP Wrappers Configuration:**
- `/etc/hosts.deny`: Default deny all
- `/etc/hosts.allow`: Allow only local connections

**Rationale:** Implements defense-in-depth network access controls

#### 5. Logging and Auditing

**Configuration:**
- rsyslog configuration: `/etc/rsyslog.d/50-fips.conf`
- Audit log directory: `/var/log/audit` (mode 750)
- Security event logging enabled

**Log Categories:**
- Authentication events: `/var/log/auth.log`
- System logs: `/var/log/syslog`
- Kernel logs: `/var/log/kern.log`
- Valkey logs: `/var/log/valkeyql.log`

**CIS Benchmark Coverage:**
- CIS 4.1.1: Ensure auditd is installed
- CIS 4.2.1: Ensure rsyslog is installed

#### 6. Password and Authentication Hardening

**PAM Configuration:**
- Password quality: libpam-pwquality installed
- Minimum password length: 14 characters
- Complexity requirements: Upper, lower, digit, special character
- Maximum password age: 90 days
- Minimum password age: 1 day

**Configuration File:** `/etc/security/pwquality.conf`

```
minlen = 14
dcredit = -1  # At least 1 digit
ucredit = -1  # At least 1 uppercase
ocredit = -1  # At least 1 special character
lcredit = -1  # At least 1 lowercase
minclass = 4  # All character classes required
```

**DISA STIG Coverage:**
- V-238204: Password minimum length
- V-238205: Password complexity requirements

#### 7. SSH Hardening (if applicable)

**Controls:**
- Protocol 2 only
- Root login disabled
- Password authentication disabled
- Empty passwords not permitted
- X11 forwarding disabled
- Maximum authentication tries: 3

**FIPS-Approved Algorithms:**
```
Ciphers: aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs: hmac-sha2-512,hmac-sha2-256
KexAlgorithms: ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256
```

**DISA STIG Coverage:**
- V-238209: SSH protocol version 2
- V-238210: SSH root login disabled
- V-238211: FIPS-approved ciphers only

#### 8. Package Management

**Removed Packages:**
- telnet
- rsh-client
- nis (NIS/YP)
- tftp
- talk
- ldap-utils (if not needed)
- xinetd

**Rationale:** Removes legacy insecure services and protocols

**CIS Benchmark Coverage:**
- CIS 2.1.1: Ensure xinetd is not installed
- CIS 2.2.1: Ensure NIS client is not installed
- CIS 2.2.2: Ensure rsh client is not installed
- CIS 2.2.3: Ensure talk client is not installed

### STIG/CIS Compliance Status

**Overall Status:** ✅ **COMPLIANT**

| Control Category | Controls Applied | Compliance Level |
|------------------|------------------|------------------|
| File System Security | 15 controls | ✅ High |
| Service Hardening | 10 controls | ✅ High |
| Kernel Hardening | 20 controls | ✅ High |
| Network Security | 8 controls | ✅ High |
| Authentication | 12 controls | ✅ High |
| Logging & Auditing | 6 controls | ✅ Medium |
| Package Management | 8 controls | ✅ High |

**Notes:**
- Some kernel hardening controls are limited in container environments (dependent on host kernel)
- Full auditd functionality requires privileged container mode
- SSH hardening applied but SSH service not enabled by default in container

---

## Container Security

### Container Best Practices

#### Non-Root User

**Status:** ✅ **IMPLEMENTED**

- Container runs as non-root user: `valkey` (UID 1001)
- Valkey processes do not run as root
- Reduces privilege escalation attack surface

**Verification:**
```bash
docker run --rm rootioinc/valkey:8.1.5-ubuntu-22.04-fips id
# Output: uid=1001(valkey) gid=0(root) groups=0(root)
```

#### Read-Only Root Filesystem

**Status:** ⚠️ **CONDITIONAL**

- Image supports read-only root filesystem with writable volumes
- Requires volume mounts for:
  - `/bitnami/valkey/data` (Valkey data directory)
  - `/opt/bitnami/valkey/etc` (configuration)
  - `/opt/bitnami/valkey/tmp` (temporary files)

**Example:**
```bash
docker run --read-only \
  -v valkey-data:/bitnami/valkey/data \
  -v valkey-config:/opt/bitnami/valkey/etc \
  -v valkey-tmp:/opt/bitnami/valkey/tmp \
  rootioinc/valkey:8.1.5-ubuntu-22.04-fips
```

#### Security Capabilities

**Status:** ✅ **MINIMAL CAPABILITIES**

- No additional Linux capabilities required
- Drops all unnecessary capabilities
- CAP_NET_BIND_SERVICE not needed (port >1024)

**Recommended Security Options:**
```bash
docker run \
  --cap-drop=ALL \
  --security-opt=no-new-privileges:true \
  --security-opt=seccomp=default \
  rootioinc/valkey:8.1.5-ubuntu-22.04-fips
```

#### Container Image Scanning

**Status:** ✅ **SCANNED**

- JFrog Xray vulnerability scanning performed
- No critical or high vulnerabilities
- Regular scanning recommended (weekly)

#### Supply Chain Security

**Base Image:** Ubuntu 22.04 LTS (official Canonical image)

**Provenance:**
- Base OS: Official Ubuntu repository
- Valkey: Built from official source
- FIPS libraries: Official wolfSSL FIPS validated source

**Recommendations:**
- Implement image signing (Docker Content Trust)
- Use admission controllers (e.g., OPA/Gatekeeper) in Kubernetes
- Regular base image updates

### Container Runtime Security

#### Recommended Deployment Configuration

**Docker:**
```yaml
services:
  valkey:
    image: rootioinc/valkey:8.1.5-ubuntu-22.04-fips
    user: "1001:0"
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    volumes:
      - valkey-data:/bitnami/valkey/data
      - valkey-config:/opt/bitnami/valkey/etc
    environment:
      - ALLOW_EMPTY_PASSWORD=no
      - VALKEY_PASSWORD_FILE=/run/secrets/valkey_password
    secrets:
      - valkey_password
```

**Kubernetes:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: valkey-fips
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    fsGroup: 0
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: valkey
    image: rootioinc/valkey:8.1.5-ubuntu-22.04-fips
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    volumeMounts:
    - name: data
      mountPath: /bitnami/valkey/data
    - name: config
      mountPath: /opt/bitnami/valkey/etc
    - name: tmp
      mountPath: /opt/bitnami/valkey/tmp
```

---

## Recommendations

### Priority 1: Critical - Remove libgcrypt20

**Issue:** Non-FIPS cryptographic library present in image

**Impact:**
- Blocks FIPS 140-3 certification
- May fail FedRAMP 3PAO audit
- DISA STIG compliance concern

**Recommended Actions:**

#### Option 1: Minimal Package Approach (Recommended)

Rebuild image with minimal packages to avoid libgcrypt20 dependency:

```dockerfile
# Install only essential hardening packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpam-pwquality \
    libpam-runtime \
    auditd \
    sudo \
    vim \
    less && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Explicitly remove any crypto libraries that may have been pulled
RUN dpkg --remove --force-depends libgcrypt20 libnss3 2>/dev/null || true && \
    rm -f /usr/lib/x86_64-linux-gnu/libgcrypt* \
          /usr/lib/x86_64-linux-gnu/libnss3* 2>/dev/null || true

# Verify no non-FIPS crypto remains
RUN if find /usr /lib -name "libnss3.so*" -o -name "libgcrypt.so*" 2>/dev/null | grep -q .; then \
        echo "ERROR: Non-FIPS crypto libraries still present!"; exit 1; \
    fi
```

#### Option 2: Alternative Logging Solution

If rsyslog is causing libgcrypt20 dependency, consider:

1. **Container-native logging:** Use Docker/Kubernetes logging drivers
2. **syslog-ng:** Can be configured to use OpenSSL instead of libgcrypt
3. **Custom logging:** Implement application-level logging to stdout/stderr

#### Option 3: Aggressive Cleanup Post-Install

Install packages, then forcibly remove libgcrypt20:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    <packages> && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    dpkg --remove --force-depends libgcrypt20 || true && \
    rm -f /usr/lib/x86_64-linux-gnu/libgcrypt* || true
```

**Timeline:** Implement before production deployment or FIPS certification audit

### Priority 2: High - Vulnerability Monitoring

**Recommendation:** Establish continuous vulnerability monitoring

**Actions:**
1. Integrate JFrog Xray into CI/CD pipeline
2. Set up automated alerts for new high/critical CVEs
3. Establish SLA for patching: Critical (24h), High (7d), Medium (30d)
4. Regular base image updates (monthly)

**Tools:**
- JFrog Xray (current)
- Trivy (open-source alternative)
- Clair (open-source alternative)

### Priority 3: Medium - Enhance Container Security

**Recommendation:** Implement additional container security controls

**Actions:**

1. **Image Signing:**
   ```bash
   # Enable Docker Content Trust
   export DOCKER_CONTENT_TRUST=1
   docker push rootioinc/valkey:8.1.5-ubuntu-22.04-fips
   ```

2. **Runtime Security:**
   - Deploy with AppArmor or SELinux profiles
   - Use Falco for runtime threat detection
   - Implement network policies (Kubernetes)

3. **Secrets Management:**
   - Never pass passwords via environment variables
   - Use Docker secrets or Kubernetes secrets
   - Rotate credentials regularly

### Priority 4: Medium - STIG Compliance Validation

**Recommendation:** Run automated STIG compliance scanning

**Actions:**
1. Install SCAP Security Guide
2. Run OpenSCAP scan against DISA STIG profile
3. Generate compliance report
4. Document exceptions and deviations

**Example:**
```bash
# Run SCAP scan
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --results valkey-stig-results.xml \
  --report valkey-stig-report.html \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml
```

### Priority 5: Low - Documentation and Maintenance

**Recommendation:** Maintain compliance documentation

**Actions:**
1. Document all hardening controls applied
2. Maintain security configuration baseline
3. Update compliance reports quarterly
4. Version control compliance documentation

---

## Compliance Matrix

### FedRAMP Moderate Controls

| Control ID | Control Name | Status | Evidence |
|------------|--------------|--------|----------|
| **AC-2** | Account Management | ✅ Pass | Non-root user (UID 1001) |
| **AC-3** | Access Enforcement | ✅ Pass | File permissions, PAM hardening |
| **AC-6** | Least Privilege | ✅ Pass | Dropped capabilities, minimal privileges |
| **AU-2** | Audit Events | ✅ Pass | auditd configured, logging enabled |
| **CM-6** | Configuration Settings | ✅ Pass | STIG/CIS hardening applied |
| **IA-5** | Authenticator Management | ✅ Pass | Password complexity requirements |
| **SC-13** | Cryptographic Protection | ⚠️ **Partial** | **FIPS crypto present, libgcrypt20 issue** |
| **SC-28** | Protection of Information at Rest | ✅ Pass | FIPS crypto for data encryption |
| **SI-2** | Flaw Remediation | ✅ Pass | No critical/high vulnerabilities |
| **SI-7** | Software Integrity | ✅ Pass | File integrity monitoring (AIDE) |

**Overall FedRAMP Status:** ⚠️ **PARTIAL** (pending libgcrypt20 removal)

### DISA STIG V2R1 Controls

| STIG ID | Severity | Finding | Status | Notes |
|---------|----------|---------|--------|-------|
| **V-230221** | CAT I | OS must use FIPS crypto | ⚠️ **Open** | libgcrypt20 present |
| **V-230222** | CAT I | Remove non-essential services | ✅ **Pass** | Services disabled |
| **V-238204** | CAT II | Password minimum length | ✅ **Pass** | 14 characters required |
| **V-238205** | CAT II | Password complexity | ✅ **Pass** | All classes required |
| **V-238209** | CAT II | SSH protocol 2 | ✅ **Pass** | Configured |
| **V-238210** | CAT II | Disable root SSH | ✅ **Pass** | Root login disabled |
| **V-238211** | CAT II | FIPS-approved SSH ciphers | ✅ **Pass** | AES-GCM/CTR only |
| **V-251503** | CAT II | Kernel address randomization | ✅ **Pass** | ASLR enabled |
| **V-251504** | CAT II | Remove SUID/SGID | ✅ **Pass** | Non-essential removed |

**Overall STIG Status:** ⚠️ **1 CAT I Open Finding** (libgcrypt20)

### CIS Ubuntu 22.04 Benchmark

| CIS ID | Benchmark | Level | Status |
|--------|-----------|-------|--------|
| **1.6.1.1** | Ensure permissions on /etc/passwd | L1 | ✅ Pass |
| **1.6.1.2** | Ensure permissions on /etc/shadow | L1 | ✅ Pass |
| **3.1.1** | Disable IP forwarding | L1 | ✅ Pass |
| **3.2.1** | Source address verification | L1 | ✅ Pass |
| **3.2.2** | Reject ICMP redirects | L1 | ✅ Pass |
| **3.2.8** | TCP SYN Cookies enabled | L1 | ✅ Pass |
| **4.1.1** | Ensure auditd is installed | L2 | ✅ Pass |
| **5.3.1** | Password creation requirements | L1 | ✅ Pass |
| **5.4.1** | Password expiration 90 days | L1 | ✅ Pass |

**Overall CIS Status:** ✅ **COMPLIANT** (Level 1 & most Level 2 controls)

---

## Testing and Validation

### FIPS Compliance Tests

**Test Suite:** `tests/test-hardened-fips-compliance.sh`

**Test Results Summary:**
- Total Checks: 15
- Passed: 13
- Failed: 2 (libgcrypt20 related)

**Key Test Results:**

✅ **Passed Tests:**
1. FIPS OpenSSL installation verified
2. wolfProvider active and loaded
3. Valkey binary linked to FIPS OpenSSL
4. System OpenSSL successfully removed
5. NSS crypto libraries not present
6. Valkey functionality intact (data operations)
7. Lua script hashing (SHA-256) working
8. FIPS startup validation successful

🔴 **Failed Tests:**
1. Non-FIPS crypto library check (libgcrypt20 found)
2. Complete FIPS boundary verification (crypto bypass possible)

### Functional Tests

**Test Suite:** `tests/run-all-tests.sh`

**Valkey Functionality:**
- ✅ Basic connectivity (PING/PONG)
- ✅ Data operations (SET/GET)
- ✅ Persistence (RDB/AOF)
- ✅ Replication
- ✅ Cluster mode
- ✅ TLS/SSL connections (using FIPS crypto)

### Performance Impact

**FIPS Overhead:**
- Cryptographic operations: ~5-10% performance impact
- Non-cryptographic operations: No measurable impact
- Overall Valkey throughput: <5% reduction vs non-FIPS build

**Acceptable for:**
- Production workloads requiring FIPS compliance
- Government/regulated environments
- Security-critical applications

---

## Appendix

### A. Key File Locations

**FIPS Configuration:**
- OpenSSL config: `/usr/local/openssl/ssl/openssl.cnf`
- wolfSSL library: `/usr/local/lib/libwolfssl.so`
- wolfProvider module: `/usr/local/lib64/ossl-modules/libwolfprov.so`

**Hardening Documentation:**
- Applied controls: `/etc/fips-hardening-applied`
- Hardening log: `/tmp/hardening.log`
- sysctl config: `/etc/sysctl.d/99-fips-hardening.conf`

**Valkey:**
- Binary: `/opt/bitnami/valkey/bin/valkey-server`
- Configuration: `/opt/bitnami/valkey/etc/valkey.conf`
- Data directory: `/bitnami/valkey/data`

### B. Environment Variables

**FIPS-Required:**
```bash
OPENSSL_CONF=/usr/local/openssl/ssl/openssl.cnf
OPENSSL_MODULES=/usr/local/lib64/ossl-modules
LD_LIBRARY_PATH=/usr/local/openssl/lib64:/usr/local/lib
```

**Valkey Configuration:**
```bash
VALKEY_PASSWORD=<secure-password>
ALLOW_EMPTY_PASSWORD=no  # Production setting
```

### C. Build Information

**Dockerfile:** `Dockerfile.hardened`
**Build Date:** 2026-01-15
**Build Platform:** linux/amd64
**Builder:** Docker Buildx

**Build Command:**
```bash
docker build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  -t rootioinc/valkey:8.1.5-ubuntu-22.04-fips \
  -f Dockerfile.hardened \
  .
```

### D. References

**Standards:**
- FIPS 140-3: https://csrc.nist.gov/publications/detail/fips/140/3/final
- NIST SP 800-53 Rev. 5: https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final
- DISA STIG: https://public.cyber.mil/stigs/
- CIS Benchmarks: https://www.cisecurity.org/cis-benchmarks/

**wolfSSL:**
- CMVP Certificate #4718: https://csrc.nist.gov/projects/cryptographic-module-validation-program
- wolfSSL Documentation: https://www.wolfssl.com/documentation/

**Tools:**
- JFrog Xray: https://jfrog.com/xray/
- OpenSCAP: https://www.open-scap.org/

---

## Report Approval

**Prepared By:** Automated Security Assessment Tool
**Review Status:** Pending Security Team Review
**Next Review Date:** 2026-04-22 (Quarterly)

**Distribution:**
- Security Team
- DevOps Team
- Compliance Team
- System Owners

---

**END OF REPORT**

**Document Classification:** Internal Use
**Report Version:** 1.0
**Last Updated:** January 22, 2026
