#!/usr/bin/env bash
set -euo pipefail

# Required
CONVERTERS_DIR="${CONVERTERS_DIR:?Set CONVERTERS_DIR to the zigbee-herdsman-converters repo path}"

# Optional with defaults (Z2M_REPO accepts owner/repo or a full URL)
Z2M_REPO="${Z2M_REPO:-Koenkk/zigbee2mqtt}"
if [[ "$Z2M_REPO" != *"://"* ]]; then
    Z2M_REPO="https://github.com/$Z2M_REPO.git"
fi
Z2M_REF="${Z2M_REF:-master}"
DOCKER_TAG="${DOCKER_TAG:-zigbee2mqtt:custom-converters}"
WORK_DIR="${WORK_DIR:-./build}"

for cmd in git node pnpm jq docker; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' is required but not found"; exit 1; }
done

mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
CONVERTERS_DIR="$(cd "$CONVERTERS_DIR" && pwd)"

echo "::group::Configuration"
echo "  CONVERTERS_DIR : $CONVERTERS_DIR"
echo "  Z2M_REPO       : $Z2M_REPO"
echo "  Z2M_REF        : $Z2M_REF"
echo "  DOCKER_TAG     : $DOCKER_TAG"
echo "  WORK_DIR       : $WORK_DIR"
echo "::endgroup::"

########################################
# 1. Clone zigbee2mqtt
########################################
echo "::group::Clone zigbee2mqtt @ $Z2M_REF"
Z2M_DIR="$WORK_DIR/zigbee2mqtt"
rm -rf "$Z2M_DIR"
git clone --depth 1 --branch "$Z2M_REF" "$Z2M_REPO" "$Z2M_DIR"
echo "::endgroup::"

########################################
# 2. Build and pack converters
########################################
echo "::group::Build and pack zigbee-herdsman-converters"
cd "$CONVERTERS_DIR"
pnpm install --frozen-lockfile
rm -f zigbee-herdsman-converters-*.tgz
pnpm pack
TARBALL_NAME="$(ls zigbee-herdsman-converters-*.tgz)"
cp "$TARBALL_NAME" "$Z2M_DIR/"
echo "Packed: $TARBALL_NAME"
echo "::endgroup::"

########################################
# 3. Patch zigbee2mqtt
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
# 4. Install deps and build zigbee2mqtt
########################################
echo "::group::Build zigbee2mqtt"
cd "$Z2M_DIR"
pnpm install --no-frozen-lockfile
pnpm run build
echo "::endgroup::"

########################################
# 5. Build Docker image
########################################
echo "::group::Build Docker image"
cd "$Z2M_DIR"
docker build -f docker/Dockerfile -t "$DOCKER_TAG" .
echo "::endgroup::"

echo ""
echo "Done! Docker image: $DOCKER_TAG"
