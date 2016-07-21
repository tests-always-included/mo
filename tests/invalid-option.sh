#!/usr/bin/env bash
# This should display a message indicating that the file --something
# could not be found.
cd "${0%/*}"
../mo --something 2>&1
