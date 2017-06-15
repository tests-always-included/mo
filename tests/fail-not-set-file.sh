#!/usr/bin/env bash

cd "${0%/*}"
unset __NO_SUCH_VAR
../mo --fail-not-set ./fail-not-set-file.template 2>&1

if [[ $? -ne 1 ]]; then
    echo "Did not return 1"
fi
