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
#/    --allow-function-arguments
#/          Permit functions to be called with additional arguments. Otherwise,
#/          the only way to get access to the arguments is to use the
#/          MO_FUNCTION_ARGS environment variable.
#/    -d, --debug
#/          Enable debug logging to stderr.
#/    -u, --fail-not-set
#/          Fail upon expansion of an unset variable. Will silently ignore by
#/          default. Alternately, set MO_FAIL_ON_UNSET to a non-empty value.
#/    -x, --fail-on-function
#/          Fail when a function returns a non-zero status code instead of
#/          silently ignoring it. Alternately, set MO_FAIL_ON_FUNCTION to a
#/          non-empty value.
#/    -f, --fail-on-file
#/          Fail when a file (from command-line or partial) does not exist.
#/          Alternately, set MO_FAIL_ON_FILE to a non-empty value.
#/    -e, --false
#/          Treat the string "false" as empty for conditionals. Alternately,
#/          set MO_FALSE_IS_EMPTY to a non-empty value.
#/    -h, --help
#/          This message.
#/    -s=FILE, --source=FILE
#/          Load FILE into the environment before processing templates.
#/          Can be used multiple times.
#/    --    Indicate the end of options. All arguments after this will be
#/          treated as filenames only. Use when filenames may start with
#/          hyphens.
#/
#/ Mo uses the following environment variables:
#/
#/ MO_ALLOW_FUNCTION_ARGUMENTS - When set to a non-empty value, this allows
#/     functions referenced in templates to receive additional options and
#/     arguments.
#/ MO_CLOSE_DELIMITER - The string used when closing a tag. Defaults to "}}".
#/ MO_DEBUG - When set to a non-empty value, additional debug information is
#/     written to stderr.
#/ MO_FUNCTION_ARGS - Arguments passed to the function.
#/ MO_FAIL_ON_FILE - If a filename from the command-line is missing or a
#/     partial does not exist, abort with an error.
#/ MO_FAIL_ON_FUNCTION - If a function returns a non-zero status code, abort
#/     with an error.
#/ MO_FAIL_ON_UNSET - When set to a non-empty value, expansion of an unset env
#/     variable will be aborted with an error.
#/ MO_FALSE_IS_EMPTY - When set to a non-empty value, the string "false" will
#/     be treated as an empty value for the purposes of conditionals.
#/ MO_OPEN_DELIMITER - The string used when opening a tag. Defaults to "{{".
#/ MO_ORIGINAL_COMMAND - Used to find the `mo` program in order to generate a
#/     help message.
#/ MO_PARSED - Content that has made it through the template engine.
#/ MO_STANDALONE_CONTENT - The content that preceeded the current tag. When a
#/     standalone tag is encountered, this is checked to see if it only
#/     contains whitespace. If this and the whitespace condition after a tag is
#/     met, then this will be reset to $'\n'.
#/ MO_UNPARSED - Template content yet to make it through the parser.
#/
#/ Mo is under a MIT style licence with an additional non-advertising clause.
#/ See LICENSE.md for the full text.
#/
#/ This is open source!  Please feel free to contribute.
#/
#/ https://github.com/tests-always-included/mo

# Disable these warnings for the entire file
#
# VAR_NAME was modified in a subshell. That change might be lost.
# shellcheck disable=SC2031
#
# Modification of VAR_NAME is local (to subshell caused by (..) group).
# shellcheck disable=SC2030

# Public: Template parser function.  Writes templates to stdout.
#
# $0 - Name of the mo file, used for getting the help message.
# $@ - Filenames to parse.
#
# See the comment above for details.
#
# Returns nothing.
mo() (
    local moSource moFiles moDoubleHyphens

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
                        MO_ALLOW_FUNCTION_ARGUMENTS=true
                        ;;

                    -u | --fail-not-set)
                        MO_FAIL_ON_UNSET=true
                        ;;

                    -x | --fail-on-function)
                        MO_FAIL_ON_FUNCTION=true
                        ;;

                    -p | --fail-on-file)
                        MO_FAIL_ON_FILE=true
                        ;;

                    -e | --false)
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

                    -*)
                        mo::error "Unknown option: $arg (See --help for options)"
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
    MO_OPEN_DELIMITER="${MO_OPEN_DELIMITER:-"{{"}"
    MO_CLOSE_DELIMITER="${MO_CLOSE_DELIMITER:-"}}"}"

    # The standalone content is a trick to make the standalone tag detection
    # possible. When it's set to content with a newline and if the tag supports
    # it, the standalone content check happens. This check ensures only
    # whitespace is after the last newline up to the tag, and only whitespace
    # is after the tag up to the next newline. If that is the case, remove
    # whitespace and the trailing newline. By setting this to $'\n', we're
    # saying we are at the beginning of content.
    MO_STANDALONE_CONTENT=$'\n'
    MO_PARSED=""
    mo::content "${moFiles[@]}" || return 1
    mo::parse "" "" ""
    echo -n "$MO_PARSED$MO_UNPARSED"
)


# Internal: Show a debug message
#
# $1 - The debug message to show
#
# Returns nothing.
mo::debug() {
    if [[ -n "${MO_DEBUG:-}" ]]; then
        echo "DEBUG ${FUNCNAME[1]:-?} - $1" >&2
    fi
}


# Internal: Show an error message and exit
#
# $1 - The error message to show
#
# Returns nothing. Exits the program.
mo::error() {
    echo "ERROR: $1" >&2
    exit "${2:-1}"
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


# Internal: Fetches the content to parse into MO_UNPARSED.  Can be a list of
# partials for files or the content from stdin.
#
# $1-@ - File names (optional), read from stdin otherwise
#
# Returns nothing.
mo::content() {
    local moFilename

    if [[ "${#@}" -gt 0 ]]; then
        MO_UNPARSED=""

        for moFilename in "$@"; do
            mo::debug "Using template to load content from file: $moFilename"
            #: This is so relative paths work from inside template files
            MO_UNPARSED="$MO_UNPARSED$MO_OPEN_DELIMITER>$moFilename$MO_CLOSE_DELIMITER"
        done
    else
        mo::debug "Will read content from stdin"
        mo::contentFile || return 1
    fi
}


# Internal: Read a file into MO_UNPARSED.
#
# $1 - Filename to load - if empty, defaults to /dev/stdin
#
# Returns nothing.
mo::contentFile() {
    local moFile moResult

    # The subshell removes any trailing newlines.  We forcibly add
    # a dot to the content to preserve all newlines. Reading from
    # stdin with a `read` loop does not work as expected, so `cat`
    # needs to stay.
    moFile=${1:-/dev/stdin}

    if [[ -e "$moFile" ]]; then
        mo::debug "Loading content: $moFile"
        MO_UNPARSED=$(set +Ee; cat -- "$moFile"; moResult=$?; echo -n '.'; exit "$moResult") || return 1
        MO_UNPARSED=${MO_UNPARSED%.}  # Remove last dot
    elif [[ -n "${MO_FAIL_ON_FILE-}" ]]; then
        mo::error "No such file: $moFile"
    else
        mo::debug "File does not exist: $moFile"
        MO_UNPARSED=""
    fi
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
# $1 - Variable name
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


# Internal: Trim leading characters from MO_UNPARSED
#
# Returns nothing.
mo::trimUnparsed() {
    local moLast moR moN moT

    moLast=""
    moR=$'\r'
    moN=$'\n'
    moT=$'\t'

    while [[ "$MO_UNPARSED" != "$moLast" ]]; do
        moLast=$MO_UNPARSED
        MO_UNPARSED=${MO_UNPARSED# }
        MO_UNPARSED=${MO_UNPARSED#"$moR"}
        MO_UNPARSED=${MO_UNPARSED#"$moN"}
        MO_UNPARSED=${MO_UNPARSED#"$moT"}
    done
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
    moTemp=${moTemp%%"$moR"*}
    moTemp=${moTemp%%"$moN"*}
    moTemp=${moTemp%%"$moT"*}

    local "$1" && mo::indirect "$1" "$moTemp"
}


# Internal: Parse MO_UNPARSED, writing content to MO_PARSED. Interpolates
# mustache tags.
#
# $1 - Current name (the variable NAME for what {{.}} means)
# $2 - Current block name
# $3 - Fast mode (skip to end of block) if non-empty
#
# Array has the following elements
#     [0] - Parsed content
#     [1] - Unparsed content after the closing tag
#
# Returns nothing.
mo::parse() {
    local moCurrent moFastMode moRemainder moChunk

    moCurrent=$1
    moCurrentBlock=$2
    moFastMode=$3
    moRemainder=""
    mo::debug "Starting parse, current: $moCurrent, ending tag: $moCurrentBlock, fast: $moFastMode"

    while [[ -n "$MO_UNPARSED" ]]; do
        moChunk=${MO_UNPARSED%%"$MO_OPEN_DELIMITER"*}
        MO_PARSED="$MO_PARSED$moChunk"
        MO_STANDALONE_CONTENT="$MO_STANDALONE_CONTENT$moChunk"
        MO_UNPARSED=${MO_UNPARSED:${#moChunk}}

        if [[ -n "$MO_UNPARSED" ]]; then
            MO_UNPARSED=${MO_UNPARSED:${#MO_OPEN_DELIMITER}}
            mo::trimUnparsed

            case "$MO_UNPARSED" in
                '#'*)
                    # Loop, if/then, or pass content through function
                    mo::parseBlock "$moCurrent" false
                    ;;

                '^'*)
                    # Display section if named thing does not exist
                    mo::parseBlock "$moCurrent" true
                    ;;

                '>'*)
                    # Load partial - get name of file relative to cwd
                    mo::parsePartial "$moCurrent" "$moFastMode"
                    ;;

                '/'*)
                    # Closing tag
                    mo::parseCloseTag "$moCurrent" "$moCurrentBlock"
                    moRemainder=$MO_UNPARSED
                    MO_UNPARSED=
                    ;;

                '!'*)
                    # Comment - ignore the tag content entirely
                    mo::parseComment
                ;;

                '='*)
                    # Change delimiters
                    # Any two non-whitespace sequences separated by whitespace.
                    mo::parseDelimiter
                    ;;

                '&'*)
                    # Unescaped - mo doesn't escape/unescape
                    MO_UNPARSED=${MO_UNPARSED#&}
                    mo::trimUnparsed
                    mo::parseValue "$moCurrent" "$moFastMode"
                    ;;

                *)
                    # Normal environment variable, string, subexpression,
                    # current value, key, or function call
                    mo::parseValue "$moCurrent" "$moFastMode"
                    ;;
            esac
        fi
    done

    MO_UNPARSED="$MO_UNPARSED$moRemainder"
}


# Internal: Handle parsing a block
#
# $1 - Current name (the variable NAME for what {{.}} means)
# $2 - Invert condition ("true" or "false")
#
# Returns nothing
mo::parseBlock() {
    local moCurrent moInvertBlock moArgs

    moCurrent=$1
    moInvertBlock=$2
    MO_UNPARSED=${MO_UNPARSED:1}
    mo::trimUnparsed
    mo::parseValueInner moArgs "$moCurrent"
    MO_UNPARSED=${MO_UNPARSED#"$MO_CLOSE_DELIMITER"}
    mo::debug "Parsing block: ${moArgs[*]}"

    if mo::standaloneCheck; then
        mo::standaloneProcess
    fi

    if [[ "${moArgs[0]}" == "NAME" ]] && mo::isFunction "${moArgs[1]}"; then
        mo::parseBlockFunction "$moCurrent" "$moInvertBlock" "${moArgs[@]}"
    elif [[ "${moArgs[0]}" == "NAME" ]] && mo::isArray "${moArgs[1]}"; then
        mo::parseBlockArray "$moCurrent" "$moInvertBlock" "${moArgs[@]}"
    else
        mo::parseBlockValue "$moCurrent" "$moInvertBlock" "${moArgs[@]}"
    fi
}


# Internal: Handle parsing a block whose first argument is a function
#
# $1 - Current name (the variable NAME for what {{.}} means)
# $2 - Invert condition ("true" or "false")
# $3-@ - The parsed arguments from inside the block tags
#
# Returns nothing
mo::parseBlockFunction() {
    local moTarget moCurrent moInvertBlock moArgs moTemp moResult

    moCurrent=$1
    moInvertBlock=$2
    shift 2
    moArgs=(${@+"$@"})
    mo::debug "Parsing block function: ${moArgs[*]}"

    if [[ "$moInvertBlock" == "true" ]]; then
        # The function exists and we're inverting the section, so discard
        # any additions to the parsed content.
        moTemp=$MO_PARSED
        mo::parse "$moCurrent" "${moArgs[1]}" "FAST-FUNCTION"
        MO_PARSED=$moTemp
    else
        # Get contents of block after parsing
        moTemp=$MO_PARSED
        MO_PARSED=""
        mo::parse "$moCurrent" "${moArgs[1]}" ""

        # Pass contents to function
        mo::evaluateFunction moResult "$MO_PARSED" "${moArgs[@]:1}"
        MO_PARSED="$moTemp$moResult"
    fi

    mo::debug "Done parsing block function: ${moArgs[*]}"
}


# Internal: Handle parsing a block whose first argument is an array
#
# $1 - Current name (the variable NAME for what {{.}} means)
# $2 - Invert condition ("true" or "false")
# $2-@ - The parsed arguments from inside the block tags
#
# Returns nothing
mo::parseBlockArray() {
    local moCurrent moInvertBlock moArgs moParseResult moResult moArrayName moArrayIndexes moArrayIndex moTemp

    moCurrent=$1
    moInvertBlock=$2
    shift 2
    moArgs=(${@+"$@"})
    mo::debug "Parsing block array: ${moArgs[*]}"
    moArrayName=${moArgs[1]}
    eval "moArrayIndexes=(\"\${!${moArrayName}[@]}\")"

    if [[ "${#moArrayIndexes[@]}" -lt 1 ]]; then
        # No elements
        if [[ "$moInvertBlock" == "true" ]]; then
            # Show the block
            mo::parse "$moArrayName" "$moArrayName" ""
        else
            # Skip the block processing
            moTemp=$MO_PARSED
            mo::parse "$moArrayName" "$moArrayName" "FAST-EMPTY"
            MO_PARSED=$moTemp
        fi
    else
        if [[ "$moInvertBlock" == "true" ]]; then
            # Skip the block processing
            moTemp=$MO_PARSED
            mo::parse "$moArrayName" "$moArrayName" "FAST-EMPTY"
            MO_PARSED=$moTemp
        else
            # Process for each element in the array
            moTemp=$MO_UNPARSED
            for moArrayIndex in "${moArrayIndexes[@]}"; do
                MO_UNPARSED=$moTemp
                mo::debug "Iterate over array using element: $moArrayName.$moArrayIndex"
                mo::parse "$moArrayName.$moArrayIndex" "${moArgs[1]}" ""
            done
        fi
    fi

    mo::debug "Done parsing block array: ${moArgs[*]}"
}


# Internal: Handle parsing a block whose first argument is a value
#
# $1 - Current name (the variable NAME for what {{.}} means)
# $2 - Invert condition ("true" or "false")
# $3-@ - The parsed arguments from inside the block tags
#
# Returns nothing
mo::parseBlockValue() {
    local moCurrent moInvertBlock moArgs moParseResult moResult moTemp

    moCurrent=$1
    moInvertBlock=$2
    shift 2
    moArgs=(${@+"$@"})
    mo::debug "Parsing block value: ${moArgs[*]}"

    # Variable, value, or list of mixed things
    mo::evaluateListOfSingles moResult "$moCurrent" "${moArgs[@]}"

    if mo::isTruthy "$moResult" "$moInvertBlock"; then
        mo::debug "Block is truthy: $moResult"
        mo::parse "${moArgs[1]}" "${moArgs[1]}" ""
    else
        mo::debug "Block is falsy: $moResult"
        moTemp=$MO_PARSED
        mo::parse "${moArgs[1]}" "${moArgs[1]}" "FAST-FALSY"
        MO_PARSED=$moTemp
    fi

    mo::debug "Done parsing block value: ${moArgs[*]}"
}


# Internal: Handle parsing a partial
#
# $1 - Current name (the variable NAME for what {{.}} means)
# $2 - Fast mode (skip to end of block) if non-empty
#
# Indentation will be applied to the entire partial's contents before parsing.
# This indentation is based on the whitespace that ends the previously parsed
# content.
#
# Returns nothing
mo::parsePartial() {
    local moCurrent moFilename moResult moFastMode moIndentation moN moR

    moCurrent=$1
    moFastMode=$2
    MO_UNPARSED=${MO_UNPARSED:1}
    mo::trimUnparsed
    mo::chomp moFilename "${MO_UNPARSED%%"$MO_CLOSE_DELIMITER"*}"
    MO_UNPARSED="${MO_UNPARSED#*"$MO_CLOSE_DELIMITER"}"
    moIndentation=""

    if mo::standaloneCheck; then
        moN=$'\n'
        moR=$'\r'
        moIndentation="$moN${MO_PARSED//"$moR"/"$moN"}"
        moIndentation=${moIndentation##*"$moN"}
        mo::debug "Adding indentation to partial: '$moIndentation'"
        mo::standaloneProcess
    fi

    if [[ -z "$moFastMode" ]]; then
        mo::debug "Parsing partial: $moFilename"

        # Execute in subshell to preserve current cwd and environment
        moResult=$(
            # It would be nice to remove `dirname` and use a function instead,
            # but that is difficult when only given filenames.
            cd "$(dirname -- "$moFilename")" || exit 1
            echo "$(
                if ! mo::contentFile "${moFilename##*/}"; then
                    exit 1
                fi

                mo::indentLines "$moIndentation"

                # Delimiters are reset when loading a new partial
                MO_OPEN_DELIMITER="{{"
                MO_CLOSE_DELIMITER="}}"
                MO_STANDALONE_CONTENT=""
                MO_PARSED=""
                mo::parse "$moCurrent" "" ""

                # Fix bash handling of subshells and keep trailing whitespace.
                echo -n "$MO_PARSED$MO_UNPARSED."
            )" || exit 1
        ) || exit 1

        if [[ -z "$moResult" ]]; then
            mo::debug "Error detected when trying to read the file"
            exit 1
        fi

        MO_PARSED="$MO_PARSED${moResult%.}"
    fi
}


# Internal: Handle closing a tag
#
# $1 - Current name (the variable NAME for what {{.}} means)
# $2 - Current block being processed
#
# Returns nothing.
mo::parseCloseTag() {
    local moArgs moCurrent moCurrentBlock

    moCurrent=$1
    moCurrentBlock=$2
    MO_UNPARSED=${MO_UNPARSED:1}
    mo::trimUnparsed
    mo::parseValueInner moArgs "$moCurrent"
    MO_UNPARSED=${MO_UNPARSED#"$MO_CLOSE_DELIMITER"}
    mo::debug "Closing tag: ${moArgs[1]}"

    if mo::standaloneCheck; then
        mo::standaloneProcess
    fi

    if [[ -n "$moCurrentBlock" ]] && [[ "${moArgs[1]}" != "$moCurrentBlock" ]]; then
        mo::error "Unexpected close tag: ${moArgs[1]}, expected $moCurrentBlock"
    elif [[ -z "$moCurrentBlock" ]]; then
        mo::error "Unexpected close tag: ${moArgs[1]}"
    fi
}


# Internal: Handle parsing a comment
#
# Returns nothing
mo::parseComment() {
    local moContent moPrevious moContent

    MO_UNPARSED=${MO_UNPARSED#*"$MO_CLOSE_DELIMITER"}
    mo::debug "Parsing comment"

    if mo::standaloneCheck; then
        mo::standaloneProcess
    fi
}


# Internal: Handle parsing the change of delimiters
#
# Returns nothing
mo::parseDelimiter() {
    local moContent moOpen moClose moPrevious

    MO_UNPARSED=${MO_UNPARSED:1}
    mo::trimUnparsed
    mo::chomp moOpen "$MO_UNPARSED"
    MO_UNPARSED=${MO_UNPARSED:${#moOpen}}
    mo::trimUnparsed
    mo::chomp moClose "${MO_UNPARSED%%="$MO_CLOSE_DELIMITER"*}"
    MO_UNPARSED=${MO_UNPARSED#*="$MO_CLOSE_DELIMITER"}
    mo::debug "Parsing delimiters: $moOpen $moClose"

    if mo::standaloneCheck; then
        mo::standaloneProcess
    fi

    MO_OPEN_DELIMITER="$moOpen"
    MO_CLOSE_DELIMITER="$moClose"
}


# Internal: Handle parsing value or function call
#
# $1 - Current name (the variable NAME for what {{.}} means)
# $2 - Fast mode (skip to end of block) if non-empty
#
# Returns nothing
mo::parseValue() {
    local moUnparsedOriginal moArgs moFastMode

    moCurrent=$1
    moFastMode=$2
    moUnparsedOriginal=$MO_UNPARSED
    MO_UNPARSED=${MO_UNPARSED#"$MO_OPEN_DELIMITER"}
    mo::trimUnparsed

    mo::parseValueInner moArgs "$moCurrent"

    if [[ -z "$moFastMode" ]]; then
        mo::evaluate moResult "$moCurrent" "${moArgs[@]}"
        MO_PARSED="$MO_PARSED$moResult"
    fi

    if [[ "${MO_UNPARSED:0:${#MO_CLOSE_DELIMITER}}" != "$MO_CLOSE_DELIMITER" ]]; then
        mo::error "Did not find closing tag near: ${moUnparsedOriginal:0:20}"
    fi

    MO_UNPARSED=${MO_UNPARSED:${#MO_CLOSE_DELIMITER}}
}


# Internal: Handle parsing value or function call inside of delimiters.
#
# $1 - Destination variable name, will be set to an array
# $2 - Current name (the variable NAME for what {{.}} means)
#
# The destination value will be an array
#     [@] = a list of argument type, argument name/value
#
# Returns nothing
mo::parseValueInner() {
    local moCurrent moArgs moArgResult

    moCurrent=$2
    moArgs=()

    while [[ "$MO_UNPARSED" != "$MO_CLOSE_DELIMITER"* ]] && [[ "$MO_UNPARSED" != "}"* ]] && [[ "$MO_UNPARSED" != ")"* ]] && [[ -n "$MO_UNPARSED" ]]; do
        mo::getArgument moArgResult
        moArgs=(${moArgs[@]+"${moArgs[@]}"} "${moArgResult[0]}" "${moArgResult[1]}")
    done

    mo::debug "Parsed arguments: ${moArgs[*]}"

    local "$1" && mo::indirectArray "$1" ${moArgs[@]+"${moArgs[@]}"}
}


# Internal: Retrieve an argument name from MO_UNPARSED.
#
# $1 - Destination variable name. Will be an array.
#
# The array will have the following elements
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#
# Returns nothing
mo::getArgument() {
    local moCurrent moArg

    moCurrent=$1

    case "$MO_UNPARSED" in
        '{'*)
            mo::getArgumentBrace moArg "$moCurrent"
            ;;

        '('*)
            mo::getArgumentParenthesis moArg "$moCurrent"
            ;;

        '"'*)
            mo::getArgumentDoubleQuote moArg
            ;;

        "'"*)
            mo::getArgumentSingleQuote moArg
            ;;

        *)
            mo::getArgumentDefault moArg
    esac

    mo::debug "Found argument: ${moArg[0]} ${moArg[1]}"

    local "$1" && mo::indirectArray "$1" "${moArg[0]}" "${moArg[1]}"
}


# Internal: Get an argument, which is the result of a subexpression as a VALUE
#
# $1 - Destination variable name, an array with two elements
# $3 - Current name (the variable NAME for what {{.}} means)
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#
# Returns nothing.
mo::getArgumentBrace() {
    local moResult moCurrent moArgs moUnparsedOriginal

    moCurrent=$2
    moUnparsedOriginal=$MO_UNPARSED
    MO_UNPARSED="${MO_UNPARSED:1}"
    mo::trimUnparsed
    mo::parseValueInner moArgs "$moCurrent"
    mo::evaluate moResult "$moCurrent" "${moArgs[@]}"

    if [[ "${MO_UNPARSED:0:1}" != "}" ]]; then
        mo::escape moResult "${moUnparsedOriginal:0:20}"
        mo::error "Unbalanced brace near $moResult"
    fi

    MO_UNPARSED="${MO_UNPARSED:1}"
    mo::trimUnparsed

    local "$1" && mo::indirectArray "$1" "VALUE" "${moResult[0]}"
}


# Internal: Get an argument, which is the result of a subexpression as a NAME
#
# $1 - Destination variable name, an array with two elements
# $2 - Current name (the variable NAME for what {{.}} means)
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#
# Returns nothing.
mo::getArgumentParenthesis() {
    local moResult moContent moCurrent moUnparsedOriginal

    moCurrent=$2
    moUnparsedOriginal=$MO_UNPARSED
    MO_UNPARSED="${MO_UNPARSED:1}"
    mo::trimUnparsed
    mo::parseValueInner moResult "$moCurrent"

    if [[ "${MO_UNPARSED:0:1}" != ")" ]]; then
        mo::escape moResult "${moUnparsedOriginal:0:20}"
        mo::error "Unbalanced parenthesis near $moResult"
    fi

    MO_UNPARSED=${MO_UNPARSED:1}
    mo::trimUnparsed

    local "$1" && mo::indirectArray "$1" "NAME" "${moResult[0]}"
}


# Internal: Get an argument in a double quoted string
#
# $1 - Destination variable name, an array with two elements
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#
# Returns nothing.
mo::getArgumentDoubleQuote() {
    local moTemp moUnparsedOriginal

    moTemp=""
    moUnparsedOriginal=$MO_UNPARSED
    MO_UNPARSED=${MO_UNPARSED:1}

    while [[ "${MO_UNPARSED:0:1}" != '"' ]]; do
        case "$MO_UNPARSED" in
            \\n)
                moTemp="$moTemp"$'\n'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\r)
                moTemp="$moTemp"$'\r'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\t)
                moTemp="$moTemp"$'\t'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\*)
                moTemp="$moTemp${MO_UNPARSED:1:1}"
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            *)
                moTemp="$moTemp${MO_UNPARSED:0:1}"
                MO_UNPARSED=${MO_UNPARSED:1}
                ;;
        esac

        if [[ -z "$MO_UNPARSED" ]]; then
            mo::escape moTemp "${moUnparsedOriginal:0:20}"
            mo::error "Found starting double quote but no closing double quote starting near $moTemp"
        fi
    done

    mo::debug "Parsed double quoted value: $moTemp"
    MO_UNPARSED=${MO_UNPARSED:1}
    mo::trimUnparsed

    local "$1" && mo::indirectArray "$1" "VALUE" "$moTemp"
}


# Internal: Get an argument in a single quoted string
#
# $1 - Destination variable name, an array with two elements
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#
# Returns nothing.
mo::getArgumentSingleQuote() {
    local moTemp moUnparsedOriginal

    moTemp=""
    moUnparsedOriginal=$MO_UNPARSED
    MO_UNPARSED=${MO_UNPARSED:1}

    while [[ "${MO_UNPARSED:0:1}" != "'" ]]; do
        moTemp="$moTemp${MO_UNPARSED:0:1}"
        MO_UNPARSED=${MO_UNPARSED:1}

        if [[ -z "$MO_UNPARSED" ]]; then
            mo::escape moTemp "${moUnparsedOriginal:0:20}"
            mo::error "Found starting single quote but no closing single quote starting near $moTemp"
        fi
    done

    mo::debug "Parsed single quoted value: $moTemp"
    MO_UNPARSED=${MO_UNPARSED:1}
    mo::trimUnparsed

    local "$1" && mo::indirectArray "$1" "VALUE" "$moTemp"
}


# Internal: Get an argument that is a simple variable name
#
# $1 - Destination variable name, an array with two elements
#
# The array has the following elements.
#     [0] = argument type, "NAME" or "VALUE"
#     [1] = argument name or value
#
# Returns nothing.
mo::getArgumentDefault() {
    local moTemp

    mo::chomp moTemp "${MO_UNPARSED%%"$MO_CLOSE_DELIMITER"*}"
    moTemp=${moTemp%%)*}
    moTemp=${moTemp%%\}*}
    MO_UNPARSED=${MO_UNPARSED:${#moTemp}}
    mo::trimUnparsed
    mo::debug "Parsed default argument: $moTemp"

    local "$1" && mo::indirectArray "$1" "NAME" "$moTemp"
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


# Internal: Determine if an array index exists.
#
# $1 - Variable name to check
# $2 - The index to check
#
# Has to check if the variable is an array and if the index is valid for that
# type of array.
#
# Returns true (0) if everything was ok, 1 if there's any condition that fails.
mo::isArrayIndexValid() {
    local moDeclare moTest

    moDeclare=$(declare -p "$1")
    moTest=""

    if [[ "${moDeclare:0:10}" == "declare -a" ]]; then
        # Numerically indexed array - must check if the index looks like a
        # number because using a string to index a numerically indexed array
        # will appear like it worked.
        if [[ "$2" == "0" ]] || [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
            # Index looks like a number
            eval "moTest=\"\${$1[$2]+ok}\""
        fi
    elif [[ "${moDeclare:0:10}" == "declare -A" ]]; then
        # Associative array
        eval "moTest=\"\${$1[$2]+ok}\""
    fi

    if [[ -n "$moTest" ]]; then
        return 0;
    fi

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
# $3-@ - A list of argument types and argument name/value.
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
# $3-@ - A list of argument types and argument name/value.
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
    local moResult moCurrent moType moArg

    moCurrent=$2
    moType=$3
    moArg=$4

    mo::debug "Evaluating $moType: $moArg ($moCurrent)"

    if [[ "$moType" == "VALUE" ]]; then
        moResult=$moArg
    elif [[ "$moArg" == "." ]]; then
        mo::evaluateVariable moResult "$moCurrent" ""
    elif [[ "$moArg" == "@key" ]]; then
        mo::evaluateKey moResult "$moCurrent"
    elif mo::isFunction "$moArg"; then
        mo::evaluateFunction moResult "" "$moArg"
    else
        mo::evaluateVariable moResult "$moArg" "$moCurrent"
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
# $3 - Current value
#
# Returns nothing.
mo::evaluateVariable() {
    local moResult moCurrent moArg moNameParts

    moArg=$2
    moCurrent=$3
    moResult=""
    mo::findVariableName moNameParts "$moArg" "$moCurrent"
    mo::debug "Evaluate variable ($moArg, $moCurrent): ${moNameParts[*]}"

    if [[ -z "${moNameParts[1]}" ]]; then
        if mo::isArray "$moArg"; then
            eval mo::join moResult "," "\${${moArg}[@]}"
        else
            if mo::isVarSet "$moArg"; then
                moResult="${!moArg}"
            elif [[ -n "${MO_FAIL_ON_UNSET-}" ]]; then
                mo::error "Environment variable not set: $moArg"
            fi
        fi
    else
        if mo::isArray "${moNameParts[0]}"; then
            eval "set +u;moResult=\"\${${moNameParts[0]}[${moNameParts[1]%%.*}]}\""
        else
            mo::error "Unable to index a scalar as an array: $moArg"
        fi
    fi

    local "$1" && mo::indirect "$1" "$moResult"
}


# Internal: Find the name of a variable to use
#
# $1 - Destination variable name, receives an array
# $2 - Variable name from the template
# $3 - The name of the "current value", from block parsing
#
# The array contains the following values
#     [0] - Variable name
#     [1] - Array index, or empty string
#
# Example variables
#     a="a"
#     b="b"
#     c=("c.0" "c.1")
#     d=([b]="d.b" [d]="d.d")
#
# Given these inputs, produce these outputs
#     a c => a
#     a c.0 => a
#     b d => d.b
#     b d.d => d.b
#     a d => d.a
#     a d.d => d.a
#     c.0 d => c.0
#     d.b d => d.b
# Returns nothing.
mo::findVariableName() {
    local moVar moCurrent moNameParts moResultBase moResultIndex

    moVar=$2
    moCurrent=$3
    moResultBase=$moVar
    moResultIndex=""

    if [[ "$moVar" == *.* ]]; then
        mo::debug "Find variable name; name has dot: $moVar"
        moResultBase=${moVar%%.*}
        moResultIndex=${moVar#*.}
    elif [[ -n "$moCurrent" ]]; then
        moCurrent=${moCurrent%%.*}
        mo::debug "Find variable name; look in array: $moCurrent"

        if mo::isArrayIndexValid "$moCurrent" "$moVar"; then
            moResultBase=$moCurrent
            moResultIndex=$moVar
        fi
    fi

    local "$1" && mo::indirectArray "$1" "$moResultBase" "$moResultIndex"
}


# Internal: Join / implode an array
#
# $1    - Variable name to receive the joined content
# $2    - Joiner
# $3-@ - Elements to join
#
# Returns nothing.
mo::join() {
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
# $4-@ - Additional arguments as list of type, value/name
#
# Returns nothing.
mo::evaluateFunction() {
    local moArgs moContent moFunctionResult moTarget moFunction moTemp moFunctionCall

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

    if [[ -n "${MO_ALLOW_FUNCTION_ARGUMENTS-}" ]]; then
        mo::debug "Function arguments are allowed"

        for moTemp in "${moArgs[@]}"; do
            mo::escape moTemp "$moTemp"
            moFunctionCall="$moFunctionCall $moTemp"
        done
    fi

    mo::debug "Calling function: $moFunctionCall"

    # Call the function in a subshell for safety. Employ the trick to preserve
    # whitespace at the end of the output.
    moContent=$(export MO_FUNCTION_ARGS=("${moArgs[@]}"); echo -n "$moContent" | eval "$moFunctionCall ; moFunctionResult=\$? ; echo -n '.' ; exit \"\$moFunctionResult\"") || {
        moFunctionResult=$?
        if [[ -n "${MO_FAIL_ON_FUNCTION-}" && "$moFunctionResult" != 0 ]]; then
            mo::error "Function failed with status code $moFunctionResult: $moFunctionCall" "$moFunctionResult"
        fi
    }

    local "$moTarget" && mo::indirect "$moTarget" "${moContent%.}"
}


# Internal: Check if a tag appears to have only whitespace before it and after
# it on a line. There must be a new line before (see the trick in mo::parse)
# and there must be a newline after or the end of a string
#
# Returns 0 if this is a standalone tag, 1 otherwise.
mo::standaloneCheck() {
    local moContent moN moR moT

    moN=$'\n'
    moR=$'\r'
    moT=$'\t'

    # Check the content before
    moContent=${MO_STANDALONE_CONTENT//"$moR"/"$moN"}

    # By default, signal to the next check that this one failed
    MO_STANDALONE_CONTENT=""

    if [[ "$moContent" != *"$moN"* ]]; then
        mo::debug "Not a standalone tag - no newline before"

        return 1
    fi

    moContent=${moContent##*"$moN"}
    moContent=${moContent//"$moT"/}
    moContent=${moContent// /}

    if [[ -n "$moContent" ]]; then
        mo::debug "Not a standalone tag - non-whitespace detected before tag"

        return 1
    fi

    # Check the content after
    moContent=${MO_UNPARSED//"$moR"/"$moN"}
    moContent=${moContent%%"$moN"*}
    moContent=${moContent//"$moT"/}
    moContent=${moContent// /}

    if [[ -n "$moContent" ]]; then
        mo::debug "Not a standalone tag - non-whitespace detected after tag"

        return 1
    fi

    # Signal to the next check that this tag removed content
    MO_STANDALONE_CONTENT=$'\n'

    return 0
}


# Internal: Process content before and after a tag. Remove prior whitespace up to the previous newline. Remove following whitespace up to and including the next newline.
#
# Returns nothing.
mo::standaloneProcess() {
    local moContent moLast moT moR moN

    moT=$'\t'
    moR=$'\r'
    moN=$'\n'
    moLast=

    mo::debug "Standalone tag - processing content before and after tag"

    while [[ "$moLast" != "$MO_PARSED" ]]; do
        moLast=$MO_PARSED
        MO_PARSED=${MO_PARSED% }
        MO_PARSED=${MO_PARSED%"$moT"}
    done

    moLast=

    while [[ "$moLast" != "$MO_UNPARSED" ]]; do
        moLast=$MO_UNPARSED
        MO_UNPARSED=${MO_UNPARSED# }
        MO_UNPARSED=${MO_UNPARSED#"$moT"}
    done

    MO_UNPARSED=${MO_UNPARSED#"$moR"}
    MO_UNPARSED=${MO_UNPARSED#"$moN"}
}


# Internal: Apply indentation before any line that has content in MO_UNPARSED.
#
# $1 - The indentation string
#
# Returns nothing.
mo::indentLines() {
    local moContent moIndentation moResult moN moR moChunk

    moIndentation=$1

    if [[ -z "$moIndentation" ]] || [[ -z "$MO_UNPARSED" ]]; then
        mo::debug "Not applying indentation, indentation ${#moIndentation} bytes, content ${#MO_UNPARSED} bytes"

        return
    fi

    moContent=$MO_UNPARSED
    MO_UNPARSED=
    moN=$'\n'
    moR=$'\r'

    mo::debug "Applying indentation: '${moIndentation}'"

    while [[ -n "$moContent" ]]; do
        moChunk=${moContent%%"$moN"*}
        moChunk=${moChunk%%"$moR"*}
        moContent=${moContent:${#moChunk}}

        if [[ -n "$moChunk" ]]; then
            MO_UNPARSED="$MO_UNPARSED$moIndentation$moChunk"
        fi

        MO_UNPARSED="$MO_UNPARSED${moContent:0:1}"
        moContent=${moContent:1}
    done
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
