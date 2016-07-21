#!/usr/bin/env bash

cd "${0%/*}"
cat <<EOF | ../mo --source=source.vars
{{VAR}}
{{#ARR}}
* {{.}}
{{/ARR}}
{{ASSOC_ARR.a}} {{ASSOC_ARR.b}}
EOF
