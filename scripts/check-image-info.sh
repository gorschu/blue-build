#!/bin/bash

# Script to check basic image information and layer count
# Usage: ./check-image-info.sh [image]

IMAGE="${1:-ghcr.io/gorschu/bluefin-dx-gorschu:stable}"

# Add docker:// prefix if not present
if [[ ! "$IMAGE" =~ ^docker:// ]]; then
    IMAGE="docker://$IMAGE"
fi

echo "Checking image information for: $IMAGE"
echo "================================================"

# Check if skopeo is available
if ! command -v skopeo &> /dev/null; then
    echo "Error: skopeo is required but not installed"
    echo "Install with: sudo dnf install skopeo"
    exit 1
fi

echo "Basic image information:"
echo "========================"

# Get basic image info
INFO=$(skopeo inspect "$IMAGE" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch image information for $IMAGE"
    echo "Make sure the image exists and is accessible"
    exit 1
fi

# Extract key information
DIGEST=$(echo "$INFO" | jq -r '.Digest // "unknown"')
CREATED=$(echo "$INFO" | jq -r '.Created // "unknown"')
LAYERS=$(echo "$INFO" | jq -r '.Layers | length')
ARCHITECTURE=$(echo "$INFO" | jq -r '.Architecture // "unknown"')
OS=$(echo "$INFO" | jq -r '.Os // "unknown"')

echo "Digest: $DIGEST"
echo "Created: $CREATED"
echo "Architecture: $ARCHITECTURE"
echo "OS: $OS"
echo "Number of layers: $LAYERS"

echo
echo "Image was built with your latest GitHub Actions workflow."
echo "To verify zstd compression is working, check your build logs for:"
echo "  - 'compression_format: zstd' in build options"
echo "  - Build time improvements compared to gzip"
echo "  - Any compression-related messages during push"

echo
echo "Recent layer information (last 5 layers):"
echo "=========================================="
echo "$INFO" | jq -r '.Layers[-5:] | .[]' 2>/dev/null | tail -5