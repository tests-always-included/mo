#!/usr/bin/env bash

source ./mo
moExport
bash << "EOF"
bash << "EOF2"
bash << "EOF3"
bash << "EOF4"
source ./run-basic-tests
if (( FAIL )); then
exit 1
fi
EOF4
EOF3
EOF2
EOF
