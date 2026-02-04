#!/bin/bash
###############################################################################
# Build Script for FIPS-Enabled Valkey (STIG/CIS Hardened)
###############################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="valkey"
IMAGE_TAG="8.1.5-ubuntu-22.04-fips"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
DOCKERFILE="Dockerfile.hardened"
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
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "Valkey FIPS + STIG/CIS Builder"
echo "========================================"
echo ""

###############################################################################
# Pre-build checks
###############################################################################
echo -e "${BLUE}[CHECK]${NC} Performing pre-build checks..."

# Check if running from correct directory
if [ ! -f "$DOCKERFILE" ]; then
    echo -e "${RED}[ERROR]${NC} Dockerfile not found: $DOCKERFILE"
    exit 1
fi

# Check for password file
if [ ! -f "$PASSWORD_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} Password file not found: $PASSWORD_FILE"
    exit 1
fi

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Docker is not installed"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Docker found: $(docker --version)"

# Check Docker BuildKit support
if ! docker buildx version >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Docker BuildKit not available"
    exit 1
else
    echo -e "${GREEN}[OK]${NC} Docker BuildKit available"
fi

echo ""
echo "========================================"
echo "Build Configuration"
echo "========================================"
echo "Image Name:    $FULL_IMAGE_NAME"
echo "Dockerfile:    $DOCKERFILE"
echo "Security:      FIPS 140-3 + DISA STIG + CIS"
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
echo "Security:   FIPS 140-3 + DISA STIG + CIS"
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

TEST_CONTAINER="valkey-fips-hardened-test-$$"

if docker run --rm --name "$TEST_CONTAINER" "$FULL_IMAGE_NAME" valkey-server --version >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Container verified"
else
    echo -e "${YELLOW}[WARN]${NC} Could not verify container"
fi

echo ""
echo "========================================"
echo "Next Steps"
echo "========================================"
echo ""
echo "1. Run: docker run -d --name valkey-fips-hardened -p 6379:6379 $FULL_IMAGE_NAME"
echo "2. Test: docker exec -it valkey-fips-hardened valkey-cli ping"
echo "3. FIPS: docker logs valkey-fips-hardened | grep FIPS"
echo "4. Scan: oscap xccdf eval ..."
echo ""
