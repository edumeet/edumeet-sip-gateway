#!/usr/bin/env bash
# Builds the images of the SIP room connector separately from the other eduMEET images.
# The version is SIPMEDIAGW_VERSION in this repository: the tag of the SIPMediaGW fork that is
# built, and the tag of the images. In the destination, this script writes only the
# edumeet-sip-* tar files and current_sip_version.txt.
# It clones both repositories itself, so its folder on the build server needs no git checkout:
# copy this file and .env-build (from .env-build.example) there, and run it in that folder.
set -euo pipefail

ENV_FILE=".env-build"
REPOSITORY=edumeet
NAMES=(edumeet-sip-gateway edumeet-sip-kamailio edumeet-sip-proxy)

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$ENV_FILE" ]] || die "Env file not found: $ENV_FILE"

env_value() (
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  printf '%s' "${!1:-}"
)
DEPLOY_REPO="$(env_value DEPLOY_REPO)"
DEPLOY_REPO="${DEPLOY_REPO:-https://github.com/edumeet/edumeet-sip-gateway.git}"
BRANCH="$(env_value BRANCH_SIP_GATEWAY)"
BRANCH="${BRANCH:-main}"
SIPMEDIAGW_REPO="$(env_value SIPMEDIAGW_REPO)"
SIPMEDIAGW_REPO="${SIPMEDIAGW_REPO:-https://github.com/edumeet/edumeet-sipmediagw.git}"
DEST_DIR="$(env_value DEST_DIR)"
[[ -n "$DEST_DIR" ]] || die "DEST_DIR is not set in $ENV_FILE"
mkdir -p "$DEST_DIR" || die "Failed to create destination dir: $DEST_DIR"

SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT

echo "Cloning $DEPLOY_REPO, branch $BRANCH..."
git clone --quiet --depth 1 --branch "$BRANCH" "$DEPLOY_REPO" "$SRC/deploy" \
  || die "Failed to clone $DEPLOY_REPO"
TAG="$(tr -d '[:space:]' < "$SRC/deploy/SIPMEDIAGW_VERSION")"
[[ -n "$TAG" ]] || die "SIPMEDIAGW_VERSION is empty"

# This copy runs on the build server; the repository has the current one.
if ! cmp -s "${BASH_SOURCE[0]}" "$SRC/deploy/build-server/build_and_publish.sh"; then
  echo "WARNING: this script differs from build-server/build_and_publish.sh on $BRANCH."
  echo "         Copy the new one to this folder before the next build."
  echo
fi

echo "Using TAG=$TAG (SIPMEDIAGW_VERSION)"
echo "Destination: $DEST_DIR"
echo

echo "Cloning SIPMediaGW at $TAG..."
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" "$SIPMEDIAGW_REPO" "$SRC/sipmediagw" \
  || die "Failed to clone $SIPMEDIAGW_REPO at $TAG"

# The proxy has no Dockerfile upstream: its build context is deploy/proxyAPI with central/proxy
# of this repository (Dockerfile, pinned packages).
cp -R "$SRC/sipmediagw/deploy/proxyAPI" "$SRC/proxy"
cp "$SRC/deploy/central/proxy/Dockerfile" "$SRC/deploy/central/proxy/requirements.txt" "$SRC/proxy/"

echo "Building (no cache)..."
docker build --no-cache --build-arg GW_VERSION="$TAG" --build-arg ALLOW_DEV_BUILD=0 \
  -t "${REPOSITORY}/edumeet-sip-gateway:${TAG}" "$SRC/sipmediagw" \
  || die "Failed to build edumeet-sip-gateway"
docker build --no-cache -t "${REPOSITORY}/edumeet-sip-kamailio:${TAG}" "$SRC/sipmediagw/deploy/kamailio" \
  || die "Failed to build edumeet-sip-kamailio"
docker build --no-cache -t "${REPOSITORY}/edumeet-sip-proxy:${TAG}" "$SRC/proxy" \
  || die "Failed to build edumeet-sip-proxy"
echo "Build succeeded."
echo

echo "Saving images to tar files..."
TARS=()
for name in "${NAMES[@]}"; do
  docker image inspect "${REPOSITORY}/${name}:${TAG}" > /dev/null 2>&1 || die "Image not found: ${REPOSITORY}/${name}:${TAG}"
  echo "  docker save -o \"${name}_${TAG}.tar\" \"${REPOSITORY}/${name}:${TAG}\""
  docker save -o "${name}_${TAG}.tar" "${REPOSITORY}/${name}:${TAG}"
  TARS+=("${name}_${TAG}.tar")
done
chmod +r "${TARS[@]}"
echo "All images saved."
for name in "${NAMES[@]}"; do
  docker rmi "${REPOSITORY}/${name}:${TAG}" > /dev/null
done
echo

echo "Moving tar files to destination..."
mv -f "${TARS[@]}" "$DEST_DIR/"
echo "$TAG" > "${DEST_DIR}/current_sip_version.txt"
echo "current_sip_version.txt updated with TAG=$TAG"

echo "Deleting the SIP tar files of other versions..."
find "$DEST_DIR" -maxdepth 1 -type f -name 'edumeet-sip-*.tar' ! -name "*_${TAG}.tar" -print -delete
echo "Done. Files are in: $DEST_DIR"
echo
echo "============================================================"
echo "Next: on the central host, central/update.sh;"
echo "on each gateway host, gateway-host/update.sh. They load the images of $TAG."
echo "============================================================"
