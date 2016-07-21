#!/usr/bin/env bash

cd "${0%/*}"
cat <<EOF | ../mo --source=source.vars
{{VAR}}
{{#ARR}}
* {{.}}
{{/ARR}}
{{ASSOC_ARR.a}} {{ASSOC_ARR.b}}
EOF


# Prints the string should mo NOT fail. Meaning that the output will not match
# tests/source.expected and therefore the test will fail.

../mo --source=a/non/existent/file files >/dev/null 2>&1
[[ "$?" -ne 1 ]] && echo "mo accepted a non existent file"
