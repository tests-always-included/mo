#!/usr/bin/env bash
# This should display a message indicating that the file --help
# could not be found.  It should not display a help messsage.
cd "${0%/*}"
../mo -- --help 2>&1
