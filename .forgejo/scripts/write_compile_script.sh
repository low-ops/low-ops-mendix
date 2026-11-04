#!/usr/bin/env bash
set -eu

mpr=$1
tag=$2

chmod -R a+rwX .
cat > compile.sh <<EOF
#!/bin/sh
set -eu
export BUILD_PATH=.
export MPR_FILE_PATH='${mpr}'
export TAG_NAME='${tag}'
export MDA_FILE_PATH="\$PWD/mda-path.txt"
/opt/mendix/compile.sh
find . -name '*.mda' -exec chmod a+r {} +
EOF
chmod +x compile.sh
