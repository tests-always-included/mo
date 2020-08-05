#!/usr/bin/env bash

cd "${0%/*}" || exit 1

failFunction() {
    false
}

# Must be sourced to use functions
# shellcheck disable=SC1091
. ../mo
mo --fail-on-function 2>&1 <<EOF
Fail on function? {{failFunction}}
EOF

if [[ $? -ne 1 ]]; then
    echo "Did not return 1"
fi
