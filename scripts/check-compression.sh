#!/bin/bash

# Script to check compression format of container image layers
# Usage: ./check-compression.sh [image]

IMAGE="${1:-ghcr.io/gorschu/bluefin-dx-gorschu:stable}"

# Add docker:// prefix if not present
if [[ ! "$IMAGE" =~ ^docker:// ]]; then
    IMAGE="docker://$IMAGE"
fi

echo "Checking compression format for image: $IMAGE"
echo "================================================"

# Check if skopeo is available
if ! command -v skopeo &> /dev/null; then
    echo "Error: skopeo is required but not installed"
    echo "Install with: sudo dnf install skopeo"
    exit 1
fi

# Inspect the image manifest
echo "Fetching image manifest..."
MANIFEST=$(skopeo inspect --raw "$IMAGE" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch manifest for $IMAGE"
    echo "Make sure the image exists and is accessible"
    exit 1
fi

# Extract layer information
echo "Analyzing layer compression formats..."
echo

# Try to get layers from manifest directly first
LAYERS=$(echo "$MANIFEST" | jq -r '.layers[]?.mediaType // empty' 2>/dev/null)

# If no layers found, this might be a manifest list (multi-arch image)
if [ -z "$LAYERS" ]; then
    echo "Image appears to be a manifest list (multi-arch), checking individual manifests..."
    
    # Get manifest list and find the linux/amd64 manifest
    AMD64_DIGEST=$(echo "$MANIFEST" | jq -r '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest' 2>/dev/null | head -1)
    
    if [ -n "$AMD64_DIGEST" ]; then
        # Remove tag from image URL when using digest  
        BASE_IMAGE=$(echo "$IMAGE" | sed 's/:[^:]*$//')
        ARCH_MANIFEST_URL="${BASE_IMAGE}@${AMD64_DIGEST}"
        echo "Checking linux/amd64 manifest: $ARCH_MANIFEST_URL"
        ARCH_MANIFEST=$(skopeo inspect --raw "$ARCH_MANIFEST_URL" 2>/dev/null)
        if [ $? -eq 0 ]; then
            LAYERS=$(echo "$ARCH_MANIFEST" | jq -r '.layers[]?.mediaType // empty' 2>/dev/null)
        fi
    fi
    
    # Fallback: get first manifest if no amd64 found
    if [ -z "$LAYERS" ]; then
        FIRST_MANIFEST_DIGEST=$(echo "$MANIFEST" | jq -r '.manifests[]?.digest // empty' 2>/dev/null | head -1)
        if [ -n "$FIRST_MANIFEST_DIGEST" ]; then
            # Remove tag from image URL when using digest
            BASE_IMAGE=$(echo "$IMAGE" | sed 's/:[^:]*$//')
            FIRST_MANIFEST_URL="${BASE_IMAGE}@${FIRST_MANIFEST_DIGEST}"
            echo "Checking first available manifest: $FIRST_MANIFEST_URL"
            FIRST_MANIFEST=$(skopeo inspect --raw "$FIRST_MANIFEST_URL" 2>/dev/null)
            if [ $? -eq 0 ]; then
                LAYERS=$(echo "$FIRST_MANIFEST" | jq -r '.layers[]?.mediaType // empty' 2>/dev/null)
            fi
        fi
    fi
fi

if [ -z "$LAYERS" ]; then
    echo "Error: Could not extract layer mediaType information from manifest"
    echo "This is unexpected - OCI images should have compression info in mediaType fields"
    echo ""
    echo "Debug information:"
    echo "Manifest structure:"
    echo "$MANIFEST" | jq '.' 2>/dev/null | head -20
    exit 1
fi

# Count compression types
GZIP_COUNT=0
ZSTD_COUNT=0
ZSTD_CHUNKED_COUNT=0
OTHER_COUNT=0

echo "Layer compression analysis:"
echo "=========================="

while IFS= read -r layer; do
    case "$layer" in
        *"tar+gzip"*)
            echo "📦 GZIP layer: $layer"
            ((GZIP_COUNT++))
            ;;
        *"tar+zstd:chunked"*)
            echo "🚀 ZSTD:CHUNKED layer: $layer"
            ((ZSTD_CHUNKED_COUNT++))
            ;;
        *"tar+zstd"*)
            echo "⚡ ZSTD layer: $layer"
            ((ZSTD_COUNT++))
            ;;
        *"tar"*)
            echo "📄 UNCOMPRESSED layer: $layer"
            ((OTHER_COUNT++))
            ;;
        *)
            echo "❓ OTHER layer: $layer"
            ((OTHER_COUNT++))
            ;;
    esac
done <<< "$LAYERS"

echo
echo "Summary:"
echo "========"
echo "GZIP layers: $GZIP_COUNT"
echo "ZSTD layers: $ZSTD_COUNT"
echo "ZSTD:CHUNKED layers: $ZSTD_CHUNKED_COUNT"
echo "OTHER layers: $OTHER_COUNT"

echo
if [ $ZSTD_CHUNKED_COUNT -gt 0 ]; then
    echo "✅ SUCCESS: Image contains zstd:chunked compressed layers!"
elif [ $ZSTD_COUNT -gt 0 ]; then
    echo "⚡ PARTIAL: Image contains zstd compressed layers (but not chunked)"
elif [ $GZIP_COUNT -gt 0 ]; then
    echo "📦 LEGACY: Image uses gzip compression"
else
    echo "❓ UNKNOWN: Could not determine compression format"
fi