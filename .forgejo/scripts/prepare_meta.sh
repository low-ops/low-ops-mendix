#!/usr/bin/env bash
set -eu

chmod -R a+rwX .
cat > meta.sh <<'EOF'
#!/bin/sh
set -eu
/opt/mendix/bin/mxpc-pipeline-tools-cli mx-app-ver . > version.txt
/opt/mendix/bin/mxpc-pipeline-tools-cli mx-app-mpr-path . > mpr.txt
chmod a+r version.txt mpr.txt
EOF
chmod +x meta.sh
