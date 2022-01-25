#!/usr/bin/env bash

source ./mo
moExport
bash << "EOF"
moUnexport
bash << "EOF2"
source ./run-basic-tests
if ! (( FAIL )); then
    exit 1
fi
EOF2
EOF
