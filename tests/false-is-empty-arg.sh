#!/usr/bin/env bash

cd "${0%/*}"
USER=j.doe ADMIN=false ../mo --false false-is-empty-arg.template
