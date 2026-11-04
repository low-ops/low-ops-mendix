#!/usr/bin/env bash
# Used after the workflow bootstrap clone (see build.yaml x-repo-checkout).
set -eu

root="$(cd "$(dirname "$0")" && pwd)"
bash "$root/install_packages.sh"

base="${SERVER%/}"
case "$base" in
  https://*) origin="https://oauth2:${TOKEN}@${base#https://}" ;;
  http://*) origin="http://oauth2:${TOKEN}@${base#http://}" ;;
  *) origin="http://oauth2:${TOKEN}@${base}" ;;
esac
git init .
git remote add origin "${origin}/${REPO}.git"
git fetch --depth 1 origin "$SHA"
git checkout FETCH_HEAD
