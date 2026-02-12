# FIPS-Enabled Valkey Docker Image

This directory contains a **FIPS 140-3 compliant** Valkey 8.1.5 Docker image built on Ubuntu 22.04, using wolfSSL FIPS v5.7.2 (CMVP Certificate #4718) for cryptographic operations.

## Overview

This implementation creates a production-ready, FIPS-validated Valkey container that:
- ✅ Uses **Ubuntu 22.04** as the base image (matching Bitnami)
- ✅ Uses **Ubuntu system OpenSSL 3.0.x** (libssl3 package) with wolfProvider
- ✅ Integrates **wolfSSL FIPS v5.7.2** (CMVP Certificate #4718 - FIPS 140-3 validated)
- ✅ Uses **wolfProvider** to bridge OpenSSL 3 and wolfSSL FIPS
- ✅ Builds **Valkey 8.1.5** with TLS support using Ubuntu system OpenSSL
- ✅ Preserves **Bitnami scripts** unchanged for compatibility
- ✅ Performs **automatic FIPS validation** on container startup
- ✅ Safe for `apt upgrade` - no package conflicts with Ubuntu package database

## Security Updates (8.1.5)

**Important**: This version includes critical security fixes from Valkey 8.1.3, 8.1.4, and 8.1.5:

### Version 8.1.5 (December 4, 2025)
- **Upgrade Urgency**: MODERATE
- Fix Lua VM crash after FUNCTION FLUSH ASYNC + FUNCTION LOAD (#1826)
- Fix invalid memory address caused by hashtable shrinking during safe iteration (#2753)
- Cluster: Avoid usage of light weight messages to nodes with not ready bidirectional links (#2817)
- Send duplicate multi meet packet only for node which supports it (#2840)
- Fix loading AOF files from future Valkey versions (#2899)

### Version 8.1.4 (October 3, 2025)
- **Upgrade Urgency**: SECURITY (Critical)
- **CVE-2025-49844**: Fix Lua script leading to remote code execution
- **CVE-2025-46817**: Fix Lua script integer overflow and potential RCE
- **CVE-2025-46818**: Fix Lua script execution in context of another user
- **CVE-2025-46819**: Fix LUA out-of-bound read

### Version 8.1.3 (July 7, 2025)
- **Upgrade Urgency**: SECURITY (Critical)
- **CVE-2025-32023**: Prevent out-of-bounds write during hyperloglog operations (#2146)
- **CVE-2025-48367**: Retry accept on transient errors (#2315)
- Fix missing response when AUTH is errored inside a transaction (#2287)

**Recommendation**: Always use the latest version (8.1.5) for production deployments to ensure all security patches are applied.

## Architecture

### Multi-Stage Build

The Dockerfile uses a multi-stage build approach with **Ubuntu system OpenSSL** + **wolfProvider**:

**Stage 1: Builder (Ubuntu 22.04)**
1. Installs Ubuntu OpenSSL development headers (`libssl-dev` package)
2. Builds **wolfSSL FIPS v5.7.2** from commercial archive (CMVP Certificate #4718)
3. Builds **wolfProvider** to integrate wolfSSL with system OpenSSL (configured with `--with-openssl=/usr`)
4. Builds **Valkey 8.1.5** with `BUILD_TLS=yes OPENSSL_PREFIX=/usr` (uses Ubuntu system OpenSSL)
5. Compiles FIPS startup validation utility

**Stage 2: Runtime (Ubuntu 22.04)**
1. Installs Ubuntu **libssl3 package** (system OpenSSL 3.0.x runtime)
2. Copies Valkey binaries and wolfSSL/wolfProvider libraries from builder
3. Copies unchanged Bitnami scripts for compatibility
4. Configures OpenSSL to use wolfProvider (`/etc/ssl/openssl-wolfprov.cnf`)
5. Sets up FIPS validation entrypoint

### FIPS Compliance Architecture

This image uses the **Ubuntu OpenSSL + wolfProvider** model for FIPS 140-3 compliance:

**Cryptographic Flow:**
```
Valkey Application
    ↓
Ubuntu System OpenSSL 3.0.x API (/usr/lib/x86_64-linux-gnu/)
    ↓
wolfProvider (/usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so)
    ↓
wolfSSL FIPS v5.7.2 (CMVP Certificate #4718)
```

**Key Components:**
- **OpenSSL**: Ubuntu libssl3 package (3.0.x) - provides standard crypto API
- **wolfProvider**: OpenSSL 3 provider that wraps wolfSSL FIPS
- **wolfSSL FIPS v5.7.2**: FIPS 140-3 validated cryptographic module (CMVP #4718)
- **FIPS Boundary**: Limited to Valkey application cryptographic operations

**Important Clarifications:**
1. **FIPS Compliance Scope**: Applies to Valkey application only, not the entire container OS
2. **System Libraries**: Non-FIPS crypto libraries (e.g., libgcrypt20) may be present as OS dependencies but are NOT used by Valkey
3. **Package Safety**: Using Ubuntu packages allows safe `apt upgrade` without conflicts
4. **Verification**: All Valkey crypto operations verified to use wolfProvider via `ldd` analysis

Per NIST SP 800-53 Rev. 5 SC-13 guidance, FIPS compliance is satisfied when the application in scope (Valkey) uses only FIPS-validated cryptographic modules for all its cryptographic operations.

### FIPS Validation Flow

```
Container Start
    ↓
FIPS Entrypoint (fips-entrypoint.sh)
    ↓
Environment Checks (OPENSSL_CONF, OPENSSL_MODULES, LD_LIBRARY_PATH)
    ↓
OpenSSL 3.x Verification
    ↓
wolfSSL Library Check
    ↓
wolfProvider Module Check
    ↓
Cryptographic Validation (fips-startup-check)
    ├─ FIPS Compile-Time Flags
    ├─ Known Answer Tests (CAST)
    └─ SHA-256 Test Vector
    ↓
Valkey Binary Verification
    ↓
Bitnami Entrypoint (/opt/bitnami/scripts/valkey/entrypoint.sh)
    ↓
Valkey Server Start
```

## Files

| File | Description |
|------|-------------|
| `Dockerfile` | Multi-stage build for FIPS Valkey |
| `Dockerfile.hardened` | FIPS + STIG/CIS hardened variant |
| `openssl-wolfprov.cnf` | OpenSSL configuration to load wolfProvider |
| `fips-startup-check.c` | C program for FIPS validation at startup |
| `fips-entrypoint.sh` | Entrypoint wrapper for FIPS validation |
| `test-fips.c` | wolfSSL FIPS test for builder stage |
| `build.sh` | Build script for FIPS Valkey with pre-checks and verification |
| `build-hardened.sh` | Build script for FIPS + STIG/CIS hardened variant |
| `test-valkey-fips.sh` | Comprehensive test suite |
| `prebuildfs/` | Bitnami helper scripts (copied from original) |
| `rootfs/` | Valkey-specific scripts (copied from original) |
| `hardening/` | STIG/CIS hardening scripts |
| `README.md` | This file |

## Prerequisites

1. **Docker with BuildKit support**
   ```bash
   docker --version  # Docker 19.03+
   docker buildx version
   ```

2. **wolfSSL Commercial Password**
  Create a file named `wolfssl_password.txt` containing your wolfSSL FIPS download password:

```bash
echo "your_password_here" > wolfssl_password.txt
```


3. **Internet Connection**
   - Required for downloading OpenSSL, wolfSSL, wolfProvider, and Valkey sources

## Building the Image

### Option 1: Using the Build Script (Recommended)

```bash
./build.sh
```

The build script will:
- Validate prerequisites
- Build the Docker image
- Display build information
- Offer to run the test suite

### Option 2: Manual Docker Build

```bash
# Build standard FIPS image with cache
docker build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  -t valkey-fips:8.1.5-ubuntu-22.04 \
  .

# Build without cache
docker build \
  --no-cache \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  -t valkey-fips:8.1.5-ubuntu-22.04 \
  .
```

### Option 3: STIG/CIS Hardened Build

For environments requiring STIG/CIS security compliance in addition to FIPS:

```bash
# Using the hardened build script
./build-hardened.sh

# Or manual build with Dockerfile.hardened
docker build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  -f Dockerfile.hardened \
  -t valkey-fips-hardened:8.1.5-ubuntu-22.04 \
  .
```

The hardened variant includes:
- All FIPS 140-3 compliance features from the standard build
- Ubuntu 22.04 STIG security hardening
- CIS Benchmark compliance measures
- Additional security controls and reduced attack surface

**Build Time**:
- Standard FIPS build: Approximately 15-20 minutes
- Hardened build: Approximately 20-25 minutes (depending on system)

## Testing

### Automated Test Suite

The `test-valkey-fips.sh` script performs comprehensive validation of the FIPS-enabled Valkey container.

#### Run the Test Suite

```bash
# From the FIPS directory
./test-valkey-fips.sh

# Or specify a custom container name
./test-valkey-fips.sh my-custom-container-name
```

#### What the Test Suite Does

The script automatically:
1. ✅ **Checks if image exists** - Verifies the built image
2. ✅ **Starts a test container** - Creates a temporary container
3. ✅ **Validates FIPS** - Checks logs for "ALL FIPS CHECKS PASSED"
4. ✅ **Verifies Valkey process** - Ensures valkey-server is running
5. ✅ **Tests basic operations** - PING, SET, GET commands
6. ✅ **Checks OpenSSL config** - Verifies OpenSSL 3.x and wolfProvider
7. ✅ **Validates libraries** - Confirms wolfSSL FIPS library exists
8. ✅ **Checks environment** - Verifies FIPS env variables
9. ✅ **Performance test** - Basic latency check
10. ✅ **Cleanup option** - Asks if you want to keep container running

#### Expected Output

```bash
========================================
FIPS Valkey Test Suite
========================================

[PASS] Image found: valkey-fips:8.1.5-ubuntu-22.04
[PASS] Container started: valkey-fips-test
[PASS] FIPS validation passed in container logs
[PASS] Valkey server process is running
[PASS] PING command successful
[PASS] SET command successful
[PASS] GET command successful (value: FIPS_140_3)
[PASS] OpenSSL 3.x detected: OpenSSL 3.0.2 (Ubuntu system package)
[PASS] wolfProvider is loaded
[PASS] Valkey version: Valkey ...
[PASS] wolfSSL FIPS v5.7.2 library found
[PASS] OPENSSL_CONF is set: /etc/ssl/openssl-wolfprov.cnf
[PASS] OPENSSL_MODULES is set: /usr/lib/x86_64-linux-gnu/ossl-modules
[PASS] Performance test completed

========================================
✓ ALL TESTS PASSED
========================================

Container Information:
  Container Name: valkey-fips-test
  Image: valkey-fips:8.1.5-ubuntu-22.04
  Status: Running with FIPS 140-3 validation

Keep container running? [Y/n]
```

#### Test Suite Features

- **Automatic cleanup**: Removes existing test containers
- **Detailed logging**: Shows exactly what's being tested
- **Color output**: Green for pass, red for fail
- **Interactive**: Asks if you want to keep the container running
- **Default container name**: `valkey-fips-test` (can be customized)
- **No password required**: Test runs with `ALLOW_EMPTY_PASSWORD=yes`

### Manual Testing

**Start a container:**
```bash
docker run -d \
  --name valkey-fips \
  -p 6379:6379 \
  -e ALLOW_EMPTY_PASSWORD=yes \
  valkey-fips:8.1.5-ubuntu-22.04
```

**Check FIPS validation in logs:**
```bash
docker logs valkey-fips | grep "FIPS"
```

Expected output:
```
========================================
Valkey FIPS Container Startup
Ubuntu 22.04 + Bitnami Scripts
========================================

[1/6] Validating Operating Environment (OE) for CMVP compliance...
      Detected kernel: 6.x.x-xx-generic
      ✓ CPU architecture: x86_64
      ✓ RDRAND: Available (hardware entropy source)
      ✓ AES-NI: Available (hardware-accelerated AES)

[2/6] Validating FIPS environment variables...
      ✓ OPENSSL_CONF: /etc/ssl/openssl-wolfprov.cnf
      ✓ OPENSSL_MODULES: /usr/lib/x86_64-linux-gnu/ossl-modules
      ✓ LD_LIBRARY_PATH: /usr/local/lib:/usr/lib/x86_64-linux-gnu

[3/6] Validating OpenSSL installation...
      ✓ OpenSSL found: OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)
      ✓ Using Ubuntu system OpenSSL 3.x with wolfProvider

[4/6] Validating wolfSSL library...
      ✓ wolfSSL library: /usr/local/lib/libwolfssl.so

[5/6] Validating wolfProvider module...
      ✓ wolfProvider module: /usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so
      ✓ Module size: ... bytes
      → Testing provider loading...
      ✓ wolfProvider successfully loaded by OpenSSL

[5.5/6] Verifying Ubuntu OpenSSL libraries with wolfProvider...
      ✓ Ubuntu OpenSSL library found: /usr/lib/x86_64-linux-gnu/libssl.so.3
      ✓ Ubuntu OpenSSL library found: /usr/lib/x86_64-linux-gnu/libcrypto.so.3
      ✓ wolfProvider module found: /usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so
      ✓ Ubuntu OpenSSL 3.x with wolfProvider verified
      ✓ All Valkey crypto operations will use wolfSSL FIPS v5.7.2

[6/6] Running cryptographic FIPS validation...

========================================
FIPS Startup Validation
========================================

[1/3] Checking FIPS compile-time configuration...
      ✓ FIPS mode: ENABLED
      ✓ FIPS version: 5

[2/3] Running FIPS Known Answer Tests (CAST)...
      ✓ FIPS CAST: PASSED

[3/3] Validating SHA-256 cryptographic operation...
      ✓ SHA-256 test vector: PASSED

========================================
✓ FIPS VALIDATION PASSED
========================================
FIPS 140-3 compliant cryptography verified
Container startup authorized

========================================
✓ ALL FIPS CHECKS PASSED
========================================

Handing control to Bitnami entrypoint...
```

**Connect to Valkey:**
```bash
docker exec -it valkey-fips valkey-cli
```

**Test basic operations:**
```bash
# Inside valkey-cli
127.0.0.1:6379> PING
PONG
127.0.0.1:6379> SET test "FIPS 140-3"
OK
127.0.0.1:6379> GET test
"FIPS 140-3"
127.0.0.1:6379> INFO server
# ... server information ...
```

**Verify OpenSSL configuration:**
```bash
docker exec valkey-fips openssl version
docker exec valkey-fips openssl list -providers
```

Expected provider output:
```
Providers:
  wolfprov
    name: wolfSSL Provider
    ...
```

## Usage Examples

### Basic Valkey Server

**Important**: Bitnami Valkey requires either a password or explicit permission to run without one.

#### Option 1: With Password (Recommended)
```bash
docker run -d \
  --name valkey-fips \
  -p 6379:6379 \
  -e VALKEY_PASSWORD=your_secure_password \
  valkey-fips:8.1.5-ubuntu-22.04
```

#### Option 2: Without Password (Development Only)
```bash
docker run -d \
  --name valkey-fips \
  -p 6379:6379 \
  -e ALLOW_EMPTY_PASSWORD=yes \
  valkey-fips:8.1.5-ubuntu-22.04
```

**Note**: If you see "VALKEY_PASSWORD environment variable is empty" error, use one of the options above.

### With Persistent Storage

```bash
docker run -d \
  --name valkey-fips \
  -p 6379:6379 \
  -v valkey-data:/bitnami/valkey/data \
  valkey-fips:8.1.5-ubuntu-22.04
```

### With Custom Configuration

```bash
docker run -d \
  --name valkey-fips \
  -p 6379:6379 \
  -v $(pwd)/valkey.conf:/opt/bitnami/valkey/etc/valkey.conf \
  valkey-fips:8.1.5-ubuntu-22.04
```

### With Environment Variables (Bitnami)

```bash
docker run -d \
  --name valkey-fips \
  -p 6379:6379 \
  -e VALKEY_PASSWORD=my_password \
  -e VALKEY_EXTRA_FLAGS="--maxmemory 256mb" \
  valkey-fips:8.1.5-ubuntu-22.04
```

### Docker Compose

```yaml
version: '3.8'
services:
  valkey-fips:
    image: valkey-fips:8.1.5-ubuntu-22.04
    container_name: valkey-fips
    ports:
      - "6379:6379"
    volumes:
      - valkey-data:/bitnami/valkey/data
    environment:
      - VALKEY_PASSWORD=my_password
    restart: unless-stopped

volumes:
  valkey-data:
```

## FIPS Compliance

### Cryptographic Module

- **wolfSSL FIPS v5.7.2** (wolfCrypt FIPS 140-3)
- **CMVP Certificate**: #4718
- **Algorithms**: AES, SHA-2, SHA-256, HMAC, RSA, ECDSA, DRBG, and more
- **Status**: FIPS 140-3 validated and approved for use in compliant systems

### Validation

The container performs the following FIPS validations on startup:

1. **Operating Environment (OE)**: Validates kernel version and CPU architecture
2. **Environment Configuration**: Verifies FIPS-required environment variables
3. **OpenSSL Configuration**: Confirms Ubuntu system OpenSSL installation
4. **wolfSSL Library**: Verifies wolfSSL FIPS v5.7.2 library is present
5. **wolfProvider Module**: Ensures wolfProvider is loaded and functional
6. **Ubuntu OpenSSL Libraries**: Validates system OpenSSL with wolfProvider integration
7. **Known Answer Tests (CAST)**: Runs cryptographic self-tests
8. **Algorithm Tests**: Validates SHA-256 operations with test vectors

If any validation fails, the container will **not start** and will exit with an error (fail-closed security model).

### Using FIPS Cryptography

All TLS connections in Valkey automatically use FIPS-validated cryptography through:
1. Valkey is built with `BUILD_TLS=yes OPENSSL_PREFIX=/usr` (Ubuntu system OpenSSL)
2. OpenSSL 3 is configured to load wolfProvider via `/etc/ssl/openssl-wolfprov.cnf`
3. wolfProvider delegates all crypto operations to wolfSSL FIPS v5.7.2 (CMVP #4718)
4. All cryptographic operations use FIPS 140-3 validated algorithms

**Cryptographic Flow:**
```
Valkey TLS Operations
    ↓
Ubuntu OpenSSL 3.0.x API
    ↓
wolfProvider (OpenSSL 3 provider)
    ↓
wolfSSL FIPS v5.7.2 (CMVP Certificate #4718)
```

**No application code changes required** - FIPS compliance is transparent to Valkey!

## Comparison with Original Bitnami Image

| Aspect | Original Bitnami | FIPS-Enabled |
|--------|------------------|--------------|
| Base Image | Debian 12 | Ubuntu 22.04 |
| OpenSSL | System OpenSSL (Debian) | Ubuntu System OpenSSL 3.0.x + wolfProvider |
| Cryptography | Standard | FIPS 140-3 (wolfSSL v5.7.2, CMVP #4718) |
| Crypto Provider | Default | wolfProvider (wraps wolfSSL FIPS) |
| Bitnami Scripts | Included | **Unchanged** - Copied as-is |
| TLS Support | Yes | Yes (FIPS 140-3 validated) |
| Startup Validation | Standard | FIPS validation required (fail-closed) |
| Package Management | apt (Debian) | apt (Ubuntu) - safe for upgrades |
| Container Size | ~120 MB | ~180 MB (includes wolfSSL/wolfProvider) |

### Compatibility

- ✅ **Bitnami scripts are unchanged** - copied directly from `bitnami/valkey:8.1.5-debian-12-r0`
- ✅ All Bitnami environment variables work the same
- ✅ Volume mounts are compatible
- ✅ Same port exposure (6379)
- ✅ Same user (1001)
- ✅ Same directory structure (`/opt/bitnami/valkey`)

### Migration

To migrate from Bitnami Valkey to FIPS-enabled Valkey:

1. **Stop the original container:**
   ```bash
   docker stop valkey
   ```

2. **Backup data:**
   ```bash
   docker cp valkey:/bitnami/valkey/data ./valkey-backup
   ```

3. **Start FIPS container:**
   ```bash
   docker run -d \
     --name valkey-fips \
     -p 6379:6379 \
     -v ./valkey-backup:/bitnami/valkey/data \
     valkey-fips:8.1.5-ubuntu-22.04
   ```

## Troubleshooting

### Container Fails to Start

**Check logs:**
```bash
docker logs valkey-fips
```

**Common issues:**

1. **FIPS validation failed**: Look for specific error in logs
   - Environment variables not set correctly
   - wolfSSL library missing
   - wolfProvider module not found

2. **Permissions issue**: Ensure user 1001 has access to volumes
   ```bash
   chown -R 1001:1001 /path/to/volume
   ```

### FIPS Known Answer Tests Fail

This indicates a cryptographic integrity issue:
- Rebuild the image without cache: `./build.sh --no-cache`
- Verify wolfSSL password is correct
- Check builder logs for compilation errors

### TLS Not Working

**Verify TLS is enabled in Valkey:**
```bash
docker exec valkey-fips valkey-cli CONFIG GET tls-*
```

**Check Valkey is linked with OpenSSL:**
```bash
docker exec valkey-fips ldd /opt/bitnami/valkey/bin/valkey-server | grep ssl
```

### Performance Issues

FIPS-validated cryptography may have slight performance overhead. Monitor:
```bash
docker exec valkey-fips valkey-cli --latency
docker exec valkey-fips valkey-cli INFO stats
```

## Development

### Modifying the Build

To customize the build:

1. **OpenSSL version**: Managed by Ubuntu package (`libssl3`/`libssl-dev`) - version follows Ubuntu 22.04 LTS
2. **Change wolfSSL version**: Edit `WOLFSSL_VERSION` in Dockerfile (ensure FIPS certification)
3. **Change wolfProvider version**: Edit `WOLFPROV_VERSION` in Dockerfile
4. **Change Valkey version**: Edit `VALKEY_VERSION` in Dockerfile
5. **Add custom patches**: Add RUN commands in builder stage

**Note on OpenSSL**: This image uses Ubuntu's system OpenSSL package to:
- Avoid conflicts with `apt upgrade`
- Maintain consistency with Ubuntu package database
- Simplify dependency management
- Allow Ubuntu to manage OpenSSL security updates

FIPS compliance comes from wolfProvider + wolfSSL, not from OpenSSL itself.

### Testing Changes

After modifications:
```bash
./build.sh --no-cache
./test-valkey-fips.sh
```

Or run comprehensive test suite:
```bash
./tests/quick-test.sh
./tests/crypto-path-validation-valkey.sh
./tests/test-fips-sha256.sh
```

## Security Considerations

1. **FIPS Compliance**: This image is designed for FIPS 140-3 compliant environments
2. **Secrets Management**: Use Docker secrets or environment variables for passwords
3. **Network Security**: Always use TLS for production deployments
4. **Updates**: Regularly rebuild with latest security patches
5. **Validation**: Always run the test suite after building

## References

- [Valkey Documentation](https://valkey.io/)
- [wolfSSL FIPS](https://www.wolfssl.com/products/wolfssl-fips/)
- [OpenSSL 3 Providers](https://www.openssl.org/docs/man3.0/man7/provider.html)
- [FIPS 140-3 Standard](https://csrc.nist.gov/publications/detail/fips/140/3/final)
- [Bitnami Valkey](https://github.com/bitnami/containers/tree/main/bitnami/valkey)

## License

This implementation follows the licenses of its components:
- Valkey: BSD 3-Clause License
- OpenSSL: Apache License 2.0
- wolfSSL: Commercial License (FIPS version)
- Bitnami Scripts: Apache License 2.0

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review container logs
3. Run the test suite with verbose output
4. Verify FIPS validation steps

## Acknowledgments

- **Bitnami** for the excellent Valkey container and scripts
- **wolfSSL** for FIPS 140-3 validated cryptography
- **Valkey** project for the Redis-compatible key-value store
- **OpenSSL** project for the cryptographic framework
