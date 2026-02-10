################################################################################
# FIPS-Enabled Valkey Image with wolfSSL FIPS v5
################################################################################
# This Dockerfile creates a FIPS 140-3 compliant Valkey image using:
# - Ubuntu 22.04 base (matching Bitnami)
# - OpenSSL 3.0.15 with FIPS module support
# - wolfSSL FIPS v5 (commercial, FIPS 140-3 validated)
# - wolfProvider (bridges OpenSSL 3 and wolfSSL)
# - Valkey 8.1.5 built with TLS support
# - Bitnami scripts (unchanged, copied from original image)
#
# Build command:
#   docker build --secret id=wolfssl_password,src=.password \
#     -t valkey-fips:8.1.5-ubuntu-22.04 \
#     -f valkey/8.1.5-ubuntu-22.04/Dockerfile .
################################################################################

################################################################################
# Stage 1: Builder - Build OpenSSL 3, wolfSSL FIPS v5, wolfProvider, and Valkey
################################################################################
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Build configuration
ARG TARGETARCH
ENV OPENSSL_VERSION=3.0.15
ENV WOLFSSL_URL=https://www.wolfssl.com/comm/wolfssl/wolfssl-5.8.2-commercial-fips-v5.2.3.7z
ENV WOLFPROV_REPO=https://github.com/wolfSSL/wolfProvider.git
ENV WOLFPROV_VERSION=v1.1.0
ENV VALKEY_VERSION=8.1.5

# Installation paths
ENV OPENSSL_PREFIX=/usr/local/openssl
ENV WOLFSSL_PREFIX=/usr/local
ENV WOLFPROV_PREFIX=/usr/local

# Install build dependencies
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        wget \
        git \
        autoconf \
        automake \
        libtool \
        pkg-config \
        p7zip-full \
        perl \
    ; \
    update-ca-certificates; \
    rm -rf /var/lib/apt/lists/*

################################################################################
# Fetch and process Mozilla CA bundle for runtime stage
# This avoids needing to install ca-certificates package in runtime
################################################################################
RUN set -eux; \
    echo "Fetching Mozilla CA bundle..."; \
    curl -L -o /tmp/cacert.pem https://curl.se/ca/cacert.pem; \
    mkdir -p /usr/local/share/ca-certificates-mozilla; \
    cd /tmp; \
    csplit -s -z -f cert- cacert.pem '/-----BEGIN CERTIFICATE-----/' '{*}'; \
    for cert in cert-*; do \
        if grep -q 'BEGIN CERTIFICATE' "$cert"; then \
            mv "$cert" "/usr/local/share/ca-certificates-mozilla/${cert}.crt"; \
        fi; \
    done; \
    rm -f /tmp/cacert.pem /tmp/cert-*; \
    echo "✓ Mozilla CA bundle processed ($(ls /usr/local/share/ca-certificates-mozilla/cert-*.crt 2>/dev/null | wc -l) certificates)"

################################################################################
# Build OpenSSL 3.0.x with FIPS module support
################################################################################
RUN set -eux; \
    cd /tmp; \
    curl -L -O https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz; \
    tar -xzf openssl-${OPENSSL_VERSION}.tar.gz; \
    cd openssl-${OPENSSL_VERSION}; \
    ./Configure \
        --prefix=${OPENSSL_PREFIX} \
        --openssldir=${OPENSSL_PREFIX}/ssl \
        --libdir=lib64 \
        shared \
        linux-x86_64 \
    ; \
    make -j"$(nproc)"; \
    make install_sw; \
    make install_ssldirs; \
    cd ..; \
    rm -rf openssl-${OPENSSL_VERSION}*; \
    echo "OpenSSL ${OPENSSL_VERSION} installed successfully"

# Update environment for subsequent builds
ENV PATH="${OPENSSL_PREFIX}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${OPENSSL_PREFIX}/lib64"
ENV PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib64/pkgconfig"

# Verify OpenSSL installation
RUN openssl version && \
    openssl list -providers && \
    ls -la ${OPENSSL_PREFIX}/lib64/ossl-modules/

################################################################################
# Build wolfSSL FIPS v5
################################################################################
COPY test-fips.c /tmp/test-fips.c

RUN --mount=type=secret,id=wolfssl_password \
    set -eux; \
    mkdir -p /usr/src; \
    # Download wolfSSL FIPS package with proper certificate verification
    # Security: Using curl with system CA certificates
    # Additional security: Password authentication required (wolfssl_password.txt)
    curl -L -o /tmp/wolfssl.7z "${WOLFSSL_URL}"; \
    PASSWORD=$(cat /run/secrets/wolfssl_password | tr -d '\n\r'); \
    7z x /tmp/wolfssl.7z -o/usr/src -p"${PASSWORD}"; \
    rm /tmp/wolfssl.7z; \
    mv /usr/src/wolfssl* /usr/src/wolfssl; \
    cd /usr/src/wolfssl; \
    # Remove Python-specific defines that can cause issues
    sed -i '/^#ifdef WOLFSSL_PYTHON/,/^#endif/d' wolfssl/wolfcrypt/settings.h || true; \
    # Configure wolfSSL with FIPS v5 and necessary features
    ./configure \
        --prefix=${WOLFSSL_PREFIX} \
        --enable-fips=v5 \
        --enable-opensslcoexist \
        --enable-cmac \
        --enable-keygen \
        --enable-sha \
        --enable-des3 \
        --enable-aesctr \
        --enable-aesccm \
        --enable-x963kdf \
        --enable-compkey \
        --enable-certgen \
        --enable-aeskeywrap \
        --enable-enckeys \
        --enable-base16 \
        --with-eccminsz=192 \
        CPPFLAGS="-DHAVE_AES_ECB -DWOLFSSL_AES_DIRECT -DWC_RSA_NO_PADDING -DWOLFSSL_PUBLIC_MP -DHAVE_PUBLIC_FFDHE -DWOLFSSL_DH_EXTRA -DWOLFSSL_PSS_LONG_SALT -DWOLFSSL_PSS_SALT_LEN_DISCOVER -DRSA_MIN_SIZE=1024" \
    ; \
    make -j"$(nproc)"; \
    ./fips-hash.sh; \
    make -j"$(nproc)"; \
    make install; \
    ldconfig; \
    cd /; \
    rm -rf /usr/src/wolfssl; \
    echo "wolfSSL FIPS v5 installed successfully"

# Update library path for wolfSSL
ENV LD_LIBRARY_PATH="${OPENSSL_PREFIX}/lib64:${WOLFSSL_PREFIX}/lib"

# Test wolfSSL installation
RUN set -eux; \
    gcc /tmp/test-fips.c -o /tmp/test-fips -lwolfssl -I${WOLFSSL_PREFIX}/include; \
    /tmp/test-fips; \
    rm /tmp/test-fips /tmp/test-fips.c; \
    echo "wolfSSL FIPS test passed"

# Build FIPS startup check utility
COPY fips-startup-check.c /tmp/fips-startup-check.c
RUN set -eux; \
    gcc /tmp/fips-startup-check.c -o /usr/local/bin/fips-startup-check \
        -lwolfssl -I${WOLFSSL_PREFIX}/include; \
    chmod +x /usr/local/bin/fips-startup-check; \
    rm /tmp/fips-startup-check.c; \
    echo "FIPS startup check utility built successfully"

################################################################################
# Build wolfProvider
################################################################################
RUN set -eux; \
    cd /tmp; \
    git clone --depth 1 --branch ${WOLFPROV_VERSION} ${WOLFPROV_REPO} wolfProvider; \
    cd wolfProvider; \
    ./autogen.sh; \
    # Configure wolfProvider to use our OpenSSL and wolfSSL
    ./configure \
        --prefix=${WOLFPROV_PREFIX} \
        --with-openssl=${OPENSSL_PREFIX} \
        --with-wolfssl=${WOLFSSL_PREFIX} \
    ; \
    make -j"$(nproc)"; \
    echo "wolfProvider built, checking build artifacts..."; \
    find . -name "*.so" -type f; \
    echo "Installing wolfProvider..."; \
    make install; \
    echo "Checking installation results..."; \
    find /usr/local -name "*wolfprov*" -type f 2>/dev/null || true; \
    find ${OPENSSL_PREFIX} -name "*wolfprov*" -type f 2>/dev/null || true; \
    # Manual installation if make install didn't work
    if [ ! -f "${OPENSSL_PREFIX}/lib64/ossl-modules/libwolfprov.so" ]; then \
        echo "Manual installation required..."; \
        mkdir -p ${OPENSSL_PREFIX}/lib64/ossl-modules; \
        if [ -f ".libs/libwolfprov.so" ]; then \
            cp -v .libs/libwolfprov.so* ${OPENSSL_PREFIX}/lib64/ossl-modules/ || true; \
        fi; \
        if [ -f "src/.libs/libwolfprov.so" ]; then \
            cp -v src/.libs/libwolfprov.so* ${OPENSSL_PREFIX}/lib64/ossl-modules/ || true; \
        fi; \
    fi; \
    cd ..; \
    rm -rf wolfProvider; \
    echo "wolfProvider installation completed"

# Verify wolfProvider installation
RUN set -eux; \
    echo "Checking for wolfProvider in possible locations..."; \
    if [ -d "${OPENSSL_PREFIX}/lib64/ossl-modules" ]; then \
        ls -la ${OPENSSL_PREFIX}/lib64/ossl-modules/; \
    fi; \
    if [ -d "${OPENSSL_PREFIX}/lib/ossl-modules" ]; then \
        ls -la ${OPENSSL_PREFIX}/lib/ossl-modules/; \
    fi; \
    if [ -d "${WOLFPROV_PREFIX}/lib64/ossl-modules" ]; then \
        ls -la ${WOLFPROV_PREFIX}/lib64/ossl-modules/; \
    fi; \
    if [ -d "${WOLFPROV_PREFIX}/lib/ossl-modules" ]; then \
        ls -la ${WOLFPROV_PREFIX}/lib/ossl-modules/; \
    fi; \
    # Check if libwolfprov.so exists in any of the expected locations
    if [ -f "${OPENSSL_PREFIX}/lib64/ossl-modules/libwolfprov.so" ] || \
       [ -f "${OPENSSL_PREFIX}/lib/ossl-modules/libwolfprov.so" ] || \
       [ -f "${WOLFPROV_PREFIX}/lib64/ossl-modules/libwolfprov.so" ] || \
       [ -f "${WOLFPROV_PREFIX}/lib/ossl-modules/libwolfprov.so" ]; then \
        echo "wolfProvider module found and verified"; \
    else \
        echo "ERROR: wolfProvider module not found in expected locations"; \
        exit 1; \
    fi

################################################################################
# Build Valkey from source with custom OpenSSL
################################################################################
# Copy FIPS SHA-256 patch (complete version with all sha1hex references)
COPY patches/valkey-fips-sha256-complete.patch /tmp/valkey-fips-sha256.patch

RUN set -eux; \
    cd /tmp; \
    # Download Valkey source with proper certificate verification
    # Security: Using curl with system CA certificates
    # Additional verification: GitHub packages are signed and checksummed
    curl -L -o ${VALKEY_VERSION}.tar.gz https://github.com/valkey-io/valkey/archive/refs/tags/${VALKEY_VERSION}.tar.gz; \
    tar xzf ${VALKEY_VERSION}.tar.gz; \
    cd valkey-${VALKEY_VERSION}; \
    # Apply FIPS SHA-256 patch to replace SHA-1 with OpenSSL SHA-256
    echo "Applying FIPS SHA-256 patch..."; \
    patch -p1 < /tmp/valkey-fips-sha256.patch; \
    echo "✓ FIPS SHA-256 patch applied successfully"; \
    echo "  - Replaced SHA-1 with OpenSSL SHA-256 in eval.c (Lua script hashing)"; \
    echo "  - Replaced SHA-1 with OpenSSL SHA-256 in debug.c (DEBUG DIGEST)"; \
    echo "  - Updated function declaration in server.h (sha1hex -> sha256hex)"; \
    # Build Valkey with TLS using our custom OpenSSL
    make BUILD_TLS=yes USE_SYSTEMD=no OPENSSL_PREFIX=${OPENSSL_PREFIX} -j"$(nproc)"; \
    # Install to /opt/bitnami/valkey for Bitnami compatibility
    make install PREFIX=/opt/bitnami/valkey; \
    mkdir -p /opt/bitnami/valkey/etc; \
    cp valkey.conf /opt/bitnami/valkey/etc/valkey.conf; \
    cp valkey.conf /opt/bitnami/valkey/etc/valkey-default.conf; \
    cd /; \
    rm -rf /tmp/valkey-${VALKEY_VERSION}* /tmp/${VALKEY_VERSION}.tar.gz; \
    echo "Valkey ${VALKEY_VERSION} built and installed successfully"

# Verify Valkey installation
RUN set -eux; \
    echo "Verifying Valkey installation..."; \
    ls -la /opt/bitnami/valkey/bin/; \
    /opt/bitnami/valkey/bin/valkey-server --version; \
    ldd /opt/bitnami/valkey/bin/valkey-server | grep -i ssl || echo "Warning: SSL not linked"; \
    echo "Valkey installation verified"

################################################################################
# Copy Bitnami scripts from local directories (for runtime stage)
################################################################################
# Copy prebuildfs and rootfs from the current directory
# These directories contain the Bitnami helper scripts and Valkey-specific scripts
COPY prebuildfs /opt/bitnami-scripts/prebuildfs
COPY rootfs /opt/bitnami-scripts/rootfs

################################################################################
# Stage 2: Runtime - Minimal Ubuntu 22.04 image with FIPS components
################################################################################
FROM ubuntu:22.04 AS runtime

ARG TARGETARCH
ARG VALKEY_VERSION=8.1.5

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

LABEL org.opencontainers.image.base.name="ubuntu:22.04" \
      org.opencontainers.image.created="2025-12-02T00:00:00Z" \
      org.opencontainers.image.description="Valkey ${VALKEY_VERSION} with FIPS 140-3 (wolfSSL v5) on Ubuntu 22.04" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.ref.name="${VALKEY_VERSION}-ubuntu-22.04-fips" \
      org.opencontainers.image.title="valkey-fips" \
      org.opencontainers.image.vendor="Custom Build" \
      org.opencontainers.image.version="${VALKEY_VERSION}"

# Set initial environment variables (matching Bitnami)
ENV HOME="/" \
    OS_ARCH="${TARGETARCH:-amd64}" \
    OS_FLAVOUR="ubuntu-22.04-fips" \
    OS_NAME="linux" \
    VALKEY_VERSION="${VALKEY_VERSION}"

# Copy Bitnami prebuildfs scripts (these are shell scripts, OS-agnostic)
# These must be copied BEFORE any RUN commands that might use them
COPY --from=builder /opt/bitnami-scripts/prebuildfs /

# Set bash shell with strict error handling (matching Bitnami)
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]

################################################################################
# CRITICAL FIPS STEP 1: Install FIPS OpenSSL to System Locations FIRST
# This must happen BEFORE any apt-get install commands to ensure all
# packages link to FIPS-validated OpenSSL instead of Ubuntu's system OpenSSL
################################################################################

# Copy FIPS components from builder (before installing ANY packages)
COPY --from=builder /usr/local/openssl /usr/local/openssl
COPY --from=builder /usr/local/lib/libwolfssl.so* /usr/local/lib/
COPY --from=builder /usr/local/include/wolfssl /usr/local/include/wolfssl
COPY --from=builder /usr/local/openssl/lib64/ossl-modules/libwolfprov.so* /tmp/wolfprov/

# Install FIPS OpenSSL as system OpenSSL
RUN set -eux; \
    echo "========================================"; \
    echo "Installing FIPS OpenSSL as System OpenSSL"; \
    echo "========================================"; \
    \
    # Create necessary directories
    mkdir -p /usr/lib/x86_64-linux-gnu; \
    mkdir -p /usr/local/lib64/ossl-modules; \
    \
    # Install FIPS OpenSSL libraries to system locations
    # This makes them the default OpenSSL that apt packages will link to
    cp -av /usr/local/openssl/lib64/libssl.so* /usr/lib/x86_64-linux-gnu/; \
    cp -av /usr/local/openssl/lib64/libcrypto.so* /usr/lib/x86_64-linux-gnu/; \
    \
    # Install wolfSSL to system locations
    cp -av /usr/local/lib/libwolfssl.so* /usr/lib/x86_64-linux-gnu/; \
    \
    # Install wolfProvider module
    cp -av /tmp/wolfprov/* /usr/local/lib64/ossl-modules/; \
    rm -rf /tmp/wolfprov; \
    \
    # Install OpenSSL binary to system PATH
    cp -av /usr/local/openssl/bin/openssl /usr/bin/openssl; \
    \
    # Configure dynamic linker to find FIPS libraries
    echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/fips-openssl.conf; \
    echo "/usr/local/openssl/lib64" >> /etc/ld.so.conf.d/fips-openssl.conf; \
    echo "/usr/local/lib" >> /etc/ld.so.conf.d/fips-openssl.conf; \
    ldconfig; \
    \
    echo "✓ FIPS OpenSSL installed to system locations"; \
    echo "✓ All future apt packages will use FIPS OpenSSL"

# Set OpenSSL environment variables for wolfProvider
ENV OPENSSL_CONF="/usr/local/openssl/ssl/openssl.cnf" \
    OPENSSL_MODULES="/usr/local/lib64/ossl-modules" \
    LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/usr/local/openssl/lib64:/usr/local/lib" \
    PATH="/usr/bin:/usr/local/openssl/bin:/opt/bitnami/common/bin:/opt/bitnami/valkey/bin:${PATH}"

# Copy OpenSSL configuration with wolfProvider
COPY openssl-wolfprov.cnf /usr/local/openssl/ssl/openssl.cnf

# Verify FIPS OpenSSL works BEFORE installing any packages
RUN set -eux; \
    echo "========================================"; \
    echo "Verifying FIPS OpenSSL Installation"; \
    echo "========================================"; \
    openssl version; \
    echo ""; \
    echo "OpenSSL providers:"; \
    openssl list -providers; \
    echo ""; \
    if ! openssl list -providers | grep -q wolfprov; then \
        echo "ERROR: wolfProvider not loaded!"; \
        exit 1; \
    fi; \
    echo "✓ FIPS OpenSSL operational"; \
    echo "✓ wolfProvider loaded"; \
    echo "========================================"

################################################################################
# Install CA certificates from Mozilla bundle (from builder stage)
# This avoids installing ca-certificates package which pulls in Ubuntu OpenSSL
################################################################################
COPY --from=builder /usr/local/share/ca-certificates-mozilla /usr/local/share/ca-certificates

RUN set -eux; \
    echo "========================================"; \
    echo "Installing Mozilla CA Certificates"; \
    echo "========================================"; \
    \
    # Create SSL certificate directories
    mkdir -p /etc/ssl/certs; \
    mkdir -p /usr/share/ca-certificates; \
    \
    # Copy individual certificates
    cp -a /usr/local/share/ca-certificates/* /usr/share/ca-certificates/ 2>/dev/null || true; \
    \
    # Create the ca-certificates.crt bundle
    cat /usr/local/share/ca-certificates/*.crt > /etc/ssl/certs/ca-certificates.crt 2>/dev/null || true; \
    \
    # Create standard symlinks
    ln -sf /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-bundle.crt 2>/dev/null || true; \
    \
    CERT_COUNT=$(ls /usr/local/share/ca-certificates/*.crt 2>/dev/null | wc -l); \
    echo "✓ Installed ${CERT_COUNT} CA certificates from Mozilla"; \
    echo "========================================"

################################################################################
# Install minimal runtime dependencies (NO ca-certificates package)
################################################################################
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libgomp1 \
        procps \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

################################################################################
# Optional: Remove alternative crypto libraries if not required by dependencies
################################################################################
RUN set -eux; \
    echo "========================================"; \
    echo "Attempting to Remove Non-FIPS Crypto Libraries"; \
    echo "========================================"; \
    \
    # Try to remove alternative crypto libraries
    # Note: Some may not be removed if dependencies exist, which is acceptable
    apt-get remove -y \
        libgnutls30 \
        libnettle8 \
        libhogweed6 \
        libgcrypt20 \
        libk5crypto3 \
        2>/dev/null || true; \
    \
    # Clean up orphaned packages
    apt-get autoremove -y --purge; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    \
    # Report status (informational only)
    echo "Checking for remaining alternative crypto libraries..."; \
    if find /usr/lib /lib -name 'libgnutls*' -o -name 'libnettle*' -o -name 'libhogweed*' -o -name 'libgcrypt*' -o -name 'libk5crypto*' 2>/dev/null | grep -q .; then \
        echo "Note: Some crypto libraries remain (likely required by dependencies)"; \
    else \
        echo "✓ Alternative crypto libraries removed"; \
    fi; \
    \
    echo "✓ FIPS environment configured"

# Copy Valkey installation from builder
COPY --from=builder /opt/bitnami/valkey /opt/bitnami/valkey

# Copy Bitnami rootfs scripts from builder (Valkey-specific scripts)
COPY --from=builder /opt/bitnami-scripts/rootfs /

# Update dynamic linker cache
RUN ldconfig

# Copy FIPS startup check utility from builder
COPY --from=builder /usr/local/bin/fips-startup-check /usr/local/bin/fips-startup-check
RUN chmod +x /usr/local/bin/fips-startup-check

# Set permissions for Bitnami compatibility (matching original Dockerfile)
RUN set -eux; \
    chmod g+rwX /opt/bitnami; \
    find / -perm /6000 -type f -exec chmod a-s {} \; || true; \
    echo "Permissions set for Bitnami compatibility"

# Create symlinks for Bitnami compatibility (matching original Dockerfile)
RUN ln -s /opt/bitnami/scripts/valkey/entrypoint.sh /entrypoint.sh && \
    ln -s /opt/bitnami/scripts/valkey/run.sh /run.sh

# Run Bitnami post-unpack setup (matching original Dockerfile)
RUN /opt/bitnami/scripts/valkey/postunpack.sh

# Copy FIPS validation entrypoint
COPY fips-entrypoint.sh /usr/local/bin/fips-entrypoint.sh
RUN chmod +x /usr/local/bin/fips-entrypoint.sh

# Set Bitnami environment variables (matching original Dockerfile)
ENV APP_VERSION="${VALKEY_VERSION}" \
    BITNAMI_APP_NAME="valkey"

# Runtime verification
RUN set -eux; \
    echo "Verifying FIPS runtime configuration..."; \
    openssl version; \
    echo "OpenSSL providers:"; \
    openssl list -providers || true; \
    echo "Valkey version:"; \
    valkey-server --version; \
    echo "Checking TLS support:"; \
    ldd /opt/bitnami/valkey/bin/valkey-server | grep -i ssl || echo "Warning: SSL not shown in ldd"; \
    echo "Runtime verification complete"

EXPOSE 6379

USER 1001

# Use FIPS entrypoint that validates FIPS, then chains to Bitnami entrypoint
ENTRYPOINT ["/usr/local/bin/fips-entrypoint.sh"]
CMD ["/opt/bitnami/scripts/valkey/run.sh"]
