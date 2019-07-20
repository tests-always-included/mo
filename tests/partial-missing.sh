#!/usr/bin/env bash

cd "${0%/*}"
../mo -u partial-missing.template 2>&1
returned=$?

if [[ $returned -ne 1 ]]; then
    echo "Did not return 1. Instead, returned $returned."
fi
