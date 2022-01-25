#!/usr/bin/env bash

list_function_names() {
    declare -F | while read l; do echo ${l/#* /}; done | sort
}

f_orig=$(list_function_names)

source ./mo
moUnload

f=$(list_function_names)

diff <(echo $f_orig | tr ' ' '\n') <(echo $f | tr ' ' '\n')
