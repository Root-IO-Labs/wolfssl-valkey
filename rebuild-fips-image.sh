#!/bin/bash
################################################################################
# Rebuild Valkey FIPS Image Script
#
# This script rebuilds the Valkey FIPS-enabled Docker image from scratch.
#
# Usage:
#   ./rebuild-fips-image.sh [--no-cache]
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "Valkey FIPS Image Rebuild Script"
echo "========================================"
echo ""

# Check for wolfssl_password.txt
if [ ! -f "wolfssl_password.txt" ]; then
    echo "❌ ERROR: wolfssl_password.txt not found"
    echo ""
    echo "Please create wolfssl_password.txt with your wolfSSL FIPS download password:"
    echo "  echo 'your_password_here' > wolfssl_password.txt"
    echo "  chmod 600 wolfssl_password.txt"
    exit 1
fi

echo "✓ wolfSSL password file found"
echo ""

# Determine build options
BUILD_OPTS=""
if [ "$1" == "--no-cache" ]; then
    echo "Building with --no-cache (full rebuild)"
    BUILD_OPTS="--no-cache"
else
    echo "Building with cache (use --no-cache for full rebuild)"
fi
echo ""

# Build the image
echo "Starting Docker build..."
echo "This will take 15-20 minutes depending on your system."
echo ""

export DOCKER_BUILDKIT=1

docker buildx build \
    $BUILD_OPTS \
    --secret id=wolfssl_password,src=wolfssl_password.txt \
    --tag valkey-fips:8.1.5-ubuntu-22.04 \
    --file Dockerfile \
    .

BUILD_EXIT_CODE=$?

echo ""
if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo "========================================"
    echo "✓ Build Successful!"
    echo "========================================"
    echo ""
    echo "Image: valkey-fips:8.1.5-ubuntu-22.04"
    echo ""
    echo "Next steps:"
    echo "  1. Test the image:"
    echo "     ./tests/quick-test.sh"
    echo ""
    echo "  2. Run crypto path validation:"
    echo "     ./tests/crypto-path-validation-valkey.sh"
    echo ""
    echo "  3. Start with Docker Compose:"
    echo "     docker-compose up -d"
    echo ""
else
    echo "========================================"
    echo "✗ Build Failed"
    echo "========================================"
    echo ""
    echo "Check the error messages above"
    exit 1
fi
