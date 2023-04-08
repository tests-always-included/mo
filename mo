#!/usr/bin/env bash
#
#/ Mo is a mustache template rendering software written in bash.  It inserts
#/ environment variables into templates.
#/
#/ Simply put, mo will change {{VARIABLE}} into the value of that
#/ environment variable.  You can use {{#VARIABLE}}content{{/VARIABLE}} to
#/ conditionally display content or iterate over the values of an array.
#/
#/ Learn more about mustache templates at https://mustache.github.io/
#/
#/ Simple usage:
#/
#/    mo [OPTIONS] filenames...
#/
#/ Options:
#/
#/    -u, --fail-not-set
#/          Fail upon expansion of an unset variable.
#/    -x, --fail-on-function
#/          Fail when a function returns a non-zero status code.
#/    -e, --false
#/          Treat the string "false" as empty for conditionals.
#/    -h, --help
#/          This message.
#/    -s=FILE, --source=FILE
#/          Load FILE into the environment before processing templates.
#/          Can be used multiple times.
#/    -d, --debug
#/          Enable debug logging to stderr.
#
# Mo is under a MIT style licence with an additional non-advertising clause.
# See LICENSE.md for the full text.
#
# This is open source!  Please feel free to contribute.
#
# https://github.com/tests-always-included/mo


# Public: Template parser function.  Writes templates to stdout.
#
# $0 - Name of the mo file, used for getting the help message.
# $@ - Filenames to parse.
#
# Options:
#
#     --allow-function-arguments
#
# Permit functions in templates to be called with additional arguments.  This
# puts template data directly in to the path of an eval statement. Use with
# caution. Not listed in the help because it only makes sense when mo is
# sourced.
#
#     -u, --fail-not-set
#
# Fail upon expansion of an unset variable.  Default behavior is to silently
# ignore and expand into empty string.
#
#     -x, --fail-on-function
#
# Fail when a function used by a template returns an error status code.
# Alternately, ou may set the MO_FAIL_ON_FUNCTION environment variable to a
# non-empty value to enable this behavior.
#
#     -e, --false
#
# Treat "false" as an empty value.  You may set the MO_FALSE_IS_EMPTY
# environment variable instead to a non-empty value to enable this behavior.
#
#     -h, --help
#
# Display a help message.
#
#     -s=FILE, --source=FILE
#
# Source a file into the environment before processing template files.
# This can be used multiple times.
#
#     --
#
# Used to indicate the end of options.  You may optionally use this when
# filenames may start with two hyphens.
#
# Mo uses the following environment variables:
#
# MO_ALLOW_FUNCTION_ARGUMENTS - When set to a non-empty value, this allows
#                  functions referenced in templates to receive additional
#                  options and arguments. This puts the content from the
#                  template directly into an eval statement. Use with extreme
#                  care.
# MO_DEBUG - When set to a non-empty value, additional debug information is
#                  written to stderr.
# MO_FUNCTION_ARGS - Arguments passed to the function.
# MO_FAIL_ON_FUNCTION - If a function returns a non-zero status code, abort
#                  with an error.
# MO_FAIL_ON_UNSET - When set to a non-empty value, expansion of an unset env
#                  variable will be aborted with an error.
# MO_FALSE_IS_EMPTY - When set to a non-empty value, the string "false" will be
#                  treated as an empty value for the purposes of conditionals.
# MO_ORIGINAL_COMMAND - Used to find the `mo` program in order to generate a
#                  help message.
#
# Returns nothing.
mo() (
    local moContent moSource moFiles moDoubleHyphens moResult

    # This function executes in a subshell; IFS is reset at the end.
    IFS=$' \n\t'

    # Enable a strict mode. This is also reset at the end.
    set -eEu -o pipefail
    moFiles=()
    moDoubleHyphens=false

    if [[ $# -gt 0 ]]; then
        for arg in "$@"; do
            if $moDoubleHyphens; then
                #: After we encounter two hyphens together, all the rest
                #: of the arguments are files.
                moFiles=(${moFiles[@]+"${moFiles[@]}"} "$arg")
            else
                case "$arg" in
                    -h|--h|--he|--hel|--help|-\?)
                        mo::usage "$0"
                        exit 0
                        ;;

                    --allow-function-arguments)
                        # shellcheck disable=SC2030
                        MO_ALLOW_FUNCTION_ARGUMENTS=true
                        ;;

                    -u | --fail-not-set)
                        # shellcheck disable=SC2030
                        MO_FAIL_ON_UNSET=true
                        ;;

                    -x | --fail-on-function)
                        # shellcheck disable=SC2030
                        MO_FAIL_ON_FUNCTION=true
                        ;;

                    -e | --false)
                        # shellcheck disable=SC2030
                        MO_FALSE_IS_EMPTY=true
                        ;;

                    -s=* | --source=*)
                        if [[ "$arg" == --source=* ]]; then
                            moSource="${arg#--source=}"
                        else
                            moSource="${arg#-s=}"
                        fi

                        if [[ -f "$moSource" ]]; then
                            # shellcheck disable=SC1090
                            . "$moSource"
                        else
                            echo "No such file: $moSource" >&2
                            exit 1
                        fi
                        ;;

                    -d | --debug)
                        MO_DEBUG=true
                        ;;

                    --)
                        #: Set a flag indicating we've encountered double hyphens
                        moDoubleHyphens=true
                        ;;

                    *)
                        #: Every arg that is not a flag or a option should be a file
                        moFiles=(${moFiles[@]+"${moFiles[@]}"} "$arg")
                        ;;
                esac
            fi
        done
    fi

    mo::debug "Debug enabled"
    mo::content moContent "${moFiles[@]}" || return 1
    mo::parse moResult "$moContent" "" "" "{{" "}}" ""
    echo -n "${moResult[0]}${moResult[1]}"
)


# Internal: Show a debug message
#
# $1 - The debug message to show
#
# Returns nothing.
mo::debug() {
    if [[ -n "${MO_DEBUG:-}" ]]; then
        echo "DEBUG: $1" >&2
    fi
}


# Internal: Show an error message and exit
#
# $1 - The error message to show
#
# Returns nothing. Exits the program.
mo::error() {
    echo "ERROR: $1" >&2
    exit ${2:-1}
}


# Internal: Displays the usage for mo.  Pulls this from the file that
# contained the `mo` function.  Can only work when the right filename
# comes is the one argument, and that only happens when `mo` is called
# with `$0` set to this file.
#
# $1 - Filename that has the help message
#
# Returns nothing.
mo::usage() {
    while read -r line; do
        if [[ "${line:0:2}" == "#/" ]]; then
            echo "${line:3}"
        fi
    done < "$MO_ORIGINAL_COMMAND"
    echo ""
    echo "MO_VERSION=$MO_VERSION"
}


# Internal: Fetches the content to parse into a variable.  Can be a list of
# partials for files or the content from stdin.
#
# $1   - Target variable to store results
# $2-@ - File names (optional), read from stdin otherwise
#
# Returns nothing.
mo::content() {
    local moContent moFilename moTarget

    moTarget=$1
    shift
    if [[ "${#@}" -gt 0 ]]; then
        moContent=""

        for moFilename in "$@"; do
            mo::debug "Using template to load content from file: $moFilename"
            #: This is so relative paths work from inside template files
            moContent="$moContent"'{{>'"$moFilename"'}}'
        done
    else
        mo::debug "Will read content from stdin"
        mo::contentFile moContent || return 1
    fi

    local "$moTarget" && mo::indirect "$moTarget" "$moContent"
}


# Internal: Read a file into a variable.
#
# $1 - Variable name to receive the file's content
# $2 - Filename to load - if empty, defaults to /dev/stdin
#
# Returns nothing.
mo::contentFile() {
    local moContent moLen

    # The subshell removes any trailing newlines.  We forcibly add
    # a dot to the content to preserve all newlines.
    # As a future optimization, it would be worth considering removing
    # cat and replacing this with a read loop.

    mo::debug "Loading content: ${2:-/dev/stdin}"
    moContent=$(cat -- "${2:-/dev/stdin}" && echo '.') || return 1
    moLen=$((${#moContent} - 1))
    moContent=${moContent:0:$moLen}  # Remove last dot

    local "$1" && mo::indirect "$1" "$moContent"
}


# Internal: Send a variable up to the parent of the caller of this function.
#
# $1 - Variable name
# $2 - Value
#
# Examples
#
#   callFunc () {
#       local "$1" && mo::indirect "$1" "the value"
#   }
#   callFunc dest
#   echo "$dest"  # writes "the value"
#
# Returns nothing.
mo::indirect() {
    unset -v "$1"
    printf -v "$1" '%s' "$2"
}


# Internal: Send an array as a variable up to caller of a function
#
# $1   - Variable name
# $2-@ - Array elements
#
# Examples
#
#   callFunc () {
#       local myArray=(one two three)
#       local "$1" && mo::indirectArray "$1" "${myArray[@]}"
#   }
#   callFunc dest
#   echo "${dest[@]}" # writes "one two three"
#
# Returns nothing.
mo::indirectArray() {
    unset -v "$1"

    # IFS must be set to a string containing space or unset in order for
    # the array slicing to work regardless of the current IFS setting on
    # bash 3.  This is detailed further at
    # https://github.com/fidian/gg-core/pull/7
    eval "$(printf "IFS= %s=(\"\${@:2}\") IFS=%q" "$1" "$IFS")"
}


# Internal: Find the first index of a substring.  If not found, sets the
# index to -1.
#
# $1 - Destination variable for the index
# $2 - Haystack
# $3 - Needle
#
# Returns nothing.
mo::findString() {
    local moPos moString

    moString=${2%%"$3"*}
    [[ "$moString" == "$2" ]] && moPos=-1 || moPos=${#moString}
    local "$1" && mo::indirect "$1" "$moPos"
}


# Internal: Split a larger string into an array of at most 2 elements.
#
# $1 - Destination variable
# $2 - String to split
# $3 - Starting delimiter
#
# Returns nothing.
mo::split() {
    local moPos moResult

    moResult=("$2")
    mo::findString moPos "${moResult[0]}" "$3"

    if [[ "$moPos" -ne -1 ]]; then
        # The first delimiter was found
        moResult[1]=${moResult[0]:$moPos + ${#3}}
        moResult[0]=${moResult[0]:0:$moPos}
    fi

    local "$1" && mo::indirectArray "$1" "${moResult[@]}"
}


# Internal: Trim leading characters
#
# $1   - Name of destination variable
# $2   - The string
#
# Returns nothing.
mo::trim() {
    local moContent moLast moR moN moT

    moContent=$2
    moLast=""
    moR=$'\r'
    moN=$'\n'
    moT=$'\t'

    while [[ "$moContent" != "$moLast" ]]; do
        moLast=$moContent
        moContent=${moContent# }
        moContent=${moContent#$moR}
        moContent=${moContent#$moN}
        moContent=${moContent#$moT}
    done

    local "$1" && mo::indirect "$1" "$moContent"
}


# Internal: Remove whitespace and content after whitespace
#
# $1 - Name of the destination variable
# $2 - The string to chomp
#
# Returns nothing.
mo::chomp() {
    local moTemp moR moN moT

    moR=$'\r'
    moN=$'\n'
    moT=$'\t'
    moTemp=${2%% *}
    moTemp=${moTemp%%$moR*}
    moTemp=${moTemp%%$moN*}
    moTemp=${moTemp%%$moT*}

    local "$1" && mo::indirect "$1" "$moTemp"
}

# Internal: Parse a block of text, writing the result to stdout. Interpolates
# mustache tags.
#
# $1 - Destination variable name to send an array
# $2 - Block of text to change
# $3 - Current name (the variable NAME for what {{.}} means)
# $4 - Current block name
# $5 - Open delimiter ("{{")
# $6 - Close delimiter ("}}")
# $7 - Fast mode (skip to end of block) if non-empty
#
#
# Array has the following elements
#     [0] - Parsed content
#     [1] - Unparsed content after the closing tag
#
# Returns nothing.
mo::parse() {
    local moContent moCurrent moOpenDelimiter moCloseDelimieter moResult moSplit moParseChunk moFastMode moStandaloneContent moRemainder
    moContent=$2
    moCurrent=$3
    moCurrentBlock=$4
    moOpenDelimiter=$5
    moCloseDelimiter=$6
    moFastMode=$7
    moResult=""
    moRemainder=""

    # This is a trick to make the standalone tag detection believe it's on a
    # new line because there's no other way to easily tell the difference
    # between a lone tag on a line and two tags where the first one evaluated
    # to an empty string. Whenever a standalone tag is encountered, this trick
    # needs to be reset to a newline.
    moStandaloneContent=$'\n'
    mo::debug "Starting parse, current: $moCurrent, ending tag: $moCurrentBlock, fast: $moFastMode"

    while [[ "${#moContent}" -gt 0 ]]; do
        # Both escaped and unescaped content are treated the same.
        mo::split moSplit "$moContent" "$moOpenDelimiter"

        if [[ "${#moSplit[@]}" -gt 1 ]]; then
            moResult="$moResult${moSplit[0]}"
            moStandaloneContent="$moStandaloneContent${moSplit[0]}"
            mo::trim moContent "${moSplit[1]}"

            case $moContent in
                '#'*)
                    # Loop, if/then, or pass content through function
                    mo::parseBlock moParseChunk "$moResult" "$moContent" "$moCurrent" "$moOpenDelimiter" "$moCloseDelimiter" false "$moStandaloneContent"
                    ;;

                '>'*)
                    # Load partial - get name of file relative to cwd
                    mo::parsePartial moParseChunk "$moResult" "$moContent" "$moCurrent" "$moCloseDelimiter" "$moFastMode" "$moStandaloneContent"
                    ;;

                '/'*)
                    # Closing tag
                    mo::parseCloseTag moParseChunk "$moResult" "$moContent" "$moCurrent" "$moCloseDelimiter" "$moCurrentBlock" "$moStandaloneContent"
                    moRemainder=${moParseChunk[3]}
                    ;;

                '^'*)
                    # Display section if named thing does not exist
                    mo::parseBlock moParseChunk "$moResult" "$moContent" "$moCurrent" "$moOpenDelimiter" "$moCloseDelimiter" true "$moStandaloneContent"
                    ;;

                '!'*)
                    # Comment - ignore the tag content entirely
                    mo::parseComment moParseChunk "$moResult" "$moContent" "$moCloseDelimiter" "$moStandaloneContent"
                ;;

                '='*)
                    # Change delimiters
                    # Any two non-whitespace sequences separated by whitespace.
                    mo::parseDelimiter moParseChunk "$moResult" "$moContent" "$moCloseDelimiter" "$moStandaloneContent"
                    moOpenDelimiter=${moParseChunk[3]}
                    moCloseDelimiter=${moParseChunk[4]}
                    ;;

                '&'*)
                    # Unescaped - mo doesn't escape
                    moContent=${moContent#&}
                    mo::trim moContent "$moContent"
                    mo::parseValue moParseChunk "$moResult" "$moContent" "$moCurrent" "$moOpenDelimiter" "$moCloseDelimiter" "$moFastMode"
                    ;;

                *)
                    # Normal environment variable, string, subexpression,
                    # current value, key, or function call
                    mo::parseValue moParseChunk "$moResult" "$moContent" "$moCurrent" "$moOpenDelimiter" "$moCloseDelimiter" "$moFastMode"
                    ;;
            esac

            moResult=${moParseChunk[0]}
            moContent=${moParseChunk[1]}

            # See above for a comment detailing this standalone trick
            moStandaloneContent=${moParseChunk[2]}
        else
            moResult="$moResult$moContent"
            moContent=""
        fi
    done

    local "$1" && mo::indirectArray "$1" "$moResult" "$moRemainder"
}


# Internal: Handle parsing a block
#
# $1 - Destination variable name, will be set to an array
# $2 - Previously parsed
# $3 - Content
# $4 - Current name (the variable NAME for what {{.}} means)
# $5 - Open delimiter
# $6 - Close delimiter
# $7 - Invert condition ("true" or "false")
# $8 - Standalone content
#
# The destination value will be an array
#     [0] = the result text
#     [1] = remaining content to parse, excluding the closing delimiter
#     [2] = standalone content trick
#
# Returns nothing
mo::parseBlock() {
    local moContent moCurrent moOpenDelimiter moCloseDelimiter moInvertBlock moTag moArgs moTemp moParseResult moResult moPrevious moStandaloneContent moArrayName moArrayIndexes moArrayIndex

    moPrevious=$2
    mo::trim moContent "${3:1}"
    moCurrent=$4
    moOpenDelimiter=$5
    moCloseDelimiter=$6
    moInvertBlock=$7
    moStandaloneContent=$8
    mo::parseValueInner moArgs "$moContent" "$moCurrent" "$moCloseDelimiter"
    moContent="${moArgs[0]#$moCloseDelimiter}"
    moArgs=("${moArgs[@]:1}")
    mo::debug "Parsing block: ${moArgs[*]}"

    if [[ "${moArgs[0]}" == "NAME" ]] && mo::isFunction "${moArgs[1]}"; then
        if mo::standaloneCheck "$moStandaloneContent" "$moContent"; then
            mo::standaloneProcessBefore moPrevious "$moPrevious"
            mo::standaloneProcessAfter moContent "$moContent"
            moStandaloneContent=$'\n'
        else
            moStandaloneContent=""
        fi

        # Get contents of block after parsing
        mo::parse moParseResult "$moContent" "$moCurrent" "${moArgs[1]}" "$moOpenDelimiter" "$moCloseDelimiter" ""

        # Pass contents to function
        mo::evaluateFunction moResult "${moParseResult[0]}" "${moArgs[@]:1}"
        moContent=${moParseResult[1]}
    elif [[ "${moArgs[0]}" == "NAME" ]] && mo::isArray "${moArgs[1]}"; then
        # Need to interate across array for each element in the array.
        if mo::standaloneCheck "$moStandaloneContent" "$moContent"; then
            mo::standaloneProcessBefore moPrevious "$moPrevious"
            mo::standaloneProcessAfter moContent "$moContent"
        fi

        moArrayName=${moArgs[1]}
        eval "moArrayIndexes=(\"\${!${moArrayName}[@]}\")"

        if [[ "${#moArrayIndexes[@]}" -lt 1 ]]; then
            # No elements
            if [[ "$moInvertBlock" == "true" ]]; then
                # Show the block
                mo::parse moParseResult "$moContent" "$moArrayName" "$moArrayName" "$moOpenDelimiter" "$moCloseDelimiter" ""
                moResult=${moParseResult[0]}
            else
                # Skip the block processing
                mo::parse moParseResult "$moContent" "$moCurrent" "$moArrayName" "$moOpenDelimiter" "$moCloseDelimiter" "FAST-EMPTY"
                moResult=""
            fi
        else
            if [[ "$moInvertBlock" == "true" ]]; then
                # Skip the block processing
                mo::parse moParseResult "$moContent" "$moCurrent" "$moArrayName" "$moOpenDelimiter" "$moCloseDelimiter" "FAST-EMPTY"
                moResult=""
            else
                moResult=""
                # Process for each element in the array
                for moArrayIndex in "${moArrayIndexes[@]}"; do
                    mo::debug "Iterate over array using element: $moArrayName.$moArrayIndex"
                    mo::parse moParseResult "$moContent" "$moArrayName.$moArrayIndex" "${moArgs[1]}" "$moOpenDelimiter" "$moCloseDelimiter" ""
                    moResult="$moResult${moParseResult[0]}"
                done
            fi
        fi

        moContent=${moParseResult[1]}
    else
        if mo::standaloneCheck "$moStandaloneContent" "$moContent"; then
            mo::standaloneProcessBefore moPrevious "$moPrevious"
            mo::standaloneProcessAfter moContent "$moContent"
        fi

        # Variable, value, or list of mixed things
        mo::evaluateListOfSingles moResult "$moCurrent" "${moArgs[@]}"

        if mo::isTruthy "$moResult" "$moInvertBlock"; then
            mo::debug "Block is truthy: $moResult"
            mo::parse moParseResult "$moContent" "$moCurrent" "${moArgs[1]}" "$moOpenDelimiter" "$moCloseDelimiter" ""
        else
            mo::debug "Block is falsy: $moResult"
            mo::parse moParseResult "$moContent" "$moCurrent" "${moArgs[1]}" "$moOpenDelimiter" "$moCloseDelimiter" "FAST-FALSY"
            moParseResult[0]=""
        fi

        moResult=${moParseResult[0]}
        moContent=${moParseResult[1]}
    fi

    local "$1" && mo::indirectArray "$1" "$moPrevious$moResult" "$moContent" "$moStandaloneContent"
}


# Internal: Handle parsing a partial
#
# $1 - Destination variable name, will be set to an array
# $2 - Previously parsed
# $3 - Content
# $4 - Current name (the variable NAME for what {{.}} means)
# $5 - Close delimiter for the current tag
# $6 - Fast mode (skip to end of block) if non-empty
# $7 - Standalone content
#
# The destination value will be an array
#     [0] = the result text
#     [1] = remaining content to parse, excluding the closing delimiter
#     [2] = standalone content trick
#
# Indentation will be applied to the entire partial's contents that are
# returned. This indentation is based on the whitespace that ends the
# previously parsed content.
#
# Returns nothing
mo::parsePartial() {
    local moContent moCurrent moCloseDelimiter moFilename moResult moFastMode moPrevious moStandaloneContent moIndentation moN moR

    moPrevious=$2
    mo::trim moContent "${3:1}"
    moCurrent=$4
    moCloseDelimiter=$5
    moFastMode=$6
    moStandaloneContent=$7
    mo::chomp moFilename "${moContent%%$moCloseDelimiter*}"
    moContent="${moContent#*$moCloseDelimiter}"
    moIndentation=""

    if mo::standaloneCheck "$moStandaloneContent" "$moContent"; then
        moN=$'\n'
        moR=$'\r'
        moIndentation="$moN${moPrevious//$moR/$moN}"
        moIndentation=${moIndentation##*$moN}
        mo::debug "Adding indentation: '$moIndentation'"
        mo::standaloneProcessBefore moPrevious "$moPrevious"
        mo::standaloneProcessAfter moContent "$moContent"
        moStandaloneContent=$'\n'
    else
        moStandaloneContent=""
    fi

    if [[ -n "$moFastMode" ]]; then
        moResult=""
        moLen=0
    else
        mo::debug "Parsing partial: $moFilename"

        # Execute in subshell to preserve current cwd and environment
        moResult=$(
            # It would be nice to remove `dirname` and use a function instead,
            # but that is difficult when only given filenames.
            cd "$(dirname -- "$moFilename")" || exit 1
            echo "$(
                if ! mo::contentFile moResult "${moFilename##*/}"; then
                    exit 1
                fi

                # Delimiters are reset when loading a new partial
                mo::parse moResult "$moResult" "$moCurrent" "" "{{" "}}" ""

                # Fix bash handling of subshells and keep trailing whitespace.
                echo -n "${moResult[0]}${moResult[1]}."
            )" || exit 1
        ) || exit 1

        if [[ ${#moResult} -eq 0 ]]; then
            mo::debug "Error detected when trying to read the file"
            exit 1
        fi

        mo::indentLines moResult "${moResult%.}" "$moIndentation"
    fi

    local "$1" && mo::indirectArray "$1" "$moPrevious$moResult" "$moContent" "$moStandaloneContent"
}


# Internal: Handle closing a tag
#
# $1 - Destination variable name, will be set to an array
# $2 - Previous content
# $3 - Content
# $4 - Current name (the variable NAME for what {{.}} means)
# $5 - Close delimiter for the current tag
# $6 - Current block being processed
# $7 - Standalone content
#
# The destination value will be an array
#     [0] = the result text ($2)
#     [1] = remaining content to parse, excluding the closing delimiter (nothing)
#     [2] = standalone content trick
#     [3] = unparsed content outside of the block (the remainder)
#
# Returns nothing.
mo::parseCloseTag() {
    local moContent moArgs moCurrent moCloseDelimiter moCurrentBlock moPrevious moStandaloneContent

    moPrevious=$2
    moContent=${3:1}
    moCurrent=$4
    moCloseDelimiter=$5
    moCurrentBlock=$6
    moStandaloneContent=$7
    mo::parseValueInner moArgs "$moContent" "$moCurrent" "$moCloseDelimiter"
    moContent="${moArgs[0]#$moCloseDelimiter}"
    mo::debug "Closing tag: ${moArgs[2]}"

    if mo::standaloneCheck "$moStandaloneContent" "$moContent"; then
        mo::standaloneProcessBefore moPrevious "$moPrevious"
        mo::standaloneProcessAfter moContent "$moContent"
        moStandaloneContent=$'\n'
    else
        moStandaloneContent=""
    fi

    if [[ -n "$moCurrentBlock" ]] && [[ "${moArgs[2]}" != "$moCurrentBlock" ]]; then
        mo::error "Unexpected close tag: ${moArgs[2]}, expected $moCurrentBlock"
    elif [[ -z "$moCurrentBlock" ]]; then
        mo::error "Unexpected close tag: ${moArgs[2]}"
    fi

    local "$1" && mo::indirectArray "$1" "$moPrevious" "" "$moStandaloneContent" "$moContent"
}


# Internal: Handle parsing a comment
#
# $1 - Destination variable name, will be set to an array
# $2 - Previous content
# $3 - Content
# $4 - Close delimiter for the current tag
# $5 - Standalone content
#
# The destination value will be an array
#     [0] = the result text
#     [1] = remaining content to parse, excluding the closing delimiter
#     [2] = standalone content trick
#
# Returns nothing
mo::parseComment() {
    local moContent moCloseDelimiter moStandaloneContent moPrevious moContent moCloseDelimiter

    moPrevious=$2
    moContent=$3
    moCloseDelimiter=$4
    moStandaloneContent=$5
    moContent=${moContent#*$moCloseDelimiter}
    mo::debug "Parsing comment"

    if mo::standaloneCheck "$moStandaloneContent" "$moContent"; then
        mo::standaloneProcessBefore moPrevious "$moPrevious"
        mo::standaloneProcessAfter moContent "$moContent"
        moStandaloneContent=$'\n'
    else
        moStandaloneContent=""
    fi

    local "$1" && mo::indirectArray "$1" "$moPrevious" "$moContent" "$moStandaloneContent"
}


# Internal: Handle parsing the change of delimiters
#
# $1 - Destination variable name, will be set to an array
# $2 - Previous content
# $3 - Content
# $4 - Close delimiter for the current tag
# $5 - Standalone content
#
# The destination value will be an array
#     [0] = the result text
#     [1] = remaining content to parse, excluding the closing delimiter
#     [2] = standalone content trick
#     [3] = new open delimiter
#     [4] = new close delimiter
#
# Returns nothing
mo::parseDelimiter() {
    local moContent moCloseDelimiter moOpen moClose moPrevious moStandaloneContent

    moPrevious=$2
    mo::trim moContent "${3#=}"
    moCloseDelimiter=$4
    moStandaloneContent=$5
    mo::chomp moOpen "$moContent"
    moContent=${moContent:${#moOpen}}
    mo::trim moContent "$moContent"
    moClose="${moContent%%=$moCloseDelimiter*}"
    moContent=${moContent#*=$moCloseDelimiter}
    mo::debug "Parsing delimiters: $moOpen $moClose"

    if mo::standaloneCheck "$moStandaloneContent" "$moContent"; then
        mo::standaloneProcessBefore moPrevious "$moPrevious"
        mo::standaloneProcessAfter moContent "$moContent"
        moStandaloneContent=$'\n'
    else
        moStandaloneContent=""
    fi

    local "$1" && mo::indirectArray "$1" "$moPrevious" "$moContent" "$moStandaloneContent" "$moOpen" "$moClose"
}


# Internal: Handle parsing value or function call
#
# $1 - Destination variable name, will be set to an array
# $2 - Previous content
# $3 - Content
# $4 - Current name (the variable NAME for what {{.}} means)
# $5 - Open delimiter for the current tag
# $6 - Close delimiter for the current tag
# $7 - Fast mode (skip to end of block) if non-empty
#
# The destination value will be an array
#     [0] = the result text
#     [1] = remaining content to parse, excluding the closing delimiter
#     [2] = standalone content trick
#
# Returns nothing
mo::parseValue() {
    local moContent moContentOriginal moOpenDelimiter moCurrent moCloseDelimiter moArgs moResult moFastMode moPrevious

    moPrevious=$2
    moContentOriginal=$3
    moCurrent=$4
    moOpenDelimiter=$5
    moCloseDelimiter=$6
    moFastMode=$7
    mo::trim moContent "${moContentOriginal#$moOpenDelimiter}"

    mo::parseValueInner moArgs "$moContent" "$moCurrent" "$moCloseDelimiter"
    moContent=${moArgs[0]}
    moArgs=("${moArgs[@]:1}")

    if [[ -n "$moFastMode" ]]; then
        moResult=""
    else
        mo::evaluate moResult "$moCurrent" "${moArgs[@]}"
    fi

    if [[ "${moContent:0:${#moCloseDelimiter}}" != "$moCloseDelimiter" ]]; then
        mo::error "Did not find closing tag near: $moContentOriginal"
    fi

    moContent=${moContent:${#moCloseDelimiter}}

    local "$1" && mo::indirectArray "$1" "$moPrevious$moResult" "$moContent" ""
}


# Internal: Handle parsing value or function call inside of delimiters
#
# $1 - Destination variable name, will be set to an array
# $2 - Content
# $3 - Current name (the variable NAME for what {{.}} means)
# $4 - Close delimiter for the current tag
#
# The destination value will be an array
#     [0] = remaining content to parse, including the closing delimiter
#     [1-*] = a list of argument type, argument name/value
#
# Returns nothing
mo::parseValueInner() {
    local moContent moCurrent moCloseDelimiter moArgs moArgResult moResult

    moContent=$2
    moCurrent=$3
    moCloseDelimiter=$4
    moArgs=()

    while [[ "$moContent" != "$moCloseDelimiter"* ]] && [[ "$moContent" != "}"* ]] && [[ "$moContent" != ")"* ]] && [[ -n "$moContent" ]]; do
        mo::getArgument moArgResult "$moCurrent" "$moContent" "$moCloseDelimiter"
        moArgs=(${moArgs[@]+"${moArgs[@]}"} "${moArgResult[0]}" "${moArgResult[1]}")
        mo::trim moContent "${moArgResult[2]}"
    done

    mo::debug "Parsed arguments: ${moArgs[*]}"

    local "$1" && mo::indirectArray "$1" "$moContent" ${moArgs[@]+"${moArgs[@]}"}
}


# Internal: Retrieve an argument name
#
# $1 - Destination variable name. Will be an array.
# $2 - Content
# $3 - Closing delimiter
#
# The array will have the following elements
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#     [2] = unparsed content
#
# Returns nothing
mo::getArgument() {
    local moContent moCurrent moClosingDelimiter moArg

    moCurrent=$2
    moContent=$3
    moClosingDelimiter=$4

    case "$moContent" in
        '{'*)
            mo::getArgumentBrace moArg "$moContent" "$moCurrent" "$moClosingDelimiter"
            ;;

        '('*)
            mo::getArgumentParenthesis moArg "$moContent" "$moCurrent" "$moClosingDelimiter"
            ;;

        '"'*)
            mo::getArgumentDoubleQuote moArg "$moContent"
            ;;

        "'"*)
            mo::getArgumentSingleQuote moArg "$moContent"
            ;;

        *)
            mo::getArgumentDefault moArg "$moContent" "$moClosingDelimiter"
    esac

    mo::debug "Found argument: ${moArg[0]} ${moArg[1]}"

    local "$1" && mo::indirectArray "$1" "${moArg[0]}" "${moArg[1]}" "${moArg[2]}"
}


# Internal: Get an argument, which is the result of a subexpression as a VALUE
#
# $1 - Destination variable name, an array with two elements
# $2 - Content
# $3 - Current name (the variable NAME for what {{.}} means)
# $4 - Close delimiter for the current tag
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#     [2] = unparsed content
#
# Returns nothing.
mo::getArgumentBrace() {
    local moResult moContent moCurrent moCloseDelimiter moArgs

    mo::trim moContent "${2:1}"
    moCurrent=$3
    moCloseDelimiter=$4
    mo::parseValueInner moResult "$moContent" "$moCurrent" "$moCloseDelimiter"
    moContent="${moResult[0]}"
    moArgs=("${moResult[@]:1}")
    mo::evaluate moResult "$moCurrent" "${moArgs[@]}"

    if [[ "${moContent:0:1}" != "}" ]]; then
        mo::error "Unbalanced brace near ${2:0:20}"
    fi

    mo::trim moContent "${moContent:1}"

    local "$1" && mo::indirectArray "$1" "VALUE" "${moResult[0]}" "$moContent"
}


# Internal: Get an argument, which is the result of a subexpression as a NAME
#
# $1 - Destination variable name, an array with two elements
# $2 - Content
# $3 - Current name (the variable NAME for what {{.}} means)
# $4 - Close delimiter for the current tag
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#     [2] = unparsed content
#
# Returns nothing.
mo::getArgumentParenthesis() {
    local moResult moContent moCurrent moCloseDelimiter

    mo::trim moContent "${2:1}"
    moCurrent=$3
    moCloseDelimiter=$4
    mo::parseValueInner moResult "$moContent" "$moCurrent" "$moCloseDelimiter"
    moContent="${moResult[1]}"

    if [[ "${moContent:0:1}" != ")" ]]; then
        mo::error "Unbalanced parenthesis near ${2:0:20}"
    fi

    mo::trim moContent "${moContent:1}"

    local "$1" && mo::indirectArray "$1" "NAME" "${moResult[0]}" "$moContent"
}


# Internal: Get an argument in a double quoted string
#
# $1 - Destination variable name, an array with two elements
# $2 - Content
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#     [2] = unparsed content
#
# Returns nothing.
mo::getArgumentDoubleQuote() {
    local moTemp moContent

    moTemp=""
    moContent=${2:1}

    while [[ "${moContent:0:1}" != '"' ]]; do
        case "$moContent" in
            \\n)
                moTemp="$moTemp"$'\n'
                moContent=${moContent:2}
                ;;

            \\r)
                moTemp="$moTemp"$'\r'
                moContent=${moContent:2}
                ;;

            \\t)
                moTemp="$moTemp"$'\t'
                moContent=${moContent:2}
                ;;

            \\*)
                moTemp="$moTemp${moContent:1:1}"
                moContent=${moContent:2}
                ;;

            *)
                moTemp="$moTemp${moContent:0:1}"
                moContent=${moContent:1}
                ;;
        esac

        if [[ -z "$moContent" ]]; then
            mo::error "Found starting double quote but no closing double quote"
        fi
    done

    mo::debug "Parsed double quoted value: $moTemp"

    local "$1" && mo::indirectArray "$1" "VALUE" "$moTemp" "${moContent:1}"
}


# Internal: Get an argument in a single quoted string
#
# $1 - Destination variable name, an array with two elements
# $2 - Content
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#     [2] = unparsed content
#
# Returns nothing.
mo::getArgumentSingleQuote() {
    local moTemp moContent

    moTemp=""
    moContent=${2:1}

    while [[ "${moContent:0:1}" != "'" ]]; do
        moTemp="$moTemp${moContent:0:1}"
        moContent=${moContent:1}

        if [[ -z "$moContent" ]]; then
            mo::error "Found starting single quote but no closing single quote"
        fi
    done

    mo::debug "Parsed single quoted value: $moTemp"

    local "$1" && mo::indirectArray "$1" "VALUE" "$moTemp" "${moContent:1}"
}


# Internal: Get an argument that is a simple variable name
#
# $1 - Destination variable name, an array with two elements
# $2 - Content
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#     [2] = unparsed content
#
# Returns nothing.
mo::getArgumentDefault() {
    local moTemp moContent

    moTemp=$2
    mo::chomp moTemp "${moTemp%%$3*}"
    moTemp=${moTemp%%)*}
    moTemp=${moTemp%%\}*}
    moContent=${2:${#moTemp}}
    mo::debug "Parsed default argument: $moTemp"

    local "$1" && mo::indirectArray "$1" "NAME" "$moTemp" "$moContent"
}


# Internal: Determine if the given name is a defined function.
#
# $1 - Function name to check
#
# Be extremely careful.  Even if strict mode is enabled, it is not honored
# in newer versions of Bash.  Any errors that crop up here will not be
# caught automatically.
#
# Examples
#
#   moo () {
#       echo "This is a function"
#   }
#   if mo::isFunction moo; then
#       echo "moo is a defined function"
#   fi
#
# Returns 0 if the name is a function, 1 otherwise.
mo::isFunction() {
    if declare -F "$1" &> /dev/null; then
        return 0
    fi

    return 1
}


# Internal: Determine if a given environment variable exists and if it is
# an array.
#
# $1 - Name of environment variable
#
# Be extremely careful.  Even if strict mode is enabled, it is not honored
# in newer versions of Bash.  Any errors that crop up here will not be
# caught automatically.
#
# Examples
#
#   var=(abc)
#   if moIsArray var; then
#      echo "This is an array"
#      echo "Make sure you don't accidentally use \$var"
#   fi
#
# Returns 0 if the name is not empty, 1 otherwise.
mo::isArray() {
    # Namespace this variable so we don't conflict with what we're testing.
    local moTestResult

    moTestResult=$(declare -p "$1" 2>/dev/null) || return 1
    [[ "${moTestResult:0:10}" == "declare -a" ]] && return 0
    [[ "${moTestResult:0:10}" == "declare -A" ]] && return 0

    return 1
}


# Internal: Determine if a variable is assigned, even if it is assigned an empty
# value.
#
# $1 - Variable name to check.
#
# Can not use logic like this in case invalid variable names are passed.
#     [[ "${!1-a}" == "${!1-b}" ]]
#
# Returns true (0) if the variable is set, 1 if the variable is unset.
mo::isVarSet() {
    if ! declare -p "$1" &> /dev/null; then
        return 1
    fi

    return 0
}


# Internal: Determine if a value is considered truthy.
#
# $1 - The value to test
# $2 - Invert the value, either "true" or "false"
#
# Returns true (0) if truthy, 1 otherwise.
mo::isTruthy() {
    local moTruthy

    moTruthy=true

    if [[ -z "${1-}" ]]; then
        moTruthy=false
    elif [[ -n "${MO_FALSE_IS_EMPTY-}" ]] && [[ "${1-}" == "false" ]]; then
        moTruthy=false
    fi

    # XOR the results
    # moTruthy  inverse  desiredResult
    # true      false    true
    # true      true     false
    # false     false    false
    # false     true     true
    if [[ "$moTruthy" == "$2" ]]; then
        mo::debug "Value is falsy, test result: $moTruthy inverse: $2"
        return 1
    fi

    mo::debug "Value is truthy, test result: $moTruthy inverse: $2"
    return 0
}


# Internal: Convert an argument list to values
#
# $1 - Destination variable name
# $2 - Current name (the variable NAME for what {{.}} means)
# $3-$* - A list of argument types and argument name/value.
#
# Sample call:
#
#     mo::evaluate dest NAME username VALUE abc123
#
# Returns nothing.
mo::evaluate() {
    local moResult moTarget moCurrent moFunction moArgs moTemp

    moTarget=$1
    moCurrent=$2
    shift 2

    if [[ "$1" == "NAME" ]] && mo::isFunction "$2"; then
        # Special case - if the first argument is a function, then the rest are
        # passed to the function.
        moFunction=$2
        mo::evaluateFunction moResult "" "${@:2}"
    else
        mo::evaluateListOfSingles moResult "$moCurrent" ${@+"$@"}
    fi

    local "$moTarget" && mo::indirect "$moTarget" "$moResult"
}


# Internal: Convert an argument list to individual values.
#
# $1 - Destination variable name
# $2 - Current name (the variable NAME for what {{.}} means)
# $3-$* - A list of argument types and argument name/value.
#
# This assumes each value is separate from the rest. In contrast, mo::evaluate
# will pass all arguments to a function if the first value is a function.
#
# Sample call:
#
#     mo::evaluateListOfSingles dest NAME username VALUE abc123
#
# Returns nothing.
mo::evaluateListOfSingles() {
    local moResult moTarget moTemp moCurrent

    moTarget=$1
    moCurrent=$2
    shift 2
    moResult=""

    while [[ $# -gt 1 ]]; do
        mo::evaluateSingle moTemp "$moCurrent" "$1" "$2"
        moResult="$moResult$moTemp"
        shift 2
    done

    mo::debug "Evaluated list of singles: $moResult"

    local "$moTarget" && mo::indirect "$moTarget" "$moResult"
}


# Internal: Evaluate a single argument
#
# $1 - Name of variable for result
# $2 - Current name (the variable NAME for what {{.}} means)
# $3 - Type of argument, either NAME or VALUE
# $4 - Argument
#
# Returns nothing
mo::evaluateSingle() {
    local moResult moCurrent moVarNameParts moType moArg

    moCurrent=$2
    moType=$3
    moArg=$4
    mo::debug "Evaluating $moType: $moArg"

    if [[ "$moType" == "VALUE" ]]; then
        moResult=$moArg
    elif [[ "$moArg" == "." ]]; then
        mo::evaluateVariable moResult "$moCurrent"
    elif [[ "$moArg" == "@key" ]]; then
        mo::evaluateKey moResult "$moCurrent"
    elif mo::isFunction "$moArg"; then
        mo::evaluateFunction moResult "" "$moArg"
    else
        mo::split moVarNameParts "$moArg" .
        mo::evaluateVariable moResult "$moArg"
    fi

    local "$1" && mo::indirect "$1" "$moResult"
}


# Internal: Return the value for @key based on current's name
#
# $1 - Name of variable for result
# $2 - Current name (the variable NAME for what {{.}} means)
#
# Returns nothing
mo::evaluateKey() {
    local moCurrent moResult

    moCurrent=$2

    if [[ "$moCurrent" == *.* ]]; then
        moResult="${moCurrent#*.}"
    else
        moResult="${moCurrent}"
    fi

    local "$1" && mo::indirect "$1" "$moResult"
}


# Internal: Handle a variable name
#
# $1 - Destination variable name
# $2 - Variable name
#
# Returns nothing.
mo::evaluateVariable() {
    local moResult moCurrent moArg moNameParts moJoined moKey moValue

    moArg=$2
    moResult=""
    mo::split moNameParts "$moArg" .

    if [[ -z "${moNameParts[1]-}" ]]; then
        if mo::isArray "$moArg"; then
            eval mo::join moResult "," "\${$moArg[@]}"
        else
            # shellcheck disable=SC2031
            if mo::isVarSet "$moArg"; then
                moResult="${!moArg}"
            elif [[ -n "${MO_FAIL_ON_UNSET-}" ]]; then
                mo::error "Environment variable not set: $moArg"
            fi
        fi
    else
        if mo::isArray "${moNameParts[0]}"; then
            eval "moResult=\"\${${moNameParts[0]}[${moNameParts[1]%%.*}]}\""
        else
            mo::error "Unable to index a scalar as an array: $moArg"
        fi
    fi

    local $1 && mo::indirect "$1" "$moResult"
}


# Internal: Join / implode an array
#
# $1    - Variable name to receive the joined content
# $2    - Joiner
# $3-$* - Elements to join
#
# Returns nothing.
moJoin() {
    local joiner part result target

    target=$1
    joiner=$2
    result=$3
    shift 3

    for part in "$@"; do
        result="$result$joiner$part"
    done

    local "$target" && mo::indirect "$target" "$result"
}


# Internal: Call a function.
#
# $1 - Variable for output
# $2 - Content to pass
# $3 - Function to call
# $4-$* - Additional arguments as list of type, value/name
#
# Returns nothing.
mo::evaluateFunction() {
    local moArgs moContent moFunctionArgs moFunctionResult moTarget moFunction moTemp moFunctionCall

    moTarget=$1
    moContent=$2
    moFunction=$3
    shift 3
    moArgs=()

    while [[ $# -gt 1 ]]; do
        mo::evaluateSingle moTemp "$moCurrent" "$1" "$2"
        moArgs=(${moArgs[@]+"${moArgs[@]}"} "$moTemp")
        shift 2
    done

    mo::escape moFunctionCall "$moFunction"

    # shellcheck disable=SC2031
    if [[ -n "${MO_ALLOW_FUNCTION_ARGUMENTS-}" ]]; then
        mo::debug "Function arguments are allowed"

        for moTemp in "${moArgs[@]}"; do
            mo::escape moTemp "$moTemp"
            moFunctionCall="$moFunctionCall $moTemp"
        done
    fi

    mo::debug "Calling function: $moFunctionCall"
    moContent=$(export MO_FUNCTION_ARGS=("${moArgs[@]}"); echo -n "$moContent" | eval "$moFunctionCall") || {
        moFunctionResult=$?
        # shellcheck disable=SC2031
        if [[ -n "${MO_FAIL_ON_FUNCTION-}" && "$moFunctionResult" != 0 ]]; then
            mo::error "Function '$moFunction' with args (${moArgs[@]+"${moArgs[@]}"}) failed with status code $moFunctionResult" "$moFunctionResult"
        fi
    }

    # shellcheck disable=SC2031
    local "$moTarget" && mo::indirect "$moTarget" "$moContent"
}


# Internal: Check if a tag appears to have only whitespace before it and after
# it on a line. There must be a new line before (see the trick in mo::parse)
# and there must be a newline after or the end of a string
#
# $1 - Standalone content that was processed in this loop
# $2 - Content after the tag
#
# Returns 0 if this is a standalone tag, 1 otherwise.
mo::standaloneCheck() {
    local moContent moN moR moT

    moN=$'\n'
    moR=$'\r'
    moT=$'\t'

    # Check the content before
    moContent=${1//$moR/$moN}

    if [[ "$moContent" != *"$moN"* ]]; then
        mo::debug "Not a standalone tag - no newline before"
        return 1
    fi

    moContent=${moContent##*$moN}
    moContent=${moContent//$moT/}
    moContent=${moContent// /}

    if [[ -n "$moContent" ]]; then
        mo::debug "Not a standalone tag - non-whitespace detected before tag"
        return 1
    fi

    # Check the content after
    moContent=${2//$moR/$moN}
    moContent=${moContent%%$moN*}
    moContent=${moContent//$moT/}
    moContent=${moContent// /}

    if [[ -n "$moContent" ]]; then
        mo::debug "Not a standalone tag - non-whitespace detected after tag"
        return 1
    fi

    return 0
}


# Internal: Process content before a tag to remove whitespace but not the newline.
#
# $1 - Destination variable
# $2 - Content
#
# Returns nothing.
mo::standaloneProcessBefore() {
    local moContent moLast moT

    moContent=$2
    moT=$'\t'
    moLast=

    mo::debug "Standalone tag - processing content before tag"

    while [[ "$moLast" != "$moContent" ]]; do
        moLast=$moContent
        moContent=${moContent% }
        moContent=${moContent%$moT}
    done

    local "$1" && mo::indirect "$1" "$moContent"
}


# Internal: Process content after a tag to remove whitespace including a single newline.
#
# $1 - Destination variable
# $2 - Content
#
# Returns nothing.
mo::standaloneProcessAfter() {
    local moContent moLast moT moR moN

    moContent=$2
    moT=$'\t'
    moR=$'\r'
    moN=$'\n'
    moLast=

    mo::debug "Standalone tag - processing content after tag"

    while [[ "$moLast" != "$moContent" ]]; do
        moLast=$moContent
        moContent=${moContent# }
        moContent=${moContent#$moT}
    done

    moContent=${moContent#$moR}
    moContent=${moContent#$moN}

    local "$1" && mo::indirect "$1" "$moContent"
}


# Internal: Apply indentation before any line that has content
#
# $1 - Destination variable
# $2 - The content to indent
# $3 - The indentation string
#
# Returns nothing.
mo::indentLines() {
    local moContent moIndentation moResult moN moR moChunk

    moContent=$2
    moIndentation=$3
    moResult=""
    moN=$'\n'
    moR=$'\r'

    if [[ -z "$moIndentation" ]] || [[ -z "$moContent" ]]; then
        mo::debug "Not applying indentation, indentation ${#moIndentation} bytes, content ${#moContent} bytes"
        moResult=$moContent
    else
        mo::debug "Applying indentation: '${moIndentation}'"

        while [[ -n "$moContent" ]]; do
            moChunk=${moContent%%$moN*}
            moChunk=${moChunk%%$moR*}
            moContent=${moContent:${#moChunk}}

            if [[ -n "$moChunk" ]]; then
                moResult="$moResult$moIndentation$moChunk"
            fi

            moResult="$moResult${moContent:0:1}"
            moContent=${moContent:1}
        done
    fi

    local "$1" && mo::indirect "$1" "$moResult"
}


# Internal: Escape a value
#
# $1 - Destination variable name
# $2 - Value to escape
#
# Returns nothing
mo::escape() {
    local moResult

    moResult=$2
    moResult=$(declare -p moResult)
    moResult=${moResult#*=}

    local "$1" && mo::indirect "$1" "$moResult"
}


# Save the original command's path for usage later
MO_ORIGINAL_COMMAND="$(cd "${BASH_SOURCE[0]%/*}" || exit 1; pwd)/${BASH_SOURCE[0]##*/}"
MO_VERSION="3.0.0"

# If sourced, load all functions.
# If executed, perform the actions as expected.
if [[ "$0" == "${BASH_SOURCE[0]}" ]] || [[ -z "${BASH_SOURCE[0]}" ]]; then
    mo "$@"
fi
