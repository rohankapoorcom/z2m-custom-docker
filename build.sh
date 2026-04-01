#!/usr/bin/env bash
set -euo pipefail

# Required
CONVERTERS_DIR="${CONVERTERS_DIR:?Set CONVERTERS_DIR to the zigbee-herdsman-converters checkout}"
Z2M_DIR="${Z2M_DIR:?Set Z2M_DIR to the zigbee2mqtt checkout}"

# Required
CONVERTERS_REPO="${CONVERTERS_REPO:?Set CONVERTERS_REPO to the converters repo (owner/repo)}"
CONVERTERS_REF="${CONVERTERS_REF:?Set CONVERTERS_REF to the converters branch or tag}"

for cmd in node pnpm jq docker; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' is required but not found"; exit 1; }
done

CONVERTERS_DIR="$(cd "$CONVERTERS_DIR" && pwd)"
Z2M_DIR="$(cd "$Z2M_DIR" && pwd)"

# Sanitize repo/ref for use in Docker tags (lowercase, alphanumeric/hyphens/dots only)
SANITIZED_TAG="$(echo "${CONVERTERS_REPO}/${CONVERTERS_REF}" | sed 's|/|.|g; s|[^a-zA-Z0-9.\-]|-|g' | tr '[:upper:]' '[:lower:]')"

# Optional
DOCKER_TAG="${DOCKER_TAG:-zigbee2mqtt:${SANITIZED_TAG}}"

echo "::group::Configuration"
echo "  CONVERTERS_DIR : $CONVERTERS_DIR"
echo "  Z2M_DIR        : $Z2M_DIR"
echo "  DOCKER_TAG     : $DOCKER_TAG"
echo "  CONVERTERS_REPO: $CONVERTERS_REPO"
echo "  CONVERTERS_REF : $CONVERTERS_REF"
echo "::endgroup::"

########################################
# 1. Build and pack converters
########################################
echo "::group::Build and pack zigbee-herdsman-converters"
cd "$CONVERTERS_DIR"

# Stamp the version with repo/branch metadata (semver pre-release tag)
# e.g. 26.22.0 -> 26.22.0-rohankapoorcom.inovelli-lib-cleanup
SANITIZED_META="$(echo "${CONVERTERS_REPO}/${CONVERTERS_REF}" | sed 's|/|.|g; s|[^a-zA-Z0-9.\-]|-|g')"
BASE_VERSION="$(jq -r '.version' package.json)"
STAMPED_VERSION="${BASE_VERSION}-${SANITIZED_META}"
jq --arg v "$STAMPED_VERSION" '.version = $v' package.json > package.json.tmp && mv package.json.tmp package.json
echo "Stamped version: $STAMPED_VERSION"

pnpm install --frozen-lockfile
rm -f zigbee-herdsman-converters-*.tgz
pnpm pack
TARBALL_NAME="$(ls zigbee-herdsman-converters-*.tgz)"
cp "$TARBALL_NAME" "$Z2M_DIR/"
echo "Packed: $TARBALL_NAME"
echo "::endgroup::"

########################################
# 2. Patch zigbee2mqtt
########################################
echo "::group::Patch zigbee2mqtt"
cd "$Z2M_DIR"

# package.json: point converters dependency at the local tarball
jq --arg tgz "file:./$TARBALL_NAME" \
    '.dependencies["zigbee-herdsman-converters"] = $tgz' \
    package.json > package.json.tmp && mv package.json.tmp package.json
echo "Patched package.json -> file:./$TARBALL_NAME"

# Dockerfile: include tarball in COPY and drop --frozen-lockfile
sed -i 's|COPY package.json pnpm-lock.yaml \./|COPY package.json pnpm-lock.yaml zigbee-herdsman-converters-*.tgz ./|' docker/Dockerfile
sed -i 's|pnpm install --frozen-lockfile --prod|pnpm install --prod|' docker/Dockerfile
echo "Patched docker/Dockerfile"
echo "::endgroup::"

########################################
# 3. Install deps and build zigbee2mqtt
########################################
echo "::group::Build zigbee2mqtt"
cd "$Z2M_DIR"
pnpm install --no-frozen-lockfile
pnpm run build
echo "::endgroup::"

########################################
# 4. Build Docker image
########################################
echo "::group::Build Docker image"
cd "$Z2M_DIR"
docker build -f docker/Dockerfile -t "$DOCKER_TAG" .
echo "::endgroup::"

echo ""
echo "Done! Docker image: $DOCKER_TAG"
