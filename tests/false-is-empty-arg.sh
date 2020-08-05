#!/usr/bin/env bash

cd "${0%/*}" || exit 1
USER=j.doe ADMIN=false ../mo --false false-is-empty-arg.template
