#!/usr/bin/env bash

list_function_names() {
    declare -F | while read l; do echo ${l/#* /}; done | sort
}

f_orig=$(list_function_names)

source ./mo

f=$(list_function_names)

f_new=$(comm -13 <(echo $f_orig | tr ' ' '\n') <(echo $f | tr ' ' '\n'))

diff <(echo $f_new | tr ' ' '\n') <(moListFuncs | sort)
