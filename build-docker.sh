#!/bin/bash
# build-docker.sh — build and push multi-arch Docker image to Docker Hub
#
# Output:
#   webosarchive/squid-sslbump-for-webos:latest
#   webosarchive/squid-sslbump-for-webos:<squid-version>
#
# Prerequisites:
#   - Docker with buildx support
#   - docker login (logged in to Docker Hub as webosarchive)
#
# Usage:
#   ./build-docker.sh              # build and push
#   ./build-docker.sh --no-push   # build only (loads amd64 image locally)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE="webosarchive/squid-sslbump-for-webos"
PLATFORMS="linux/amd64,linux/arm64"
BUILDER_NAME="squid-webos-builder"

# Read version from Dockerfile so it stays in sync automatically
SQUID_VERSION="$(grep -m1 '^ARG SQUID_VERSION=' "$SCRIPT_DIR/Dockerfile" | cut -d= -f2)"

# ---------------------------------------------------------------

log() { echo "" && echo "==> $*"; }

check_prereqs() {
    log "Checking prerequisites..."

    if ! command -v docker &>/dev/null; then
        echo "ERROR: docker not found. Install Docker Desktop or Docker Engine."
        exit 1
    fi

    if ! docker buildx version &>/dev/null; then
        echo "ERROR: docker buildx not available. Upgrade to Docker 20.10+ or Docker Desktop."
        exit 1
    fi

    if [ "$PUSH" = "1" ]; then
        if ! docker info 2>/dev/null | grep -q "Username"; then
            echo "ERROR: Not logged in to Docker Hub. Run: docker login"
            exit 1
        fi
    fi

    echo "Prerequisites OK."
}

ensure_builder() {
    log "Checking buildx builder ($BUILDER_NAME)..."

    if docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
        echo "Builder '$BUILDER_NAME' already exists."
    else
        echo "Creating builder '$BUILDER_NAME' (docker-container driver for multi-arch support)..."
        docker buildx create \
            --name "$BUILDER_NAME" \
            --driver docker-container \
            --bootstrap
    fi

    docker buildx use "$BUILDER_NAME"
}

build_and_push() {
    local tags=(
        "-t" "${IMAGE}:latest"
        "-t" "${IMAGE}:${SQUID_VERSION}"
    )

    if [ "$PUSH" = "1" ]; then
        log "Building and pushing $IMAGE (squid $SQUID_VERSION) for $PLATFORMS..."
        docker buildx build \
            --platform "$PLATFORMS" \
            "${tags[@]}" \
            --push \
            "$SCRIPT_DIR"
    else
        log "Building $IMAGE (squid $SQUID_VERSION) for linux/amd64 (local load, no push)..."
        echo "NOTE: --load only supports a single platform. Building amd64 only."
        docker buildx build \
            --platform linux/amd64 \
            "${tags[@]}" \
            --load \
            "$SCRIPT_DIR"
    fi
}

main() {
    PUSH=1
    for arg in "$@"; do
        case "$arg" in
            --no-push) PUSH=0 ;;
            *) echo "ERROR: Unknown argument '$arg'. Usage: $0 [--no-push]" >&2; exit 1 ;;
        esac
    done

    echo ""
    echo "squid-sslbump-for-webos — Docker build"
    echo "Image:     $IMAGE"
    echo "Squid:     $SQUID_VERSION"
    echo "Platforms: $PLATFORMS"
    echo "Push:      $([ "$PUSH" = "1" ] && echo yes || echo no)"
    echo ""

    check_prereqs
    ensure_builder
    build_and_push

    echo ""
    echo "========================================"
    echo " Build complete"
    if [ "$PUSH" = "1" ]; then
        echo " Pushed: ${IMAGE}:latest"
        echo " Pushed: ${IMAGE}:${SQUID_VERSION}"
    else
        echo " Loaded: ${IMAGE}:latest (amd64 only)"
    fi
    echo "========================================"
}

main "$@"
