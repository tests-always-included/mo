#!/usr/bin/env bash

bash << "EOF"
source ./mo
source ./run-basic-tests
if (( FAIL )); then
    exit 1
fi
