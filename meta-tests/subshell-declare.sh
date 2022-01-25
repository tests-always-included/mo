#!/usr/bin/env bash

source ./mo
cat <(moDeclare) - << "EOF" | bash
source ./run-basic-tests
if (( FAIL )); then
    exit 1
fi
EOF
