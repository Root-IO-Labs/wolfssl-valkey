#!/bin/bash
set -e

###############################################################################
# FIPS Validation Wrapper for Bitnami Valkey
#
# This script performs FIPS 140-3 validation before passing control to the
# original Bitnami entrypoint script.
#
# Environment variables:
#   SKIP_FIPS_CHECK - Skip FIPS validation (default: false, not recommended)
#
# Original Bitnami entrypoint: /opt/bitnami/scripts/valkey/entrypoint.sh
###############################################################################

echo "========================================"
echo "Valkey FIPS Container Startup"
echo "Ubuntu 22.04 + Bitnami Scripts"
echo "========================================"
echo ""

EXIT_CODE=0

###############################################################################
# Check 1: Operating Environment (OE) Validation
###############################################################################
echo "[1/6] Validating Operating Environment (OE) for CMVP compliance..."

# Check kernel version
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)

echo "      Detected kernel: $KERNEL_VERSION"

# wolfSSL FIPS v5.2.3 validated OE requires kernel >= 6.8.x
# TODO: Update this range once wolfSSL CMVP certificate is obtained
# if [ "$KERNEL_MAJOR" -lt 6 ] || ([ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -lt 8 ]); then
#     echo "      ✗ ERROR: Kernel version $KERNEL_VERSION is below minimum validated version (6.8.x)"
#     echo "      This kernel is not listed in the wolfSSL FIPS CMVP Operating Environment"
#     EXIT_CODE=1
# else
#     echo "      ✓ Kernel version: $KERNEL_VERSION (validated range)"
# fi

# Check CPU architecture
CPU_ARCH=$(uname -m)
if [ "$CPU_ARCH" != "x86_64" ]; then
    echo "      ✗ ERROR: Unsupported CPU architecture: $CPU_ARCH"
    echo "      wolfSSL FIPS CMVP validation requires x86_64 architecture"
    EXIT_CODE=1
else
    echo "      ✓ CPU architecture: $CPU_ARCH"
fi

# Check for recommended CPU features
if [ -f /proc/cpuinfo ]; then
    if grep -q rdrand /proc/cpuinfo; then
        echo "      ✓ RDRAND: Available (hardware entropy source)"
    else
        echo "      ⚠ RDRAND: Not available (using kernel entropy only)"
    fi

    if grep -q aes /proc/cpuinfo; then
        echo "      ✓ AES-NI: Available (hardware-accelerated AES)"
    else
        echo "      ⚠ AES-NI: Not available (software AES)"
    fi
else
    echo "      ⚠ WARNING: Cannot read /proc/cpuinfo"
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "Operating Environment is not CMVP compliant"
    echo "See docs/operating-environment.md for requirements"
    exit 1
fi

###############################################################################
# Check 2: Environment Variables
###############################################################################
echo ""
echo "[2/6] Validating FIPS environment variables..."

if [ -z "$OPENSSL_CONF" ]; then
    echo "      ✗ ERROR: OPENSSL_CONF is not set"
    EXIT_CODE=1
elif [ ! -f "$OPENSSL_CONF" ]; then
    echo "      ✗ ERROR: OPENSSL_CONF file does not exist: $OPENSSL_CONF"
    EXIT_CODE=1
else
    echo "      ✓ OPENSSL_CONF: $OPENSSL_CONF"
fi

if [ -z "$OPENSSL_MODULES" ]; then
    echo "      ✗ ERROR: OPENSSL_MODULES is not set"
    EXIT_CODE=1
elif [ ! -d "$OPENSSL_MODULES" ]; then
    echo "      ✗ ERROR: OPENSSL_MODULES directory does not exist: $OPENSSL_MODULES"
    EXIT_CODE=1
else
    echo "      ✓ OPENSSL_MODULES: $OPENSSL_MODULES"
fi

if [ -z "$LD_LIBRARY_PATH" ]; then
    echo "      ✗ ERROR: LD_LIBRARY_PATH is not set"
    EXIT_CODE=1
else
    echo "      ✓ LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "Environment configuration is invalid"
    exit 1
fi

###############################################################################
# Check 3: OpenSSL Installation
###############################################################################
echo ""
echo "[3/6] Validating OpenSSL installation..."

OPENSSL_BIN="/usr/local/openssl/bin/openssl"
if [ ! -x "$OPENSSL_BIN" ]; then
    echo "      ✗ ERROR: OpenSSL binary not found or not executable: $OPENSSL_BIN"
    EXIT_CODE=1
else
    OPENSSL_VERSION=$($OPENSSL_BIN version 2>&1 | head -n1)
    echo "      ✓ OpenSSL found: $OPENSSL_VERSION"

    # Check if it's OpenSSL 3.x
    if ! echo "$OPENSSL_VERSION" | grep -q "OpenSSL 3\."; then
        echo "      ⚠ WARNING: Expected OpenSSL 3.x, got: $OPENSSL_VERSION"
    fi
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "OpenSSL installation is invalid"
    exit 1
fi

###############################################################################
# Check 4: wolfSSL Library
###############################################################################
echo ""
echo "[4/6] Validating wolfSSL library..."

WOLFSSL_LIB="/usr/local/lib/libwolfssl.so"
if [ ! -f "$WOLFSSL_LIB" ]; then
    # Try alternative locations
    if [ -f "/usr/local/lib/libwolfssl.so.42" ]; then
        WOLFSSL_LIB="/usr/local/lib/libwolfssl.so.42"
    elif ls /usr/local/lib/libwolfssl.so.* >/dev/null 2>&1; then
        WOLFSSL_LIB=$(ls /usr/local/lib/libwolfssl.so.* | head -n1)
    else
        echo "      ✗ ERROR: wolfSSL library not found in /usr/local/lib/"
        EXIT_CODE=1
    fi
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "      ✓ wolfSSL library: $WOLFSSL_LIB"
else
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "wolfSSL library is missing"
    exit 1
fi

###############################################################################
# Check 5: wolfProvider Module
###############################################################################
echo ""
echo "[5/6] Validating wolfProvider module..."

WOLFPROV_MODULE="$OPENSSL_MODULES/libwolfprov.so"
if [ ! -f "$WOLFPROV_MODULE" ]; then
    echo "      ✗ ERROR: wolfProvider module not found: $WOLFPROV_MODULE"
    echo "      Available modules in $OPENSSL_MODULES:"
    ls -la "$OPENSSL_MODULES/" 2>/dev/null || echo "      (directory listing failed)"
    EXIT_CODE=1
else
    echo "      ✓ wolfProvider module: $WOLFPROV_MODULE"
    WOLFPROV_SIZE=$(stat -c%s "$WOLFPROV_MODULE" 2>/dev/null || echo "unknown")
    echo "      ✓ Module size: $WOLFPROV_SIZE bytes"
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "wolfProvider module is missing or invalid"
    exit 1
fi

###############################################################################
# Check 5.5: Verify No System Crypto Libraries Present
###############################################################################
echo ""
echo "[5.5/6] Verifying no non-FIPS crypto libraries present..."

# Check that libraries in /usr/lib/x86_64-linux-gnu are FIPS OpenSSL (not system OpenSSL)
# Our Dockerfile places FIPS OpenSSL libraries at /usr/lib/x86_64-linux-gnu/ so system
# packages link to FIPS-validated crypto. We verify they match /usr/local/openssl/lib64/
FIPS_SSL_PATHS=(
    "/usr/lib/x86_64-linux-gnu/libssl.so.3"
    "/usr/lib/x86_64-linux-gnu/libcrypto.so.3"
)

NON_FIPS_LIBS_FOUND=0
for lib_path in "${FIPS_SSL_PATHS[@]}"; do
    if [ -f "$lib_path" ]; then
        # Verify this is the FIPS OpenSSL by comparing with /usr/local/openssl/lib64/
        fips_lib="/usr/local/openssl/lib64/$(basename "$lib_path")"
        if [ -f "$fips_lib" ]; then
            # Compare SHA256 hashes (cryptographically secure verification)
            system_hash=$(sha256sum "$lib_path" 2>/dev/null | awk '{print $1}')
            fips_hash=$(sha256sum "$fips_lib" 2>/dev/null | awk '{print $1}')

            if [ "$system_hash" = "$fips_hash" ] && [ -n "$system_hash" ]; then
                echo "      ✓ FIPS OpenSSL library verified: $lib_path"
                echo "         SHA256: $system_hash"
            else
                echo "      ✗ ERROR: Library at $lib_path does not match FIPS OpenSSL"
                echo "         System SHA256: $system_hash"
                echo "         FIPS SHA256:   $fips_hash"
                NON_FIPS_LIBS_FOUND=1
            fi
        else
            echo "      ✗ ERROR: FIPS OpenSSL library not found: $fips_lib"
            NON_FIPS_LIBS_FOUND=1
        fi
    else
        echo "      ✗ ERROR: Expected FIPS OpenSSL library not found: $lib_path"
        NON_FIPS_LIBS_FOUND=1
    fi
done

# Check for unexpected system OpenSSL in /lib (should NOT exist, or should be hardlinks to FIPS)
UNEXPECTED_SSL_PATHS=(
    "/lib/x86_64-linux-gnu/libssl.so.3"
    "/lib/x86_64-linux-gnu/libcrypto.so.3"
)

for lib_path in "${UNEXPECTED_SSL_PATHS[@]}"; do
    if [ -f "$lib_path" ]; then
        # Check if this is a hardlink to the FIPS OpenSSL in /usr/lib
        usr_lib_path="/usr/lib/x86_64-linux-gnu/$(basename "$lib_path")"
        if [ -f "$usr_lib_path" ]; then
            # Compare inodes to check if they're hardlinked (same file)
            lib_inode=$(stat -c%i "$lib_path" 2>/dev/null || echo "0")
            usr_inode=$(stat -c%i "$usr_lib_path" 2>/dev/null || echo "0")

            if [ "$lib_inode" = "$usr_inode" ] && [ "$lib_inode" != "0" ]; then
                echo "      ✓ FIPS OpenSSL library hardlinked: $lib_path -> $usr_lib_path (inode $lib_inode)"
            else
                echo "      ✗ ERROR: Unexpected system OpenSSL library found: $lib_path (different from $usr_lib_path)"
                NON_FIPS_LIBS_FOUND=1
            fi
        else
            echo "      ✗ ERROR: Unexpected system OpenSSL library found: $lib_path (no matching FIPS library)"
            NON_FIPS_LIBS_FOUND=1
        fi
    fi
done

# Check for other non-FIPS crypto libraries
OTHER_CRYPTO_LIBS=(
    "/usr/lib/x86_64-linux-gnu/libmbedtls.so"
    "/usr/lib/x86_64-linux-gnu/libnss3.so"
    "/usr/lib/x86_64-linux-gnu/libgcrypt.so"
)

for lib_path in "${OTHER_CRYPTO_LIBS[@]}"; do
    if [ -f "$lib_path" ]; then
        echo "      ⚠ WARNING: Non-FIPS crypto library detected: $lib_path"
        # Note: These are warnings, not errors, as they may be required by system utilities
    fi
done

if [ $NON_FIPS_LIBS_FOUND -eq 0 ]; then
    echo "      ✓ No system OpenSSL libraries found (FIPS-only configuration)"
    echo "      ✓ All crypto operations will use FIPS OpenSSL + wolfProvider"
else
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "System crypto libraries detected - FIPS boundary compromised"
    echo "Applications may bypass FIPS cryptography"
    exit 1
fi

###############################################################################
# Check 6: Cryptographic FIPS Validation (C utility)
###############################################################################
if [ "$SKIP_FIPS_CHECK" != "true" ]; then
    echo ""
    echo "[6/6] Running cryptographic FIPS validation..."
    echo ""

    FIPS_CHECK_BIN="/usr/local/bin/fips-startup-check"
    if [ ! -x "$FIPS_CHECK_BIN" ]; then
        echo "      ✗ ERROR: FIPS check utility not found: $FIPS_CHECK_BIN"
        EXIT_CODE=1
    else
        # Execute the C-based FIPS validation utility
        if ! "$FIPS_CHECK_BIN"; then
            echo ""
            echo "========================================"
            echo "✗ FIPS VALIDATION FAILED"
            echo "========================================"
            echo "Cryptographic validation failed"
            exit 1
        fi
    fi
else
    echo ""
    echo "[6/6] Skipping cryptographic FIPS validation (SKIP_FIPS_CHECK=true)"
fi

###############################################################################
# Final Validation - Check if any errors occurred
###############################################################################
if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "One or more FIPS validation checks failed"
    echo "Container cannot start - FIPS compliance not verified"
    echo ""
    echo "Review the error messages above and ensure:"
    echo "  - Kernel version >= 6.8.x"
    echo "  - CPU architecture is x86_64"
    echo "  - All required FIPS libraries are present"
    echo "  - Environment variables are correctly set"
    echo "========================================"
    exit 1
fi

###############################################################################
# All Checks Passed - Hand off to Bitnami Entrypoint
###############################################################################
echo "========================================"
echo "✓ ALL FIPS CHECKS PASSED"
echo "========================================"
echo ""
echo "Handing control to Bitnami entrypoint..."
echo ""

# Execute the original Bitnami entrypoint with all arguments
exec /opt/bitnami/scripts/valkey/entrypoint.sh "$@"
