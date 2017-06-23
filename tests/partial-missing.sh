#!/usr/bin/env bash

cd "${0%/*}"
../mo partial-missing.template 2>&1

if [[ $? -ne 1 ]]; then
    echo "Did not return 1"
fi
