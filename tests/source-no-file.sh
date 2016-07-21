#!/usr/bin/env bash

cd "${0%/*}"
echo "Do not display this" | ../mo --source= 2>&1

if [[ $? -ne 1 ]]; then
    echo "Did not return 1"
fi
