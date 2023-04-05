#!/usr/bin/env bash

cd "${0%/*}" || exit 1

_CTRL_Z_=$'\cZ'

{
    IFS=$'\n'"${_CTRL_Z_}" read -r -d "${_CTRL_Z_}" STDERR;
    IFS=$'\n'"${_CTRL_Z_}" read -r -d "${_CTRL_Z_}" STDOUT;
} <<EOF
$((printf "${_CTRL_Z_}%s${_CTRL_Z_}%d${_CTRL_Z_}" "$(\
cat <<EOMO | ../mo --strict --source=strict-source-multiple-1.vars --source=strict-source-multiple-2.vars
{{#BASH_VERSINFO}}Illegal{{/BASH_VERSINFO}}
{{BASH_VERSINFO.0}}
A: {{A}}
B: {{B}}
C: {{C}}
D: {{D.0}}
D: {{#D}}{{.}}{{/D}}
EOMO
)" "${?}" 1>&2) 2>&1)
EOF

echo "${STDOUT[@]}"

expectedErr="Illegal variable access BASH_VERSINFO"
if [[ ! "$STDERR" =~ "$expectedErr" ]]; then
    echo "STDERR should have contained an illegal variable access message:"
    echo "$STDERR"
fi

exit 0
