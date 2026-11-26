#!/usr/bin/env bash
set -eu

rm -f compile.sh mda-path.txt
mda=$(find . -name '*.mda' | head -n 1)
test -n "$mda"

mkdir -p project scripts
unzip "$mda" -d ./project
cp -r /app/buildpack/scripts/* ./scripts/

if [ -f Dockerfile ]; then
  dockerfile="$PWD/Dockerfile"
else
  dockerfile=/app/buildpack/Dockerfile
fi

mkdir -p /kaniko/.docker
auth=$(printf '%s:%s' "$HARBOR_USERNAME" "$HARBOR_PASSWORD" | base64 | tr -d '\n')
printf '{"auths":{"https://%s":{"auth":"%s"},"%s":{"auth":"%s"}}}\n' \
  "$REGISTRY" "$auth" "$REGISTRY" "$auth" > /kaniko/.docker/config.json

image="${REGISTRY}/apps-${APP}/app:${TAG}"
share="/srv/shared/${CORRELATION}"
mkdir -p "$share"
chmod 777 "$share"

meta=$(find . -path '*/model/metadata.json' | head -n 1)
if [ -n "$meta" ]; then
  cp "$meta" "$share/metadata.json"
fi

printf 'image=%s\ncommit=%s\n' "$image" "$SHA" > "$share/build-log.txt"

# Unqualified names (mendix-rootfs:builder) resolve to Docker Hub library/.
ROOTFS_APP="${ROOTFS_APP:-${REGISTRY}/low-ops/rootfs-app:0-ci-main}"
ROOTFS_BUILDER="${ROOTFS_BUILDER:-${REGISTRY}/low-ops/rootfs-builder:0-ci-main}"
case "${ROOTFS_APP}" in
  *.*/*) ;;
  *) echo "ROOTFS_APP must be a fully qualified image, got: ${ROOTFS_APP}" >&2; exit 1 ;;
esac
case "${ROOTFS_BUILDER}" in
  *.*/*) ;;
  *) echo "ROOTFS_BUILDER must be a fully qualified image, got: ${ROOTFS_BUILDER}" >&2; exit 1 ;;
esac

/kaniko/executor \
  --context "$PWD" \
  --dockerfile "$dockerfile" \
  --destination "$image" \
  --build-arg "ROOTFS_IMAGE=${ROOTFS_APP}" \
  --build-arg "BUILDER_ROOTFS_IMAGE=${ROOTFS_BUILDER}" \
  --ignore-path=/var/mail \
  --ignore-path=/var/spool/mail \
  --ignore-path=//product_uuid \
  --ignore-path=/srv/shared \
  --cleanup

echo "image=${image}" >> "$GITHUB_OUTPUT"
