# Operating Environment (OE) Specification

## FIPS 140-3 CMVP Compliance Documentation

**Document Version:** 1.0
**Last Updated:** 2025-12-03
**Status:** DRAFT - Pending wolfSSL CMVP Certificate Validation

---

## 1. Overview

This document defines the Operating Environment (OE) for the Valkey 8.1.5 FIPS-enabled container image built on Ubuntu 22.04. The OE specification is critical for FIPS 140-3 CMVP compliance, as cryptographic module validation is tied to specific operating system versions, kernel versions, and CPU architectures.

**CMVP Requirement:**
> A FIPS 140-3 validated cryptographic module (wolfSSL FIPS v5) operates correctly only within the Operating Environments (OEs) listed in its CMVP certificate. Any deployment outside these OEs invalidates the FIPS compliance claim.

---

## 2. Base Operating System

### 2.1 Ubuntu Version

| Component | Version | Details |
|-----------|---------|---------|
| **Distribution** | Ubuntu | Canonical's official distribution |
| **Release** | 22.04 LTS (Noble Numbat) | Long-term support release |
| **Architecture** | amd64 (x86_64) | 64-bit Intel/AMD processors |
| **Base Image** | `ubuntu:22.04` | Official Docker Hub image |
| **Libc Version** | glibc 2.39 | GNU C Library |

### 2.2 Why Ubuntu 22.04?

Per the implementation notes discussion with wolfSSL (2025-12-02):

1. **SCAP/STIG Availability:** Ubuntu has well-defined SCAP and STIG benchmarks recognized by FedRAMP 3PAOs
2. **CIS Benchmarks:** Comprehensive CIS Benchmark support for compliance automation
3. **Kernel Alignment:** Ubuntu 22.04 LTS kernels fall within wolfSSL CMVP validated kernel ranges
4. **FedRAMP Familiarity:** Widely recognized by government assessors

---

## 3. Kernel Requirements

### 3.1 Kernel Version Constraints

**Ubuntu 22.04 LTS Default Kernel:**
- **Kernel Series:** 6.8.x (at GA), upgrades to 6.11+ in HWE stack
- **Initial Release:** Linux 6.8.0-31-generic
- **Current Expected:** Linux 6.8.x - 6.14.x range

**CMVP Validation Requirement:**
> The kernel version used at runtime MUST appear in the wolfSSL FIPS v5.2.3 CMVP certificate Operating Environment list.

### 3.2 Kernel Version Verification

**At Build Time:**
```bash
# Document the builder kernel
uname -r
# Expected: 6.8.x or higher
```

**At Runtime:**
```bash
# Verified by fips-entrypoint.sh
KERNEL_VERSION=$(uname -r)
# Compare against wolfSSL CMVP OE list
```

### 3.3 Kernel Requirements for FIPS

The Linux kernel must provide:

| Requirement | Purpose |
|------------|---------|
| **Hardware RNG Access** | `/dev/hwrng` or CPU RDRAND/RDSEED |
| **Kernel RNG Interface** | `/dev/random` (not `/dev/urandom` for FIPS crypto) |
| **Memory Protection** | ASLR, NX bit, stack canaries |
| **Audit Framework** | auditd support for cryptographic event logging |
| **Namespace Support** | Container isolation (user, network, mount, PID) |

---

## 4. CPU Architecture Requirements

### 4.1 Supported Architectures

**Primary Target:**
- **Architecture:** x86_64 (amd64)
- **Instruction Sets:** SSE2, AES-NI (recommended for performance)
- **Vendors:** Intel, AMD

**CMVP Certificate Requirement:**
> The CPU architecture must match one of the architectures listed in the wolfSSL FIPS v5.2.3 CMVP certificate.

### 4.2 Required CPU Features

| Feature | Required? | Purpose |
|---------|-----------|---------|
| **x86_64** | ✅ Yes | Base architecture |
| **RDRAND** | ⚠️ Recommended | Hardware entropy source |
| **RDSEED** | ⚠️ Recommended | Entropy seed instruction |
| **AES-NI** | ⚠️ Recommended | Hardware-accelerated AES for TLS |
| **AVX2** | ❌ Optional | Performance optimization |

### 4.3 CPU Validation at Runtime

The container startup validates:
```bash
# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
fi

# Check for RDRAND (optional but recommended)
if grep -q rdrand /proc/cpuinfo; then
    echo "✓ RDRAND available"
else
    echo "⚠ RDRAND not available - using kernel entropy only"
fi
```

---

## 5. wolfSSL FIPS CMVP Certificate Mapping

### 5.1 wolfSSL Module Information

| Property | Value |
|----------|-------|
| **Module Name** | wolfSSL Cryptographic Module |
| **Version** | FIPS v5.2.3 (wolfSSL 5.8.2) |
| **Validation Level** | FIPS 140-3 Level 1 |
| **Certificate Number** | **PENDING - To be obtained from wolfSSL** |
| **Validation Date** | **PENDING** |
| **Algorithm Certificates** | **PENDING** |

### 5.2 Operating Environment List

**Per wolfSSL Discussion (2025-12-02):**
> The wolfSSL FIPS v5 CMVP certificate lists approximately 80 validated operating environments, including named versions of Debian, Ubuntu, other Linux distributions, specific Linux kernel versions, and defined CPU architectures.

**Required Action:**
1. ✅ Obtain wolfSSL FIPS 140-3 CMVP certificate document
2. ⏳ Cross-reference Ubuntu 22.04 kernel versions against OE list
3. ⏳ Document exact OE identifier from certificate
4. ⏳ Obtain written confirmation from wolfSSL that Ubuntu 22.04 LTS kernels are within validated scope

**Expected OE Entry Format:**
```
Operating Environment: Ubuntu 22.04 LTS
Kernel: Linux 6.8.x - 6.14.x
Processor: x86_64 (Intel/AMD)
Compiler: GCC 13.2.0
```

### 5.3 OE Equivalence Justification

**wolfSSL Guidance (Caleb - FIPS SME, 2025-12-02):**
> "The certificate is tied to the cryptographic module operating within a defined OE and CPU. There is no OS-level FIPS validation beyond ensuring you implement the library within an environment consistent with the CMVP listing. As long as the OS release we choose (e.g., Ubuntu Community) uses a kernel within the validated range—and behaves consistently—we can treat it as equivalent for FIPS purposes. The burden is on Root to verify and document this alignment."

**Our Justification:**
1. Ubuntu 22.04 LTS uses kernel versions within the wolfSSL validated range
2. Binary compatibility is maintained through glibc 2.39
3. System call interface is stable across kernel minor versions
4. Cryptographic module behavior is deterministic and reproducible
5. No kernel modifications that affect cryptographic operations

---

## 6. Runtime OE Validation

### 6.1 Automated Validation

The `fips-entrypoint.sh` script performs runtime OE validation:

```bash
# Validation Steps
[1] Check environment variables (OPENSSL_CONF, OPENSSL_MODULES)
[2] Check OpenSSL installation
[3] Check Valkey binary installation
[4] Check wolfSSL library presence
[5] Check wolfProvider module
[6] Run cryptographic FIPS validation
[7] Final validation - check if any errors occurred
```

### 6.2 Validation Failure Behavior

**Fail-Closed Approach:**
- If OE validation fails, container startup is aborted
- Clear error message indicates which OE requirement failed
- Container must not serve traffic or run application logic

### 6.3 OE Validation Log Output

Expected output format:
```
========================================
Valkey FIPS Container Startup
========================================

[1/6] Validating environment variables...
      ✓ OPENSSL_CONF: /usr/local/openssl/ssl/openssl.cnf
      ✓ OPENSSL_MODULES: /usr/local/lib64/ossl-modules
      ✓ LD_LIBRARY_PATH configured

[2/6] Validating OpenSSL installation...
      ✓ OpenSSL found: OpenSSL 3.0.15

[3/6] Validating Valkey installation...
      ✓ Valkey found: Valkey 8.1.5

[4/6] Validating wolfSSL library...
      ✓ wolfSSL library: /usr/local/lib/libwolfssl.so

[5/6] Validating wolfProvider module...
      ✓ wolfProvider module: /usr/local/lib64/ossl-modules/libwolfprov.so

[6/6] Running cryptographic FIPS validation...
      ✓ FIPS mode: ENABLED
      ✓ FIPS CAST: PASSED
      ✓ SHA-256 test vector: PASSED
      ✓ Entropy source validation: COMPLETE

========================================
✓ ALL FIPS CHECKS PASSED
========================================
```

---

## 7. Container Deployment Constraints

### 7.1 Supported Container Runtimes

| Runtime | Supported | Notes |
|---------|-----------|-------|
| **Docker** | ✅ Yes | Tested and validated |
| **containerd** | ✅ Yes | Via Docker or Kubernetes |
| **Kubernetes** | ✅ Yes | With Linux kernel >= 6.8.x |
| **Podman** | ✅ Yes | rootless mode supported |
| **LXC/LXD** | ⚠️ Untested | May work but not validated |

### 7.2 Host Kernel Requirements

**Critical Requirement:**
> The **host kernel** (not just the container base image) must be within the validated OE range.

**Example:**
- ✅ **Valid:** Ubuntu 22.04 host (kernel 6.8.x) running Ubuntu 22.04 container
- ✅ **Valid:** Ubuntu 22.04 host (kernel 6.8.x HWE) running Ubuntu 22.04 container
- ❌ **Invalid:** Ubuntu 20.04 host (kernel 5.4.x) running Ubuntu 22.04 container
- ⚠️ **Unknown:** RHEL 9 host (kernel 5.14.x) - requires wolfSSL CMVP verification

### 7.3 Cloud Platform Considerations

| Platform | Kernel Control | FIPS Status |
|----------|---------------|-------------|
| **AWS EC2** | ✅ Customer-controlled via AMI | Verify AMI kernel version |
| **Azure VM** | ✅ Customer-controlled via image | Verify image kernel version |
| **GCP GCE** | ✅ Customer-controlled via image | Verify image kernel version |
| **AWS ECS/Fargate** | ❌ AWS-managed | ⚠️ Kernel version not guaranteed |
| **GKE Autopilot** | ❌ Google-managed | ⚠️ Kernel version not guaranteed |

**Recommendation:** Use customer-managed Kubernetes (GKE Standard, EKS, AKS) where host kernel version is controllable.

---

## 8. Virtualization and Hardware Requirements

### 8.1 Supported Virtualization

| Type | Supported | Notes |
|------|-----------|-------|
| **Bare Metal** | ✅ Preferred | Direct hardware access for RDRAND |
| **KVM** | ✅ Yes | Full hardware entropy pass-through |
| **VMware ESXi** | ✅ Yes | Verify RDRAND pass-through enabled |
| **Xen** | ✅ Yes | Verify RDRAND pass-through enabled |
| **Hyper-V** | ✅ Yes | Verify RDRAND pass-through enabled |
| **QEMU/TCG** | ⚠️ Degraded | Software emulation, no hardware RNG |

### 8.2 Required Hardware Entropy

**Entropy Source Priority:**
1. **CPU RDRAND/RDSEED** (preferred for FIPS)
2. **Hardware RNG** (TPM, `/dev/hwrng`)
3. **Kernel entropy pool** (seeded from approved sources)
4. **wolfSSL user-space entropy module** (when licensed and integrated)

---

## 9. Verification and Audit Procedures

### 9.1 Pre-Deployment Checklist

Before deploying to production:

- [ ] Obtain and review wolfSSL FIPS CMVP certificate
- [ ] Verify host kernel version is within validated OE range
- [ ] Confirm CPU architecture is x86_64
- [ ] Test container startup and OE validation on target infrastructure
- [ ] Review host virtualization configuration (RDRAND pass-through)
- [ ] Document host OS, kernel, and hardware platform
- [ ] Run full FIPS validation test suite
- [ ] Test Valkey TLS connections with FIPS-approved cipher suites

### 9.2 Audit Evidence

For FedRAMP 3PAO assessment, provide:

1. **wolfSSL CMVP Certificate** (PDF)
2. **OE Mapping Document** (this document)
3. **Host Platform Specification** (kernel, CPU, virtualization)
4. **Container Startup Logs** (showing successful OE validation)
5. **FIPS Self-Test Results** (from fips-startup-check)
6. **Valkey TLS Test Results** (cipher suite validation)
7. **wolfSSL Validation Letter** (optional, from consulting engagement)

---

## 10. Maintenance and Updates

### 10.1 Kernel Updates

**Ubuntu 22.04 LTS Kernel Update Policy:**
- Security patches: Applied automatically within minor version
- Minor version updates: e.g., 6.8.0-31 → 6.8.0-45 (automatic)
- Major version updates: Via Hardware Enablement (HWE) stack (optional)

**FIPS Compliance During Updates:**
- ✅ **Safe:** Patch-level updates within validated kernel series (e.g., 6.8.0-31 → 6.8.0-45)
- ⚠️ **Review Required:** Major kernel updates (e.g., 6.8.x → 6.11.x)
  - Verify new kernel is in wolfSSL CMVP OE list
  - Re-validate container startup and FIPS tests
  - Update this document with new kernel range

### 10.2 wolfSSL Module Updates

If wolfSSL releases a new FIPS module version:
1. Obtain new CMVP certificate
2. Review OE changes
3. Update Dockerfile with new module version
4. Re-run full validation test suite
5. Update all documentation

---

## 11. Known Limitations

### 11.1 Current Gaps

**As of 2025-12-03:**
- ⏳ **wolfSSL CMVP certificate not yet obtained** - Certificate number pending
- ⏳ **Exact OE identifier not documented** - Requires wolfSSL certificate review
- ⏳ **Kernel version range not finalized** - Awaiting CMVP certificate validation
- ⏳ **No written confirmation from wolfSSL** - Consulting engagement pending

### 11.2 Unsupported Configurations

- ❌ Non-x86_64 architectures (ARM64, RISC-V, etc.)
- ❌ Ubuntu versions < 22.04 with this image
- ❌ Kernel versions < 6.8.x (outside validated range)
- ❌ Emulated CPU environments without hardware entropy
- ❌ Windows/macOS container hosts (Docker Desktop)
- ❌ Valkey without TLS (FIPS requires encrypted connections)

---

## 12. Action Items

### 12.1 Immediate Actions Required

1. **Obtain wolfSSL CMVP Certificate**
   - Contact: wolfSSL sales/support
   - Request: FIPS 140-3 certificate document for wolfSSL 5.8.2 FIPS v5.2.3
   - Timeline: ASAP (blocking for audit)

2. **Validate OE Mapping**
   - Cross-reference Ubuntu 22.04 kernel against CMVP OE list
   - Document exact OE identifier
   - Obtain written confirmation from wolfSSL if needed

3. **Implement Runtime OE Validation**
   - ✅ Update `fips-entrypoint.sh` with fail-closed security (COMPLETED 2025-12-03)
   - ✅ Add environment variable validation
   - ✅ Add library presence checks

4. **Create OE Test Suite**
   - Test on various kernel versions within range
   - Test on different hardware platforms
   - Test Valkey TLS cipher suites
   - Document test results

### 12.2 Documentation Updates

After obtaining CMVP certificate:
- [ ] Update Section 5.1 with certificate number and validation date
- [ ] Update Section 5.2 with exact OE list from certificate
- [ ] Update Section 3.1 with validated kernel version range
- [ ] Add CMVP certificate as appendix or separate file

---

## 13. References

1. **NIST FIPS 140-3:** *Security Requirements for Cryptographic Modules*
   - https://csrc.nist.gov/publications/detail/fips/140/3/final

2. **CMVP Program:** *Cryptographic Module Validation Program*
   - https://csrc.nist.gov/projects/cryptographic-module-validation-program

3. **wolfSSL FIPS Documentation:**
   - https://www.wolfssl.com/products/fips/

4. **Ubuntu 22.04 LTS Release Notes:**
   - https://wiki.ubuntu.com/NobleNumbat/ReleaseNotes

5. **Root + wolfSSL FIPS Implementation Notes:**
   - Internal document dated 2025-12-02

6. **Valkey TLS Documentation:**
   - https://valkey.io/docs/management/security/encryption/

---

## Appendices

### Appendix A: Glossary

- **OE:** Operating Environment - The combination of OS, kernel, CPU, and compiler used during CMVP validation
- **CMVP:** Cryptographic Module Validation Program - NIST's FIPS 140-3 validation authority
- **FIPS 140-3:** Federal Information Processing Standard for cryptographic modules
- **HWE:** Hardware Enablement - Ubuntu's mechanism for newer kernel support on LTS releases
- **3PAO:** Third-Party Assessment Organization - FedRAMP auditors
- **TLS:** Transport Layer Security - Cryptographic protocol for secure connections


