#!/bin/sh
# CI runtime test for gh package
# Called by Entware CI as: test.sh <PKG_NAME> <PKG_VERSION>

case "$1" in
    gh)
        gh --version 2>&1 | grep -q "$2" && \
            echo "PASS: gh --version contains $2" || \
            { echo "FAIL: gh --version did not match $2"; exit 1; }
        ;;
esac
