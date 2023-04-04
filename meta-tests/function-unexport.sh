#!/usr/bin/env bash

list_function_names() {
    declare -F | while read l; do echo ${l/#* /}; done | sort
}
declare -xf list_function_names

f_orig=$(list_function_names)

source ./mo
moExport
moUnexport

f=$(bash -c list_function_names)

diff <(echo $f_orig | tr ' ' '\n') <(echo $f | tr ' ' '\n')
