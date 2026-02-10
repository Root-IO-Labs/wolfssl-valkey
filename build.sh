#!/bin/bash
###############################################################################
# Build Script for FIPS-Enabled Valkey Docker Image
#
# This script builds the FIPS 140-3 compliant Valkey container using:
# - Ubuntu 22.04 base
# - OpenSSL 3.0.15 with FIPS module
# - wolfSSL FIPS v5 (commercial)
# - wolfProvider
# - Valkey 8.1.5 with TLS support
#
# Requirements:
#   - Docker with BuildKit support
#   - wolfssl_password.txt file with wolfSSL commercial archive password
#   - Internet connection for downloading sources
#
# Usage:
#   ./build.sh [options]
#
# Options:
#   --no-cache    Build without cache
#   --help        Show this help message
###############################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="valkey-fips"
IMAGE_TAG="8.1.5-ubuntu-22.04"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
DOCKERFILE="Dockerfile"
PASSWORD_FILE="wolfssl_password.txt"
BUILD_CONTEXT="."

# Parse command line arguments
NO_CACHE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --no-cache    Build without cache"
            echo "  --help        Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "FIPS Valkey Docker Image Build"
echo "========================================"
echo ""

###############################################################################
# Pre-build checks
###############################################################################
echo -e "${BLUE}[CHECK]${NC} Performing pre-build checks..."

# Check if running from correct directory
if [ ! -f "$DOCKERFILE" ]; then
    echo -e "${RED}[ERROR]${NC} Dockerfile not found: $DOCKERFILE"
    echo "Please run this script from the root of the node-fips directory"
    exit 1
fi

# Check for password file
if [ ! -f "$PASSWORD_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} Password file not found: $PASSWORD_FILE"
    echo "Please create a $PASSWORD_FILE file with the wolfSSL commercial archive password"
    exit 1
fi

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Docker is not installed or not in PATH"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Docker found: $(docker --version)"

# Check Docker BuildKit support
if ! docker buildx version >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Docker BuildKit is not available"
    echo "This build requires BuildKit for secure secret handling (--secret flag)"
    echo "Please install/enable Docker BuildKit or use Docker 18.09+"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Docker BuildKit available"



echo ""
echo "========================================"
echo "Build Configuration"
echo "========================================"
echo "Image Name:    $FULL_IMAGE_NAME"
echo "Dockerfile:    $DOCKERFILE"
echo "Build Context: $BUILD_CONTEXT"
echo "Cache:         $([ -z "$NO_CACHE" ] && echo "Enabled" || echo "Disabled")"
echo "========================================"
echo ""

# Confirm build
read -p "Continue with build? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
    echo "Build cancelled"
    exit 0
fi

###############################################################################
# Build the image
###############################################################################
echo ""
echo -e "${BLUE}[BUILD]${NC} Starting Docker build..."
echo ""

BUILD_START=$(date +%s)

# Build command
DOCKER_BUILDKIT=1 docker build \
    --secret id=wolfssl_password,src="$PASSWORD_FILE" \
    -t "$FULL_IMAGE_NAME" \
    -f "$DOCKERFILE" \
    $NO_CACHE \
    "$BUILD_CONTEXT"

BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

echo ""
echo "========================================"
echo -e "${GREEN}✓ BUILD SUCCESSFUL${NC}"
echo "========================================"
echo "Image:      $FULL_IMAGE_NAME"
echo "Build time: ${BUILD_TIME}s"
echo ""

###############################################################################
# Display image information
###############################################################################
echo -e "${BLUE}[INFO]${NC} Image information:"
docker image inspect "$FULL_IMAGE_NAME" --format='{{.Size}}' | \
    awk '{printf "Size:       %.2f MB\n", $1/1024/1024}'
docker image inspect "$FULL_IMAGE_NAME" --format='Created:    {{.Created}}'
echo ""

###############################################################################
# Verify image
###############################################################################
echo -e "${BLUE}[VERIFY]${NC} Quick verification..."

# Test if image can start
echo "Testing container startup..."
TEST_CONTAINER="valkey-fips-build-test-$$"

if docker run --rm --name "$TEST_CONTAINER" "$FULL_IMAGE_NAME" valkey-server --version >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Container can start and Valkey is accessible"
else
    echo -e "${YELLOW}[WARN]${NC} Could not verify Valkey version in container"
fi

echo ""
echo "========================================"
echo "Next Steps"
echo "========================================"
echo ""
echo "1. Run the test suite:"
echo "   ./test-valkey-fips.sh"
echo ""
echo "2. Start a container:"
echo "   docker run -d --name valkey-fips -p 6379:6379 $FULL_IMAGE_NAME"
echo ""
echo "3. Connect to Valkey:"
echo "   docker exec -it valkey-fips valkey-cli"
echo ""
echo "4. View container logs:"
echo "   docker logs valkey-fips"
echo ""
echo "5. Check FIPS validation:"
echo "   docker logs valkey-fips | grep 'FIPS'"
echo ""
echo "6. Test TLS (if configured):"
echo "   docker exec -it valkey-fips valkey-cli --tls ..."
echo ""

# Option to run tests
read -p "Run test suite now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}[TEST]${NC} Running test suite..."
    ./test-valkey-fips.sh
fi
