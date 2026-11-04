#!/usr/bin/env bash
set -eu

version=$(cat version.txt)
mpr=$(cat mpr.txt)
short=$(printf '%s' "$SHA" | cut -c1-7)
tag=$(printf '%s' "${REF_NAME}-${short}" | sed 's/%20/_/g' | tr -cd '[:alnum:]_.-' | sed 's/^[.-]*//' | cut -c -128)

echo "version=${version}" >> "$GITHUB_OUTPUT"
echo "mpr=${mpr}" >> "$GITHUB_OUTPUT"
echo "tag=${tag}" >> "$GITHUB_OUTPUT"

rm -f meta.sh version.txt mpr.txt
