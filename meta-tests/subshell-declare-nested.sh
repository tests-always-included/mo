#!/usr/bin/env bash

source ./mo
cat <(moDeclare) - << "EOF" | bash
cat <(moDeclare) - << "EOF2" | bash
cat <(moDeclare) - << "EOF3" | bash
cat <(moDeclare) - << "EOF4" | bash
source ./run-basic-tests
if (( FAIL )); then
    exit 1
fi
EOF4
EOF3
EOF2
EOF
