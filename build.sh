#!/usr/bin/env bash
set -euo pipefail

# Required
HERDSMAN_DIR="${HERDSMAN_DIR:?Set HERDSMAN_DIR to the zigbee-herdsman checkout}"
CONVERTERS_DIR="${CONVERTERS_DIR:?Set CONVERTERS_DIR to the zigbee-herdsman-converters checkout}"
Z2M_DIR="${Z2M_DIR:?Set Z2M_DIR to the zigbee2mqtt checkout}"

# Required
HERDSMAN_REPO="${HERDSMAN_REPO:?Set HERDSMAN_REPO to the herdsman repo (owner/repo)}"
HERDSMAN_REF="${HERDSMAN_REF:?Set HERDSMAN_REF to the herdsman branch or tag}"
CONVERTERS_REPO="${CONVERTERS_REPO:?Set CONVERTERS_REPO to the converters repo (owner/repo)}"
CONVERTERS_REF="${CONVERTERS_REF:?Set CONVERTERS_REF to the converters branch or tag}"

for cmd in node pnpm jq docker sha1sum; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' is required but not found"; exit 1; }
done

HERDSMAN_DIR="$(cd "$HERDSMAN_DIR" && pwd)"
CONVERTERS_DIR="$(cd "$CONVERTERS_DIR" && pwd)"
Z2M_DIR="$(cd "$Z2M_DIR" && pwd)"

# Sanitize a "<repo>/<ref>" string for use as part of a Docker tag (lowercase,
# alphanumeric/hyphens/dots only). Long inputs are truncated to 50 chars and
# given a deterministic 8-char sha1 suffix so the result stays unique.
sanitize_tag_segment() {
    local raw="$1"
    local sanitized
    sanitized="$(echo "$raw" | sed 's|/|.|g; s|[^a-zA-Z0-9.\-]|-|g' | tr '[:upper:]' '[:lower:]')"
    if [ "${#sanitized}" -gt 50 ]; then
        local hash
        hash="$(echo -n "$raw" | sha1sum | cut -c1-8)"
        sanitized="${sanitized:0:41}-${hash}"
    fi
    echo "$sanitized"
}

# Stamp a package's version with repo/branch metadata as a semver pre-release
# tag (e.g. 26.22.0 -> 26.22.0-rohankapoorcom.repo.branch). Mirrors the tag
# sanitization but keeps original case since semver pre-release identifiers
# are case-sensitive and we want them readable.
sanitize_version_meta() {
    echo "$1" | sed 's|/|.|g; s|[^a-zA-Z0-9.\-]|-|g'
}

CONVERTERS_TAG_SEGMENT="$(sanitize_tag_segment "${CONVERTERS_REPO}/${CONVERTERS_REF}")"
HERDSMAN_TAG_SEGMENT="$(sanitize_tag_segment "${HERDSMAN_REPO}/${HERDSMAN_REF}")"
SANITIZED_TAG="${CONVERTERS_TAG_SEGMENT}__${HERDSMAN_TAG_SEGMENT}"

# Optional
DOCKER_TAG="${DOCKER_TAG:-zigbee2mqtt:${SANITIZED_TAG}}"

echo "::group::Configuration"
echo "  HERDSMAN_DIR   : $HERDSMAN_DIR"
echo "  CONVERTERS_DIR : $CONVERTERS_DIR"
echo "  Z2M_DIR        : $Z2M_DIR"
echo "  DOCKER_TAG     : $DOCKER_TAG"
echo "  HERDSMAN_REPO  : $HERDSMAN_REPO"
echo "  HERDSMAN_REF   : $HERDSMAN_REF"
echo "  CONVERTERS_REPO: $CONVERTERS_REPO"
echo "  CONVERTERS_REF : $CONVERTERS_REF"
echo "::endgroup::"

########################################
# 0. Build and pack zigbee-herdsman
########################################
echo "::group::Build and pack zigbee-herdsman"
cd "$HERDSMAN_DIR"

HERDSMAN_VERSION_META="$(sanitize_version_meta "${HERDSMAN_REPO}/${HERDSMAN_REF}")"
HERDSMAN_BASE_VERSION="$(jq -r '.version' package.json)"
HERDSMAN_STAMPED_VERSION="${HERDSMAN_BASE_VERSION}-${HERDSMAN_VERSION_META}"
jq --arg v "$HERDSMAN_STAMPED_VERSION" '.version = $v' package.json > package.json.tmp && mv package.json.tmp package.json
echo "Stamped herdsman version: $HERDSMAN_STAMPED_VERSION"

pnpm install --frozen-lockfile
rm -f zigbee-herdsman-*.tgz
pnpm pack
HERDSMAN_TARBALL_NAME="$(ls zigbee-herdsman-*.tgz)"
cp "$HERDSMAN_TARBALL_NAME" "$CONVERTERS_DIR/"
cp "$HERDSMAN_TARBALL_NAME" "$Z2M_DIR/"
echo "Packed herdsman: $HERDSMAN_TARBALL_NAME"
echo "::endgroup::"

########################################
# 1. Build and pack converters
########################################
echo "::group::Build and pack zigbee-herdsman-converters"
cd "$CONVERTERS_DIR"

# Stamp the version with repo/branch metadata (semver pre-release tag)
# e.g. 26.22.0 -> 26.22.0-rohankapoorcom.inovelli-lib-cleanup
CONVERTERS_VERSION_META="$(sanitize_version_meta "${CONVERTERS_REPO}/${CONVERTERS_REF}")"
CONVERTERS_BASE_VERSION="$(jq -r '.version' package.json)"
CONVERTERS_STAMPED_VERSION="${CONVERTERS_BASE_VERSION}-${CONVERTERS_VERSION_META}"
jq --arg v "$CONVERTERS_STAMPED_VERSION" '.version = $v' package.json > package.json.tmp && mv package.json.tmp package.json
echo "Stamped converters version: $CONVERTERS_STAMPED_VERSION"

# Point converters' zigbee-herdsman dependency at the local tarball so the
# TypeScript build compiles against the same API surface the runtime will see.
jq --arg tgz "file:./$HERDSMAN_TARBALL_NAME" \
    '.dependencies["zigbee-herdsman"] = $tgz' \
    package.json > package.json.tmp && mv package.json.tmp package.json
echo "Patched converters package.json -> zigbee-herdsman: file:./$HERDSMAN_TARBALL_NAME"

pnpm install --no-frozen-lockfile
rm -f zigbee-herdsman-converters-*.tgz
pnpm pack
CONVERTERS_TARBALL_NAME="$(ls zigbee-herdsman-converters-*.tgz)"
cp "$CONVERTERS_TARBALL_NAME" "$Z2M_DIR/"
echo "Packed converters: $CONVERTERS_TARBALL_NAME"
echo "::endgroup::"

########################################
# 2. Patch zigbee2mqtt
########################################
echo "::group::Patch zigbee2mqtt"
cd "$Z2M_DIR"

# package.json: point both deps at the local tarballs. The existing
# pnpm.overrides."zigbee-herdsman": "$zigbee-herdsman" entry then propagates
# the override into transitive consumers (including the converters tarball).
jq --arg conv "file:./$CONVERTERS_TARBALL_NAME" \
   --arg herd "file:./$HERDSMAN_TARBALL_NAME" \
    '.dependencies["zigbee-herdsman-converters"] = $conv
     | .dependencies["zigbee-herdsman"] = $herd' \
    package.json > package.json.tmp && mv package.json.tmp package.json
echo "Patched package.json -> zigbee-herdsman-converters: file:./$CONVERTERS_TARBALL_NAME"
echo "Patched package.json -> zigbee-herdsman: file:./$HERDSMAN_TARBALL_NAME"

# Dockerfile: include both tarballs in COPY and drop --frozen-lockfile
sed -i 's|COPY package.json pnpm-lock.yaml \./|COPY package.json pnpm-lock.yaml zigbee-herdsman-*.tgz zigbee-herdsman-converters-*.tgz ./|' docker/Dockerfile
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
echo "Done!"
echo "  Docker image      : $DOCKER_TAG"
echo "  Herdsman version  : $HERDSMAN_STAMPED_VERSION ($HERDSMAN_TARBALL_NAME)"
echo "  Converters version: $CONVERTERS_STAMPED_VERSION ($CONVERTERS_TARBALL_NAME)"
