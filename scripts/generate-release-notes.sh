#!/usr/bin/env bash

set -euo pipefail

# Script: generate-release-notes.sh
# Description: Generates release notes from CHANGELOG.md and git history
# Usage: ./generate-release-notes.sh <github_ref> <github_repository> <github_output>
# Arguments:
#   - GITHUB_REF: The git ref (e.g., refs/tags/v1.0.0)
#   - GITHUB_REPOSITORY: The GitHub repository (e.g., owner/repo)
#   - GITHUB_OUTPUT: Path to the GitHub Actions output file

GITHUB_REF="${1:-}"
GITHUB_REPOSITORY="${2:-}"
GITHUB_OUTPUT="${3:-}"

if [ -z "$GITHUB_REF" ] || [ -z "$GITHUB_REPOSITORY" ]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <github_ref> <github_repository> <github_output>"
  exit 1
fi

echo "Generating release notes..."

# Handle both tag pushes and workflow_dispatch
if [[ "$GITHUB_REF" == refs/tags/* ]]; then
  TAG_NAME=${GITHUB_REF#refs/tags/}
else
  TAG_NAME=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0-dev")
fi

if [ -n "$GITHUB_OUTPUT" ]; then
  echo "tag_name=$TAG_NAME" >> "$GITHUB_OUTPUT"
fi

VERSION_NUM=${TAG_NAME#v}  # Remove 'v' prefix if present

# Check if prerelease
if [[ "$VERSION_NUM" =~ (alpha|beta|rc) ]]; then
  if [ -n "$GITHUB_OUTPUT" ]; then
    echo "is_prerelease=true" >> "$GITHUB_OUTPUT"
  fi
else
  if [ -n "$GITHUB_OUTPUT" ]; then
    echo "is_prerelease=false" >> "$GITHUB_OUTPUT"
  fi
fi

# Filter the tag list to only inclued previous 'versioned' tag
PREV_TAG=$(git tag --sort=-version:refname --merged $TAG_NAME^ 2>/dev/null | \
  grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | \
  grep -v "^$TAG_NAME$" | \
  head -n 1 || echo "")

# Extract changelog section (Keep a Changelog format)
if [ -f "CHANGELOG.md" ]; then
  echo "## What's Changed" >> release_notes.md
  echo "" >> release_notes.md

  # Look for version with ## [Version] format (Keep a Changelog standard)
  awk -v version="$VERSION_NUM" '
    BEGIN { found=0; in_section=0 }

    # Match version headers with ## [version] format
    /^## \[/ {
      if (in_section) exit  # Stop at next version

      # Extract version from [version] - YYYY-MM-DD format
      match($0, /\[([^\]]+)\]/, arr)
      if (arr[1]) {
        ver = arr[1]
        # Remove v prefix if present
        gsub(/^v/, "", ver)

        if (ver == version) {
          found=1
          in_section=1
          next  # Skip the header itself
        }
      }
    }

    # Print content if we are in the right section
    in_section {
      # Stop if we hit a new version header (## [)
      if (/^## \[/) exit
      # Skip the bottom link references
      if (/^\[.*\]:/) exit
      print
    }
  ' CHANGELOG.md > changelog_section.tmp

  if [ -s changelog_section.tmp ]; then
    cat changelog_section.tmp >> release_notes.md
    echo "" >> release_notes.md
  else
    echo " No changelog entry found for version $VERSION_NUM in CHANGELOG.md" >> release_notes.md
    echo "" >> release_notes.md
  fi
  rm -f changelog_section.tmp
fi

# Add detailed commit history
if [ -n "$PREV_TAG" ]; then
  echo "---" >> release_notes.md
  echo "" >> release_notes.md
  echo "## Full Commit History" >> release_notes.md
  echo "" >> release_notes.md
  echo "<details>" >> release_notes.md
  echo "<summary>Click to expand</summary>" >> release_notes.md
  echo "" >> release_notes.md
  git log --pretty=format:"- %s (%h)" $PREV_TAG..$TAG_NAME >> release_notes.md
  echo "" >> release_notes.md
  echo "</details>" >> release_notes.md
  echo "" >> release_notes.md

  # Add comparison link
  echo "**Full Diff**: [\`$PREV_TAG...$TAG_NAME\`](https://github.com/$GITHUB_REPOSITORY/compare/$PREV_TAG...$TAG_NAME)" >> release_notes.md
  echo "" >> release_notes.md
fi

# Add asset information
echo "---" >> release_notes.md
echo "" >> release_notes.md
echo "## Installation" >> release_notes.md
echo "" >> release_notes.md
echo "### Download Binaries" >> release_notes.md
echo "" >> release_notes.md
echo "| Platform | Architecture | Download |" >> release_notes.md
echo "|----------|--------------|----------|" >> release_notes.md
echo "| 🍎 macOS | ARM64 (Apple Silicon) | [\`flows2fim-darwin-arm64.tar.gz\`](https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG_NAME/flows2fim-darwin-arm64.tar.gz) |" >> release_notes.md
echo "| 🐧 Linux | AMD64 | [\`flows2fim-linux-amd64.tar.gz\`](https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG_NAME/flows2fim-linux-amd64.tar.gz) |" >> release_notes.md
echo "| 🐧 Linux | ARM64 | [\`flows2fim-linux-arm64.tar.gz\`](https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG_NAME/flows2fim-linux-arm64.tar.gz) |" >> release_notes.md
echo "| 🪟 Windows | AMD64 | [\`flows2fim-windows-amd64.zip\`](https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG_NAME/flows2fim-windows-amd64.zip) |" >> release_notes.md
echo "" >> release_notes.md

echo "### 🐳 Docker/Container" >> release_notes.md
echo "" >> release_notes.md
echo "\`\`\`bash" >> release_notes.md
echo "# Pull the image" >> release_notes.md
echo "docker pull ghcr.io/$GITHUB_REPOSITORY:${TAG_NAME#v}" >> release_notes.md
echo "" >> release_notes.md
echo "# Or use latest" >> release_notes.md
echo "docker pull ghcr.io/$GITHUB_REPOSITORY:latest" >> release_notes.md
echo "\`\`\`" >> release_notes.md
echo "" >> release_notes.md

echo "### 🔐 Verification" >> release_notes.md
echo "" >> release_notes.md
echo "All release assets include SHA256 checksums for verification:" >> release_notes.md
echo "" >> release_notes.md
echo "\`\`\`bash" >> release_notes.md
echo "# Download checksums file" >> release_notes.md
echo "curl -LO https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG_NAME/checksums.txt" >> release_notes.md
echo "" >> release_notes.md
echo "# Verify your download" >> release_notes.md
echo "sha256sum -c checksums.txt" >> release_notes.md
echo "\`\`\`" >> release_notes.md

echo "Release notes generated successfully: release_notes.md"
