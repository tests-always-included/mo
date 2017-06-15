#!/usr/bin/env bash

cd "${0%/*}"
unset __NO_SUCH_VAR
echo "This will fail: {{__NO_SUCH_VAR}}" | ../mo --fail-not-set 2>&1

if [[ $? -ne 1 ]]; then
    echo "Did not return 1"
fi
