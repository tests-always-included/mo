#!/usr/bin/env bash

cd "${0%/*}" || exit 1
cat <<EOF | ../mo --source=source-multiple-1.vars --source=source-multiple-2.vars
A: {{A}}
B: {{B}}
C: {{C}}
EOF
