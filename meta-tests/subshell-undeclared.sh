#!/usr/bin/env bash

bash << "EOF"
source ./run-basic-tests
if ! (( FAIL )); then
    exit 1
fi
EOF
