#!/usr/bin/env bash

source ./mo
moExport
env --ignore-environment << "EOF"
source ./run-basic-tests
if ! (( FAIL )); then
    exit 1
fi
EOF