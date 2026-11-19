#!/usr/bin/env bash
# Installs a pinned Conftest release on a Linux x86_64 runner after verifying its checksum.
set -euo pipefail
V="${CONFTEST_VERSION:-0.71.1}"
D=$(mktemp -d); cd "$D"
base="https://github.com/open-policy-agent/conftest/releases/download/v$V"
curl -sSfLO "$base/conftest_${V}_Linux_x86_64.tar.gz"
curl -sSfLO "$base/checksums.txt"
grep " conftest_${V}_Linux_x86_64.tar.gz\$" checksums.txt | sha256sum -c -
tar xzf "conftest_${V}_Linux_x86_64.tar.gz" conftest
sudo install -m 0755 conftest /usr/local/bin/conftest
conftest --version
