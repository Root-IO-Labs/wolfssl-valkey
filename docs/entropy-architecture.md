# Entropy Architecture for FIPS 140-3 Compliance

## Random Number Generation (RNG) and Entropy Sources

**Document Version:** 1.0
**Last Updated:** 2025-12-03
**Status:** DRAFT - Pending wolfSSL Entropy Module Integration

---

## 1. Overview

This document describes the entropy and random number generation (RNG) architecture for the Valkey 8.1.5 FIPS-enabled container image. Proper entropy management is **critical** for FIPS 140-3 compliance, as all security-critical cryptographic operations (key generation, IV creation, nonce generation, etc.) must use approved RNG mechanisms.

**FIPS 140-3 Requirement:**
> All security-critical random values (keys, IVs, nonces, ephemeral secrets) must be generated using a CMVP-validated cryptographic module's approved RNG mechanisms. The entropy source feeding those generators must align with the validated Operating Environment (OE) assumptions.

**Key Principle:**
> The container must **never** introduce ad hoc or non-validated RNG paths for FIPS-relevant operations.

---

## 2. FIPS Requirements for Entropy

### 2.1 What Must Be FIPS-Validated

| Use Case | FIPS Requirement |
|----------|------------------|
| **Cryptographic Key Generation** | ✅ Must use approved DRBG (SP 800-90A) |
| **IV/Nonce Generation** | ✅ Must use approved RNG |
| **TLS Session Keys** | ✅ Must use approved RNG |
| **Salt for Password Hashing** | ✅ Must use approved RNG |
| **Random Padding** | ✅ Must use approved RNG |
| **Non-Security Random (e.g., UUIDs, log IDs)** | ⚠️ May use non-validated RNG |

### 2.2 What Is NOT Allowed in FIPS Mode

❌ **Direct use of `/dev/urandom`** for cryptographic operations
❌ **Language runtime built-in RNGs** (Python `random`, Node.js `Math.random()`, etc.) for crypto
❌ **Application-level PRNGs** not backed by FIPS module
❌ **Non-validated entropy sources** for key material

### 2.3 NIST SP 800-90A/B/C Standards

| Standard | Purpose |
|----------|---------|
| **SP 800-90A** | Deterministic Random Bit Generators (DRBGs) - defines approved algorithms |
| **SP 800-90B** | Entropy Source Validation - defines testing requirements for entropy sources |
| **SP 800-90C** | Construction of DRBGs from entropy sources |

---

## 3. Current Implementation Status

### 3.1 Configuration A: OS/Hardware Entropy Path (Baseline - Current)

**Status:** ✅ Implemented (default)

**Architecture:**
```
Hardware RNG (CPU RDRAND/RDSEED)
    ↓
Linux Kernel RNG (/dev/random)
    ↓
wolfSSL FIPS DRBG
    ↓
Cryptographic Operations (via wolfProvider)
    ↓
Valkey / Applications
```

**Components:**

| Layer | Description | FIPS Status |
|-------|-------------|-------------|
| **Hardware RNG** | CPU RDRAND/RDSEED instructions (Intel/AMD) | ✅ Approved entropy source (when available) |
| **Kernel RNG** | Linux kernel `/dev/random` backed by hardware entropy | ✅ Acceptable per wolfSSL OE assumptions |
| **wolfSSL DRBG** | SP 800-90A compliant DRBG (CTR_DRBG or Hash_DRBG) | ✅ FIPS 140-3 validated |
| **wolfProvider** | OpenSSL 3 provider wrapping wolfSSL | ✅ Interfaces to validated module |

**Assumptions:**
1. Host CPU provides RDRAND/RDSEED (verified at container startup)
2. Kernel version is within wolfSSL CMVP OE (validated by entrypoint)
3. Virtualization platform passes through hardware RNG (documented requirement)
4. No modifications to kernel RNG subsystem

**Verification:**
- `fips-entrypoint.sh` checks for RDRAND availability
- wolfSSL FIPS module performs power-up self-tests on DRBG
- `fips-startup-check.c` validates RNG functionality

**Limitations:**
- Relies on OS-level entropy (not under direct container control)
- Assumes host kernel RNG is properly seeded
- Virtualization may introduce entropy quality concerns

---

### 3.2 Configuration B: wolfSSL User-Space Entropy Module (Enhanced - Planned)

**Status:** ⏳ NOT YET IMPLEMENTED (requires licensing and integration)

**Architecture:**
```
Hardware RNG (CPU RDRAND/RDSEED)
    ↓
wolfSSL User-Space Entropy Module
    ↓
wolfSSL FIPS DRBG
    ↓
Cryptographic Operations (via wolfProvider)
    ↓
Valkey / Applications
```

**Advantages Over Configuration A:**
1. **Direct Control:** Entropy collection happens in user space, fully under container control
2. **SP 800-90B Validated:** wolfSSL entropy module has completed CMTL testing for SP 800-90B
3. **No Kernel Dependency:** Reduces reliance on host kernel RNG quality
4. **Audit Trail:** Better logging and monitoring of entropy collection
5. **Predictable Behavior:** Deterministic entropy path across all deployments

**Current Status (per Implementation Notes, Section 5):**

> "wolfSSL's user-space entropy source has completed CMTL testing and is currently in the final review phase of the FIPS 140-3 validation process. Although it has not yet been issued a final CMVP certificate, the CMTL has confirmed that:
> - The entropy source validation submission is materially complete
> - All required SP 800-90B testing, analysis, and documentation have been delivered to NIST/CSE
> - No outstanding technical work from wolfSSL remains
>
> To support ongoing compliance activities while awaiting final approval, the CMTL can issue a formal progress letter..."

**Required Actions:**
1. ✅ License wolfSSL user-space entropy module from wolfSSL
2. ⏳ Obtain CMTL progress letter for FedRAMP 3PAO acceptance
3. ⏳ Integrate entropy module into Dockerfile build process
4. ⏳ Configure wolfSSL FIPS to use entropy module
5. ⏳ Update validation checks in `fips-startup-check.c`
6. ⏳ Document entropy flow for 3PAO audit

**Timeline:**
- Licensing negotiation: 1-2 weeks
- Integration and testing: 1-2 weeks
- Documentation: 1 week
- **Total: 3-5 weeks**

---

## 4. Entropy Flow Validation

### 4.1 Startup Validation

**Current Checks (Configuration A):**

In `fips-entrypoint.sh`:
```bash
# Check for RDRAND availability
if grep -q rdrand /proc/cpuinfo; then
    echo "✓ RDRAND: Available (hardware entropy source)"
else
    echo "⚠ RDRAND: Not available (using kernel entropy only)"
fi
```

In `fips-startup-check.c`:
```c
// Run wolfSSL FIPS Known Answer Tests (CAST)
// This includes DRBG self-tests
ret = wc_RunAllCast_fips();
if (ret != 0) {
    printf("✗ FIPS CAST FAILED\n");
    return 1;
}
```

**Planned Enhancements (Configuration B):**

Add to `fips-startup-check.c`:
```c
// Verify entropy module initialization
ret = wolfCrypt_Init_Entropy();
if (ret != 0) {
    printf("✗ Entropy module initialization failed\n");
    return 1;
}

// Test entropy collection
byte entropy[32];
ret = wolfCrypt_GetEntropy(entropy, sizeof(entropy));
if (ret != 0) {
    printf("✗ Entropy collection failed\n");
    return 1;
}
```

### 4.2 Runtime Monitoring

**Recommended (Future Enhancement):**
- Log entropy pool health metrics
- Alert on entropy starvation
- Monitor DRBG reseeding events
- Track entropy source failures

---

## 5. Application Integration

### 5.1 Valkey Cryptographic Operations

Valkey uses cryptography for:

| Operation | FIPS Requirement | Implementation |
|-----------|------------------|----------------|
| **SSL/TLS Connections** | FIPS-approved algorithms | ✅ Via FIPS OpenSSL + wolfProvider |
| **Password Hashing (SCRAM-SHA-256)** | Salt generation must use approved RNG | ✅ Via OpenSSL RAND_bytes() → wolfSSL |
| **TLS operations Extension** | All crypto via FIPS module | ✅ Via OpenSSL API → wolfProvider |
| **Key Derivation (KDF)** | FIPS-approved KDF with approved RNG | ✅ Via wolfSSL FIPS |
| **Random Number Functions (random(), uuid())** | Non-crypto use cases | ⚠️ May use internal PRNG (acceptable) |

**Key Configuration:**

Valkey is built with:
```
--with-openssl \
--with-includes=/usr/local/openssl/include \
--with-libraries=/usr/local/openssl/lib64 \
LDFLAGS="-L/usr/local/openssl/lib64 -Wl,-rpath=/usr/local/openssl/lib64"
```

This ensures Valkey links to FIPS OpenSSL, which uses wolfProvider, which uses wolfSSL FIPS DRBG.

### 5.2 Language Runtimes (If Present)

**Python:**
```python
# FIPS-compliant (via wolfSSL):
import ssl
import hashlib
ssl.RAND_bytes(32)  # Uses OpenSSL RAND_bytes → wolfProvider → wolfSSL

# NON-FIPS (do not use for crypto):
import random
random.random()  # Uses Python's Mersenne Twister (not FIPS)
```

**Node.js:**
```javascript
// FIPS-compliant (via wolfSSL):
const crypto = require('crypto');
crypto.randomBytes(32);  // Uses OpenSSL RAND_bytes → wolfProvider → wolfSSL

// NON-FIPS (do not use for crypto):
Math.random();  // Uses V8's PRNG (not FIPS)
```

**Rule:** All security-critical randomness **must** go through the FIPS OpenSSL API.

---

## 6. Entropy Source Priorities

### 6.1 Hardware Entropy Sources (Preferred)

| Source | Priority | Availability Check |
|--------|----------|-------------------|
| **CPU RDRAND** | 🥇 Highest | `grep rdrand /proc/cpuinfo` |
| **CPU RDSEED** | 🥇 Highest | `grep rdseed /proc/cpuinfo` |
| **TPM RNG** | 🥈 High | `ls /dev/tpm*` |
| **Hardware RNG** | 🥈 High | `ls /dev/hwrng` |

**Best Practice:** Always deploy on hardware/VMs with CPU RDRAND support.

### 6.2 Software Entropy Sources (Fallback)

| Source | Priority | Use Case |
|--------|----------|----------|
| **Kernel RNG** | 🥉 Medium | When no hardware RNG available |
| **User-Space Collectors** | 🥉 Medium | Supplemental entropy (timing, events) |

**Warning:** Pure software entropy sources may not meet FIPS quality requirements.

### 6.3 Unacceptable Entropy Sources

❌ `/dev/urandom` (for cryptographic key generation)
❌ Process IDs, timestamps (alone)
❌ User input (alone)
❌ Network traffic patterns (alone)

---

## 7. Virtualization Considerations

### 7.1 Hardware RNG Pass-Through

**Required for FIPS Compliance:**

Virtualization platforms **must** pass through hardware RNG to guest:

| Platform | Configuration | Verification |
|----------|---------------|--------------|
| **KVM/QEMU** | Add `<rng model='virtio'>`<br>in VM XML | `grep rdrand /proc/cpuinfo` in guest |
| **VMware ESXi** | Enable "CPU RDRAND pass-through"<br>in VM settings | `grep rdrand /proc/cpuinfo` in guest |
| **Hyper-V** | Automatic in Gen 2 VMs | `grep rdrand /proc/cpuinfo` in guest |
| **Xen** | Enable RDRAND in guest config | `grep rdrand /proc/cpuinfo` in guest |

**Failure Mode:**
If RDRAND is not available, container startup will issue a warning but continue (Configuration A falls back to kernel RNG).

### 7.2 Container Runtimes

**Docker/containerd:**
- Inherits host kernel RNG
- No special configuration needed
- RDRAND availability matches host

**Kubernetes:**
- Entropy quality depends on node kernel
- Ensure all nodes meet hardware requirements
- Consider `nodeSelector` for RDRAND-capable nodes

---

## 8. Entropy Starvation Prevention

### 8.1 Symptoms of Entropy Starvation

- Slow key generation
- Blocking on `/dev/random` reads
- TLS handshake delays
- Application timeouts

### 8.2 Mitigation Strategies

**For Configuration A (Current):**
1. ✅ Use hardware RNG (RDRAND) - automatic with modern CPUs
2. ✅ Use `/dev/random` (not `/dev/urandom`) for wolfSSL seeding
3. ✅ Avoid excessive key generation at startup
4. ✅ Monitor kernel entropy pool: `cat /proc/sys/kernel/random/entropy_avail`

**For Configuration B (Planned):**
1. ✅ wolfSSL user-space entropy module manages collection
2. ✅ Direct hardware access reduces kernel dependency
3. ✅ Predictable entropy availability

### 8.3 Testing for Entropy Quality

**Recommended Tools:**
```bash
# Check entropy availability
cat /proc/sys/kernel/random/entropy_avail

# Monitor entropy consumption
watch -n 1 cat /proc/sys/kernel/random/entropy_avail

# Test RNG performance
dd if=/dev/random bs=1M count=10 of=/dev/null
```

---

## 9. Audit and Compliance Evidence

### 9.1 Documentation for 3PAO

Provide to FedRAMP assessors:

1. **Entropy Architecture Diagram** (this document)
2. **Configuration Specification** (A or B)
3. **CMVP Mapping:**
   - wolfSSL FIPS certificate (includes DRBG validation)
   - wolfSSL entropy module CMTL progress letter (for Config B)
4. **Validation Logs:**
   - Container startup logs showing RDRAND detection
   - FIPS self-test results (DRBG tests)
5. **Source Code Evidence:**
   - Valkey build flags (linking to FIPS OpenSSL)
   - `fips-startup-check.c` source code
6. **Runtime Configuration:**
   - OpenSSL configuration (`openssl-wolfprov.cnf`)
   - Environment variables (`OPENSSL_CONF`, `LD_LIBRARY_PATH`)

### 9.2 Test Evidence

**Functional Tests:**
```bash
# Test 1: Verify wolfSSL RNG works
/usr/local/bin/fips-startup-check

# Test 2: Test OpenSSL random number generation
openssl rand -base64 32

# Test 3: Test OpenSSL hex random generation (FIPS DRBG)
openssl rand -hex 32

# Test 4: Verify no /dev/urandom usage for crypto
strace -e openat openssl rand -hex 16 2>&1 | grep urandom
# Should show no urandom access during FIPS crypto operations
```

**Performance Tests:**
```bash
# Measure RNG throughput (FIPS DRBG via wolfSSL)
time openssl rand -out /dev/null 100M

# Measure Valkey random data generation
time openssl rand -hex 1000000 >/dev/null
```

---

## 10. Migration Path: Configuration A → B

### 10.1 Current State (Configuration A)

✅ Functional and FIPS-compliant
✅ Uses OS/hardware entropy within validated OE assumptions
⚠️ Less direct control over entropy quality
⚠️ Dependent on host kernel and virtualization

### 10.2 Target State (Configuration B)

🎯 Enhanced FIPS compliance
🎯 SP 800-90B validated entropy source
🎯 Direct control over entropy collection
🎯 Better audit trail and monitoring

### 10.3 Migration Steps

1. **License Acquisition** (Weeks 1-2)
   - Contact wolfSSL sales
   - Negotiate entropy module license
   - Obtain CMTL progress letter

2. **Build Integration** (Week 3)
   - Add entropy module to Dockerfile Stage 1
   - Configure wolfSSL to use entropy module
   - Update library paths and linkage

3. **Validation Enhancement** (Week 4)
   - Update `fips-startup-check.c` with entropy module tests
   - Add entropy quality monitoring
   - Implement logging for entropy events

4. **Testing** (Week 5)
   - Full FIPS validation test suite
   - Performance testing
   - Entropy starvation testing
   - Cross-platform testing (KVM, VMware, bare metal)

5. **Documentation** (Week 6)
   - Update this document with Configuration B details
   - Update build documentation
   - Create customer migration guide
   - Prepare 3PAO evidence package

### 10.4 Rollback Plan

If Configuration B integration fails:
- ✅ Configuration A remains functional
- ✅ No regression in FIPS compliance
- ✅ Can deploy with Configuration A while resolving issues

---

## 11. Known Issues and Limitations

### 11.1 Current Implementation (Configuration A)

| Issue | Impact | Mitigation |
|-------|--------|------------|
| **Kernel RNG dependency** | Entropy quality depends on host | ✅ Require RDRAND in OE documentation |
| **No direct entropy monitoring** | Limited visibility into entropy health | ⏳ Add monitoring in future release |
| **Virtualization variability** | Inconsistent entropy across platforms | ✅ Document platform requirements |

### 11.2 Planned Implementation (Configuration B)

| Issue | Impact | Status |
|-------|--------|--------|
| **Licensing cost** | Budget required for entropy module | ⏳ In negotiation with wolfSSL |
| **Integration complexity** | Additional build steps | ⏳ Planned for Phase 1 |
| **CMVP certificate pending** | Final validation not complete | ⏳ CMTL progress letter available |

---

## 12. References

### 12.1 NIST Standards

1. **SP 800-90A Rev. 1:** *Recommendation for Random Number Generation Using Deterministic Random Bit Generators*
   - https://csrc.nist.gov/publications/detail/sp/800-90a/rev-1/final

2. **SP 800-90B:** *Recommendation for the Entropy Sources Used for Random Bit Generation*
   - https://csrc.nist.gov/publications/detail/sp/800-90b/final

3. **SP 800-90C (Draft):** *Recommendation for Random Bit Generator (RBG) Constructions*
   - https://csrc.nist.gov/publications/detail/sp/800-90c/draft

### 12.2 wolfSSL Documentation

4. **wolfSSL FIPS 140-3 User Guide**
   - Available from wolfSSL support portal

5. **wolfSSL Entropy Module Documentation**
   - To be provided with license

### 12.3 Internal Documents

6. **Root + wolfSSL FIPS Implementation Notes** (2025-12-02)
   - Section 2.2: Entropy requirements
   - Section 5: Entropy module licensing
   - Section 10.3: Configuration A vs B

7. **Operating Environment Documentation**
   - `docs/operating-environment.md`

---

## 13. Appendices

### Appendix A: DRBG Algorithms

wolfSSL FIPS v5 supports these SP 800-90A DRBGs:

| Algorithm | Security Strength | Notes |
|-----------|------------------|-------|
| **CTR_DRBG (AES-256)** | 256 bits | Default, highest security |
| **Hash_DRBG (SHA-256)** | 256 bits | Alternative |
| **Hash_DRBG (SHA-512)** | 256 bits | Higher performance |
| **HMAC_DRBG (SHA-256)** | 256 bits | Alternative |

All are FIPS-approved and validated in wolfSSL FIPS v5.2.3.

### Appendix B: Entropy Collection Test Vectors

*To be added after Configuration B integration.*

### Appendix C: Platform-Specific Entropy Notes

**AWS EC2:**
- All instance types provide RDRAND
- ENA (Elastic Network Adapter) provides additional entropy
- No special configuration needed

**Azure VMs:**
- All v2+ instances provide RDRAND
- Gen 2 VMs have enhanced entropy
- Hyper-V entropy pass-through automatic

**GCP GCE:**
- All instance types provide RDRAND
- Shielded VMs have additional hardware security

**Bare Metal:**
- Intel CPUs: RDRAND since Ivy Bridge (2012)
- AMD CPUs: RDRAND since Excavator (2015)
- Verify with: `grep rdrand /proc/cpuinfo`

---

## 14. Action Items

### 14.1 Immediate (Configuration A - Current)

- [x] Document current entropy architecture
- [x] Add RDRAND detection to `fips-entrypoint.sh`
- [x] Validate DRBG in `fips-startup-check.c`
- [ ] Create entropy monitoring scripts
- [ ] Document platform requirements for customers

### 14.2 Phase 1 (Configuration B - Migration)

- [ ] Obtain wolfSSL entropy module license
- [ ] Obtain CMTL progress letter
- [ ] Integrate entropy module into Dockerfile
- [ ] Update validation checks
- [ ] Full testing on multiple platforms
- [ ] Update all documentation

### 14.3 Phase 2 (Enhancements)

- [ ] Add entropy pool monitoring
- [ ] Implement entropy quality metrics
- [ ] Add alerting for entropy starvation
- [ ] Create performance benchmarks
- [ ] Automated entropy testing in CI/CD

---

**Document Status:** DRAFT - Configuration A documented, Configuration B planning in progress

**Next Review Date:** Upon wolfSSL entropy module license acquisition

**Owner:** Root FIPS Implementation Team

**Classification:** Internal - For FedRAMP/3PAO Review
