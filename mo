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
#/          Can be used multiple times. The file must be a valid shell script
#/          and should only contain variable assignments.
#/    -o=DELIM, --open=DELIM
#/          Set the opening delimiter. Default is "{{".
#/    -c=DELIM, --close=DELIM
#/          Set the closing delimiter. Default is "}}".
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
#/     Used internally.
#/ MO_CLOSE_DELIMITER_DEFAULT - The default value of MO_CLOSE_DELIMITER. Used
#/     when resetting the close delimiter, such as when parsing a partial.
#/ MO_CURRENT - Variable name to use for ".".
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
#/     Used internally.
#/ MO_OPEN_DELIMITER_DEFAULT - The default value of MO_OPEN_DELIMITER. Used
#/     when resetting the open delimiter, such as when parsing a partial.
#/ MO_ORIGINAL_COMMAND - Used to find the `mo` program in order to generate a
#/     help message.
#/ MO_PARSED - Content that has made it through the template engine.
#/ MO_STANDALONE_CONTENT - The unparsed content that preceeded the current tag.
#/     When a standalone tag is encountered, this is checked to see if it only
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

#: Disable these warnings for the entire file
#:
#: VAR_NAME was modified in a subshell. That change might be lost.
# shellcheck disable=SC2031
#:
#: Modification of VAR_NAME is local (to subshell caused by (..) group).
# shellcheck disable=SC2030

# Public: Template parser function.  Writes templates to stdout.
#
# $0 - Name of the mo file, used for getting the help message.
# $@ - Filenames to parse.
#
# Returns nothing.
mo() (
    local moSource moFiles moDoubleHyphens moParsed moContent

    #: This function executes in a subshell; IFS is reset at the end.
    IFS=$' \n\t'

    #: Enable a strict mode. This is also reset at the end.
    set -eEu -o pipefail
    moFiles=()
    moDoubleHyphens=false
    MO_OPEN_DELIMITER_DEFAULT="{{"
    MO_CLOSE_DELIMITER_DEFAULT="}}"
    MO_FUNCTION_CACHE_HIT=()
    MO_FUNCTION_CACHE_MISS=()

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

                        if [[ -e "$moSource" ]]; then
                            # shellcheck disable=SC1090
                            . "$moSource"
                        else
                            echo "No such file: $moSource" >&2
                            exit 1
                        fi
                        ;;

                    -o=* | --open=*)
                        if [[ "$arg" == --open=* ]]; then
                            MO_OPEN_DELIMITER_DEFAULT="${arg#--open=}"
                        else
                            MO_OPEN_DELIMITER_DEFAULT="${arg#-o=}"
                        fi
                        ;;

                    -c=* | --close=*)
                        if [[ "$arg" == --close=* ]]; then
                            MO_CLOSE_DELIMITER_DEFAULT="${arg#--close=}"
                        else
                            MO_CLOSE_DELIMITER_DEFAULT="${arg#-c=}"
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
    MO_OPEN_DELIMITER="$MO_OPEN_DELIMITER_DEFAULT"
    MO_CLOSE_DELIMITER="$MO_CLOSE_DELIMITER_DEFAULT"
    mo::content moContent ${moFiles[@]+"${moFiles[@]}"} || return 1
    mo::parse moParsed "$moContent"
    echo -n "$moParsed"
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


# Internal: Show a debug message and internal state information
#
# No arguments
#
# Returns nothing.
mo::debugShowState() {
    if [[ -z "${MO_DEBUG:-}" ]]; then
        return
    fi
   
    local moState moTemp moIndex moDots

    mo::escape moTemp "$MO_OPEN_DELIMITER"
    moState="open: $moTemp"
    mo::escape moTemp "$MO_CLOSE_DELIMITER"
    moState="$moState  close: $moTemp"
    mo::escape moTemp "$MO_STANDALONE_CONTENT"
    moState="$moState  standalone: $moTemp"
    mo::escape moTemp "$MO_CURRENT"
    moState="$moState  current: $moTemp"
    moIndex=$((${#MO_PARSED} - 20))
    moDots=...

    if [[ "$moIndex" -lt 0 ]]; then
        moIndex=0
        moDots=
    fi

    mo::escape moTemp "${MO_PARSED:$moIndex}"
    moState="$moState  parsed: $moDots$moTemp"

    moDots=...
    
    if [[ "${#MO_UNPARSED}" -le 20 ]]; then
        moDots=
    fi

    mo::escape moTemp "${MO_UNPARSED:0:20}$moDots"
    moState="$moState  unparsed: $moTemp"

    echo "DEBUG ${FUNCNAME[1]:-?} - $moState" >&2
}

# Internal: Show an error message and exit
#
# $1 - The error message to show
# $2 - Error code
#
# Returns nothing. Exits the program.
mo::error() {
    echo "ERROR: $1" >&2
    exit "${2:-1}"
}


# Internal: Show an error message with a snippet of context and exit
#
# $1 - The error message to show
# $2 - The starting point
# $3 - Error code
#
# Returns nothing. Exits the program.
mo::errorNear() {
    local moEscaped

    mo::escape moEscaped "${2:0:40}"
    echo "ERROR: $1" >&2
    echo "ERROR STARTS NEAR: $moEscaped"
    exit "${3:-1}"
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
# $1 - Destination variable name
# $2-@ - File names (optional), read from stdin otherwise
#
# Returns nothing.
mo::content() {
    local moTarget moContent moFilename

    moTarget=$1
    shift
    moContent=""

    if [[ "${#@}" -gt 0 ]]; then
        for moFilename in "$@"; do
            mo::debug "Using template to load content from file: $moFilename"
            #: This is so relative paths work from inside template files
            moContent="$moContent$MO_OPEN_DELIMITER>$moFilename$MO_CLOSE_DELIMITER"
        done
    else
        mo::debug "Will read content from stdin"
        mo::contentFile moContent || return 1
    fi
    
    local "$moTarget" && mo::indirect "$moTarget" "$moContent"
}


# Internal: Read a file into MO_UNPARSED.
#
# $1 - Destination variable name.
# $2 - Filename to load - if empty, defaults to /dev/stdin
#
# Returns nothing.
mo::contentFile() {
    local moFile moResult moContent

    #: The subshell removes any trailing newlines.  We forcibly add
    #: a dot to the content to preserve all newlines. Reading from
    #: stdin with a `read` loop does not work as expected, so `cat`
    #: needs to stay.
    moFile=${2:-/dev/stdin}

    if [[ -e "$moFile" ]]; then
        mo::debug "Loading content: $moFile"
        moContent=$(
            set +Ee
            cat -- "$moFile"
            moResult=$?
            echo -n '.'
            exit "$moResult"
        ) || return 1
        moContent=${moContent%.}  #: Remove last dot
    elif [[ -n "${MO_FAIL_ON_FILE-}" ]]; then
        mo::error "No such file: $moFile"
    else
        mo::debug "File does not exist: $moFile"
        moContent=""
    fi

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

    #: IFS must be set to a string containing space or unset in order for
    #: the array slicing to work regardless of the current IFS setting on
    #: bash 3.  This is detailed further at
    #: https://github.com/fidian/gg-core/pull/7
    eval "$(printf "IFS= %s=(\"\${@:2}\") IFS=%q" "$1" "$IFS")"
}


# Internal: Trim leading characters from MO_UNPARSED
#
# Returns nothing.
mo::trimUnparsed() {
    local moI moC

    moI=0
    moC=${MO_UNPARSED:0:1}

    while [[ "$moC" == " " || "$moC" == $'\r' || "$moC" == $'\n' || "$moC" == $'\t' ]]; do
        moI=$((moI + 1))
        moC=${MO_UNPARSED:$moI:1}
    done

    if [[ "$moI" != 0 ]]; then
        MO_UNPARSED=${MO_UNPARSED:$moI}
    fi
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


# Public: Parses text, interpolates mustache tags. Utilizes the current value
# of MO_OPEN_DELIMITER, MO_CLOSE_DELIMITER, and MO_STANDALONE_CONTENT. Those
# three variables shouldn't be changed by user-defined functions.
#
# $1 - Destination variable name - where to store the finished content
# $2 - Content to parse
# $3 - Preserve standalone status/content - truthy if not empty. When set to a
#      value, that becomes the standalone content value
#
# Returns nothing.
mo::parse() {
    local moOldParsed moOldStandaloneContent moOldUnparsed moResult

    #: The standalone content is a trick to make the standalone tag detection
    #: possible. When it's set to content with a newline and if the tag supports
    #: it, the standalone content check happens. This check ensures only
    #: whitespace is after the last newline up to the tag, and only whitespace
    #: is after the tag up to the next newline. If that is the case, remove
    #: whitespace and the trailing newline. By setting this to $'\n', we're
    #: saying we are at the beginning of content.
    mo::debug "Starting parse of ${#2} bytes"
    moOldParsed=${MO_PARSED:-}
    moOldUnparsed=${MO_UNPARSED:-}
    MO_PARSED=""
    MO_UNPARSED="$2"

    if [[ -z "${3:-}" ]]; then
        moOldStandaloneContent=${MO_STANDALONE_CONTENT:-}
        MO_STANDALONE_CONTENT=$'\n'
    else
        MO_STANDALONE_CONTENT=$3
    fi

    MO_CURRENT=${MO_CURRENT:-}
    mo::parseInternal
    moResult="$MO_PARSED$MO_UNPARSED"
    MO_PARSED=$moOldParsed
    MO_UNPARSED=$moOldUnparsed

    if [[ -z "${3:-}" ]]; then
        MO_STANDALONE_CONTENT=$moOldStandaloneContent
    fi

    local "$1" && mo::indirect "$1" "$moResult"
}


# Internal: Parse MO_UNPARSED, writing content to MO_PARSED. Interpolates
# mustache tags.
#
# No arguments
#
# Returns nothing.
mo::parseInternal() {
    local moChunk

    mo::debug "Starting parse"

    while [[ -n "$MO_UNPARSED" ]]; do
        mo::debugShowState
        moChunk=${MO_UNPARSED%%"$MO_OPEN_DELIMITER"*}
        MO_PARSED="$MO_PARSED$moChunk"
        MO_STANDALONE_CONTENT="$MO_STANDALONE_CONTENT$moChunk"
        MO_UNPARSED=${MO_UNPARSED:${#moChunk}}

        if [[ -n "$MO_UNPARSED" ]]; then
            MO_UNPARSED=${MO_UNPARSED:${#MO_OPEN_DELIMITER}}
            mo::trimUnparsed

            case "$MO_UNPARSED" in
                '#'*)
                    #: Loop, if/then, or pass content through function
                    mo::parseBlock false
                    ;;

                '^'*)
                    #: Display section if named thing does not exist
                    mo::parseBlock true
                    ;;

                '>'*)
                    #: Load partial - get name of file relative to cwd
                    mo::parsePartial
                    ;;

                '/'*)
                    #: Closing tag
                    mo::errorNear "Unbalanced close tag" "$MO_UNPARSED"
                    ;;

                '!'*)
                    #: Comment - ignore the tag content entirely
                    mo::parseComment
                    ;;

                '='*)
                    #: Change delimiters
                    #: Any two non-whitespace sequences separated by whitespace.
                    mo::parseDelimiter
                    ;;

                '&'*)
                    #: Unescaped - mo doesn't escape/unescape
                    MO_UNPARSED=${MO_UNPARSED#&}
                    mo::trimUnparsed
                    mo::parseValue
                    ;;

                *)
                    #: Normal environment variable, string, subexpression,
                    #: current value, key, or function call
                    mo::parseValue
                    ;;
            esac
        fi
    done
}


# Internal: Handle parsing a block
#
# $1 - Invert condition ("true" or "false")
#
# Returns nothing
mo::parseBlock() {
    local moInvertBlock moTokens moTokensString

    moInvertBlock=$1
    MO_UNPARSED=${MO_UNPARSED:1}
    mo::tokenizeTagContents moTokens "$MO_CLOSE_DELIMITER"
    MO_UNPARSED=${MO_UNPARSED#"$MO_CLOSE_DELIMITER"}
    mo::tokensToString moTokensString "${moTokens[@]:1}"
    mo::debug "Parsing block: $moTokensString"

    if mo::standaloneCheck; then
        mo::standaloneProcess
    fi

    if [[ "${moTokens[1]}" == "NAME" ]] && mo::isFunction "${moTokens[2]}"; then
        mo::parseBlockFunction "$moInvertBlock" "$moTokensString" "${moTokens[@]:1}"
    elif [[ "${moTokens[1]}" == "NAME" ]] && mo::isArray "${moTokens[2]}"; then
        mo::parseBlockArray "$moInvertBlock" "$moTokensString" "${moTokens[@]:1}"
    else
        mo::parseBlockValue "$moInvertBlock" "$moTokensString" "${moTokens[@]:1}"
    fi
}


# Internal: Handle parsing a block whose first argument is a function
#
# $1 - Invert condition ("true" or "false")
# $2-@ - The parsed tokens from inside the block tags
#
# Returns nothing
mo::parseBlockFunction() {
    local moTarget moInvertBlock moTokens moTemp moUnparsed moTokensString

    moInvertBlock=$1
    moTokensString=$2
    shift 2
    moTokens=(${@+"$@"})
    mo::debug "Parsing block function: $moTokensString"
    mo::getContentUntilClose moTemp "$moTokensString"
    #: Pass unparsed content to the function.
    #: Keep the updated delimiters if they changed.

    if [[ "$moInvertBlock" != "true" ]]; then
        mo::evaluateFunction moResult "$moTemp" "${moTokens[@]:1}"
        MO_PARSED="$MO_PARSED$moResult"
    fi

    mo::debug "Done parsing block function: $moTokensString"
}


# Internal: Handle parsing a block whose first argument is an array
#
# $1 - Invert condition ("true" or "false")
# $2-@ - The parsed tokens from inside the block tags
#
# Returns nothing
mo::parseBlockArray() {
    local moInvertBlock moTokens moResult moArrayName moArrayIndexes moArrayIndex moTemp moUnparsed moOpenDelimiterBefore moCloseDelimiterBefore moOpenDelimiterAfter moCloseDelimiterAfter moParsed moTokensString moCurrent

    moInvertBlock=$1
    moTokensString=$2
    shift 2
    moTokens=(${@+"$@"})
    mo::debug "Parsing block array: $moTokensString"
    moOpenDelimiterBefore=$MO_OPEN_DELIMITER
    moCloseDelimiterBefore=$MO_CLOSE_DELIMITER
    mo::getContentUntilClose moTemp "$moTokensString"
    moOpenDelimiterAfter=$MO_OPEN_DELIMITER
    moCloseDelimiterAfter=$MO_CLOSE_DELIMITER
    moArrayName=${moTokens[1]}
    eval "moArrayIndexes=(\"\${!${moArrayName}[@]}\")"
    
    if [[ "${#moArrayIndexes[@]}" -lt 1 ]]; then
        #: No elements
        if [[ "$moInvertBlock" == "true" ]]; then
            #: Restore the delimiter before parsing
            MO_OPEN_DELIMITER=$moOpenDelimiterBefore
            MO_CLOSE_DELIMITER=$moCloseDelimiterBefore
            moCurrent=$MO_CURRENT
            MO_CURRENT=$moArrayName
            mo::parse moParsed "$moTemp" "blockArrayInvert$MO_STANDALONE_CONTENT"
            MO_CURRENT=$moCurrent
            MO_PARSED="$MO_PARSED$moParsed"
        fi
    else
        if [[ "$moInvertBlock" != "true" ]]; then
            #: Process for each element in the array
            moUnparsed=$MO_UNPARSED

            for moArrayIndex in "${moArrayIndexes[@]}"; do
                #: Restore the delimiter before parsing
                MO_OPEN_DELIMITER=$moOpenDelimiterBefore
                MO_CLOSE_DELIMITER=$moCloseDelimiterBefore
                moCurrent=$MO_CURRENT
                MO_CURRENT=$moArrayName.$moArrayIndex
                mo::debug "Iterate over array using element: $MO_CURRENT"
                mo::parse moParsed "$moTemp" "blockArray$MO_STANDALONE_CONTENT"
                MO_CURRENT=$moCurrent
                MO_PARSED="$MO_PARSED$moParsed"
            done

            MO_UNPARSED=$moUnparsed
        fi
    fi

    MO_OPEN_DELIMITER=$moOpenDelimiterAfter
    MO_CLOSE_DELIMITER=$moCloseDelimiterAfter
    mo::debug "Done parsing block array: $moTokensString"
}


# Internal: Handle parsing a block whose first argument is a value
#
# $1 - Invert condition ("true" or "false")
# $2-@ - The parsed tokens from inside the block tags
#
# Returns nothing
mo::parseBlockValue() {
    local moInvertBlock moTokens moResult moUnparsed moOpenDelimiterBefore moOpenDelimiterAfter moCloseDelimiterBefore moCloseDelimiterAfter moParsed moTemp moTokensString moCurrent

    moInvertBlock=$1
    moTokensString=$2
    shift 2
    moTokens=(${@+"$@"})
    mo::debug "Parsing block value: $moTokensString"
    moOpenDelimiterBefore=$MO_OPEN_DELIMITER
    moCloseDelimiterBefore=$MO_CLOSE_DELIMITER
    mo::getContentUntilClose moTemp "$moTokensString"
    moOpenDelimiterAfter=$MO_OPEN_DELIMITER
    moCloseDelimiterAfter=$MO_CLOSE_DELIMITER

    #: Variable, value, or list of mixed things
    mo::evaluateListOfSingles moResult "${moTokens[@]}"

    if mo::isTruthy "$moResult" "$moInvertBlock"; then
        mo::debug "Block is truthy: $moResult"
        #: Restore the delimiter before parsing
        MO_OPEN_DELIMITER=$moOpenDelimiterBefore
        MO_CLOSE_DELIMITER=$moCloseDelimiterBefore
        moCurrent=$MO_CURRENT
        MO_CURRENT=${moTokens[1]}
        mo::parse moParsed "$moTemp" "blockValue$MO_STANDALONE_CONTENT"
        MO_PARSED="$MO_PARSED$moParsed"
        MO_CURRENT=$moCurrent
    fi

    MO_OPEN_DELIMITER=$moOpenDelimiterAfter
    MO_CLOSE_DELIMITER=$moCloseDelimiterAfter
    mo::debug "Done parsing block value: $moTokensString"
}


# Internal: Handle parsing a partial
#
# No arguments.
#
# Indentation will be applied to the entire partial's contents before parsing.
# This indentation is based on the whitespace that ends the previously parsed
# content.
#
# Returns nothing
mo::parsePartial() {
    local moFilename moResult moIndentation moN moR moTemp moT

    MO_UNPARSED=${MO_UNPARSED:1}
    mo::trimUnparsed
    mo::chomp moFilename "${MO_UNPARSED%%"$MO_CLOSE_DELIMITER"*}"
    MO_UNPARSED="${MO_UNPARSED#*"$MO_CLOSE_DELIMITER"}"
    moIndentation=""

    if mo::standaloneCheck; then
        moN=$'\n'
        moR=$'\r'
        moT=$'\t'
        moIndentation="$moN${MO_PARSED//"$moR"/"$moN"}"
        moIndentation=${moIndentation##*"$moN"}
        moTemp=${moIndentation// }
        moTemp=${moTemp//"$moT"}

        if [[ -n "$moTemp" ]]; then
            moIndentation=
        fi

        mo::debug "Adding indentation to partial: '$moIndentation'"
        mo::standaloneProcess
    fi

    mo::debug "Parsing partial: $moFilename"

    #: Execute in subshell to preserve current cwd and environment
    moResult=$(
        #: It would be nice to remove `dirname` and use a function instead,
        #: but that is difficult when only given filenames.
        cd "$(dirname -- "$moFilename")" || exit 1
        echo "$(
            local moPartialContent moPartialParsed

            if ! mo::contentFile moPartialContent "${moFilename##*/}"; then
                exit 1
            fi

            #: Reset delimiters before parsing
            mo::indentLines moPartialContent "$moIndentation" "$moPartialContent"
            MO_OPEN_DELIMITER="$MO_OPEN_DELIMITER_DEFAULT"
            MO_CLOSE_DELIMITER="$MO_CLOSE_DELIMITER_DEFAULT"
            mo::parse moPartialParsed "$moPartialContent"

            #: Fix bash handling of subshells and keep trailing whitespace.
            echo -n "$moPartialParsed."
        )" || exit 1
    ) || exit 1

    if [[ -z "$moResult" ]]; then
        mo::debug "Error detected when trying to read the file"
        exit 1
    fi

    MO_PARSED="$MO_PARSED${moResult%.}"
}


# Internal: Handle parsing a comment
#
# No arguments.
#
# Returns nothing
mo::parseComment() {
    local moContent moContent

    MO_UNPARSED=${MO_UNPARSED#*"$MO_CLOSE_DELIMITER"}
    mo::debug "Parsing comment"

    if mo::standaloneCheck; then
        mo::standaloneProcess
    fi
}


# Internal: Handle parsing the change of delimiters
#
# No arguments.
#
# Returns nothing
mo::parseDelimiter() {
    local moContent moOpen moClose

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
# No arguments.
#
# Returns nothing
mo::parseValue() {
    local moUnparsedOriginal moTokens

    moUnparsedOriginal=$MO_UNPARSED
    mo::tokenizeTagContents moTokens "$MO_CLOSE_DELIMITER"
    mo::evaluate moResult "${moTokens[@]:1}"
    MO_PARSED="$MO_PARSED$moResult"

    if [[ "${MO_UNPARSED:0:${#MO_CLOSE_DELIMITER}}" != "$MO_CLOSE_DELIMITER" ]]; then
        mo::errorNear "Did not find closing tag" "$moUnparsedOriginal"
    fi

    if mo::standaloneCheck; then
        mo::standaloneProcess
    fi

    MO_UNPARSED=${MO_UNPARSED:${#MO_CLOSE_DELIMITER}}
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
    local moFunctionName

    for moFunctionName in "${MO_FUNCTION_CACHE_HIT[@]}"; do
        if [[ "$moFunctionName" == "$1" ]]; then
            return 0
        fi
    done

    for moFunctionName in "${MO_FUNCTION_CACHE_MISS[@]}"; do
        if [[ "$moFunctionName" == "$1" ]]; then
            return 1
        fi
    done

    if declare -F "$1" &> /dev/null; then
        MO_FUNCTION_CACHE_HIT=( ${MO_FUNCTION_CACHE_HIT[@]+"${MO_FUNCTION_CACHE_HIT[@]}"} "$1" )

        return 0
    fi

    MO_FUNCTION_CACHE_MISS=( ${MO_FUNCTION_CACHE_MISS[@]+"${MO_FUNCTION_CACHE_MISS[@]}"} "$1" )

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
    #: Namespace this variable so we don't conflict with what we're testing.
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
        #: Numerically indexed array - must check if the index looks like a
        #: number because using a string to index a numerically indexed array
        #: will appear like it worked.
        if [[ "$2" == "0" ]] || [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
            #: Index looks like a number
            eval "moTest=\"\${$1[$2]+ok}\""
        fi
    elif [[ "${moDeclare:0:10}" == "declare -A" ]]; then
        #: Associative array
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
# Using logic like this gives false positives.
#     [[ -v "$a" ]]
#
# Declaring a variable is not the same as assigning the variable.
#     export x
#     declare -p x   # Output: declare -x x
#     export y=""
#     declare -p y   # Output: declare -x y=""
#     unset z
#     declare -p z   # Error code 1 and output: bash: declare: z: not found
#
# Returns true (0) if the variable is set, 1 if the variable is unset.
mo::isVarSet() {
    if declare -p "$1" &> /dev/null && [[ -v "$1" ]]; then
        return 0
    fi

    return 1
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

    #: XOR the results
    #: moTruthy  inverse  desiredResult
    #: true      false    true
    #: true      true     false
    #: false     false    false
    #: false     true     true
    if [[ "$moTruthy" == "$2" ]]; then
        mo::debug "Value is falsy, test result: $moTruthy inverse: $2"
        return 1
    fi

    mo::debug "Value is truthy, test result: $moTruthy inverse: $2"
    return 0
}


# Internal: Convert token list to values
#
# $1 - Destination variable name
# $2-@ - Tokens to convert
#
# Sample call:
#
#     mo::evaluate dest NAME username VALUE abc123 PAREN 2
#
# Returns nothing.
mo::evaluate() {
    local moTarget moStack moValue moType moIndex moCombined moResult

    moTarget=$1
    shift

    #: Phase 1 - remove all command tokens (PAREN, BRACE)
    moStack=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            PAREN|BRACE)
                moType=$1
                moValue=$2
                mo::debug "Combining $moValue tokens"
                moIndex=$((${#moStack[@]} - (2 * moValue)))
                mo::evaluateListOfSingles moCombined "${moStack[@]:$moIndex}"

                if [[ "$moType" == "PAREN" ]]; then
                    moStack=("${moStack[@]:0:$moIndex}" NAME "$moCombined")
                else
                    moStack=("${moStack[@]:0:$moIndex}" VALUE "$moCombined")
                fi
                ;;

            *)
                moStack=(${moStack[@]+"${moStack[@]}"} "$1" "$2")
                ;;
        esac

        shift 2
    done

    #: Phase 2 - check if this is a function or if we should just concatenate values
    if [[ "${moStack[0]:-}" == "NAME" ]] && mo::isFunction "${moStack[1]}"; then
        #: Special case - if the first argument is a function, then the rest are
        #: passed to the function.
        mo::debug "Evaluating function: ${moStack[1]}"
        mo::evaluateFunction moResult "" "${moStack[@]:1}"
    else
        #: Concatenate
        mo::debug "Concatenating ${#moStack[@]} stack items"
        mo::evaluateListOfSingles moResult ${moStack[@]+"${moStack[@]}"}
    fi

    local "$moTarget" && mo::indirect "$moTarget" "$moResult"
}


# Internal: Convert an argument list to individual values.
#
# $1 - Destination variable name
# $2-@ - A list of argument types and argument name/value.
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
    local moResult moTarget moTemp

    moTarget=$1
    shift
    moResult=""

    while [[ $# -gt 1 ]]; do
        mo::evaluateSingle moTemp "$1" "$2"
        moResult="$moResult$moTemp"
        shift 2
    done

    mo::debug "Evaluated list of singles: $moResult"

    local "$moTarget" && mo::indirect "$moTarget" "$moResult"
}


# Internal: Evaluate a single argument
#
# $1 - Name of variable for result
# $2 - Type of argument, either NAME or VALUE
# $3 - Argument
#
# Returns nothing
mo::evaluateSingle() {
    local moResult moType moArg

    moType=$2
    moArg=$3
    mo::debug "Evaluating $moType: $moArg ($MO_CURRENT)"

    if [[ "$moType" == "VALUE" ]]; then
        moResult=$moArg
    elif [[ "$moArg" == "." ]]; then
        mo::evaluateVariable moResult ""
    elif [[ "$moArg" == "@key" ]]; then
        mo::evaluateKey moResult
    elif mo::isFunction "$moArg"; then
        mo::evaluateFunction moResult "" "$moArg"
    else
        mo::evaluateVariable moResult "$moArg"
    fi

    local "$1" && mo::indirect "$1" "$moResult"
}


# Internal: Return the value for @key based on current's name
#
# $1 - Name of variable for result
#
# Returns nothing
mo::evaluateKey() {
    local moResult

    if [[ "$MO_CURRENT" == *.* ]]; then
        moResult="${MO_CURRENT#*.}"
    else
        moResult="${MO_CURRENT}"
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
    local moResult moArg moNameParts

    moArg=$2
    moResult=""
    mo::findVariableName moNameParts "$moArg"
    mo::debug "Evaluate variable ($moArg, $MO_CURRENT): ${moNameParts[*]}"

    if [[ -z "${moNameParts[1]}" ]]; then
        if mo::isArray "${moNameParts[0]}"; then
            eval mo::join moResult "," "\${${moNameParts[0]}[@]}"
        else
            if mo::isVarSet "${moNameParts[0]}"; then
                moResult=${moNameParts[0]}
                moResult="${!moResult}"
            elif [[ -n "${MO_FAIL_ON_UNSET-}" ]]; then
                mo::error "Environment variable not set: ${moNameParts[0]}"
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
# Given these inputs (function input, current value), produce these outputs
#     a c => a
#     a c.0 => a
#     b d => d.b
#     b d.d => d.b
#     a d => d.a
#     a d.d => d.a
#     c.0 d => c.0
#     d.b d => d.b
#     '' c => c
#     '' c.0 => c.0
# Returns nothing.
mo::findVariableName() {
    local moVar moNameParts moResultBase moResultIndex moCurrent

    moVar=$2
    moResultBase=$moVar
    moResultIndex=""

    if [[ -z "$moVar" ]]; then
        moResultBase=${MO_CURRENT%%.*}

        if [[ "$MO_CURRENT" == *.* ]]; then
            moResultIndex=${MO_CURRENT#*.}
        fi
    elif [[ "$moVar" == *.* ]]; then
        mo::debug "Find variable name; name has dot: $moVar"
        moResultBase=${moVar%%.*}
        moResultIndex=${moVar#*.}
    elif [[ -n "$MO_CURRENT" ]]; then
        moCurrent=${MO_CURRENT%%.*}
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
        mo::evaluateSingle moTemp "$1" "$2"
        moArgs=(${moArgs[@]+"${moArgs[@]}"} "$moTemp")
        shift 2
    done

    mo::escape moFunctionCall "$moFunction"

    if [[ -n "${MO_ALLOW_FUNCTION_ARGUMENTS-}" ]]; then
        mo::debug "Function arguments are allowed"

        if [[ ${#moArgs[@]} -gt 0 ]]; then
            for moTemp in "${moArgs[@]}"; do
                mo::escape moTemp "$moTemp"
                moFunctionCall="$moFunctionCall $moTemp"
            done
        fi
    fi

    mo::debug "Calling function: $moFunctionCall"

    #: Call the function in a subshell for safety. Employ the trick to preserve
    #: whitespace at the end of the output.
    moContent=$(
        export MO_FUNCTION_ARGS=(${moArgs[@]+"${moArgs[@]}"})
        echo -n "$moContent" | eval "$moFunctionCall ; moFunctionResult=\$? ; echo -n '.' ; exit \"\$moFunctionResult\""
    ) || {
        moFunctionResult=$?
        if [[ -n "${MO_FAIL_ON_FUNCTION-}" && "$moFunctionResult" != 0 ]]; then
            mo::error "Function failed with status code $moFunctionResult: $moFunctionCall" "$moFunctionResult"
        fi
    }

    local "$moTarget" && mo::indirect "$moTarget" "${moContent%.}"
}


# Internal: Check if a tag appears to have only whitespace before it and after
# it on a line. There must be a new line before and there must be a newline
# after or the end of a string
#
# No arguments.
#
# Returns 0 if this is a standalone tag, 1 otherwise.
mo::standaloneCheck() {
    local moContent moN moR moT

    moN=$'\n'
    moR=$'\r'
    moT=$'\t'

    #: Check the content before
    moContent=${MO_STANDALONE_CONTENT//"$moR"/"$moN"}

    #: By default, signal to the next check that this one failed
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

    #: Check the content after
    moContent=${MO_UNPARSED//"$moR"/"$moN"}
    moContent=${moContent%%"$moN"*}
    moContent=${moContent//"$moT"/}
    moContent=${moContent// /}

    if [[ -n "$moContent" ]]; then
        mo::debug "Not a standalone tag - non-whitespace detected after tag"

        return 1
    fi

    #: Signal to the next check that this tag removed content
    MO_STANDALONE_CONTENT=$'\n'

    return 0
}


# Internal: Process content before and after a tag. Remove prior whitespace up
# to the previous newline. Remove following whitespace up to and including the
# next newline.
#
# No arguments.
#
# Returns nothing.
mo::standaloneProcess() {
    local moI moTemp

    mo::debug "Standalone tag - processing content before and after tag"
    moI=$((${#MO_PARSED} - 1))
    mo::debug "zero done ${#MO_PARSED}"
    mo::escape moTemp "$MO_PARSED"
    mo::debug "$moTemp"

    while [[ "${MO_PARSED:$moI:1}" == " " || "${MO_PARSED:$moI:1}" == $'\t' ]]; do
        moI=$((moI - 1))
    done

    if [[ $((moI + 1)) != "${#MO_PARSED}" ]]; then
        MO_PARSED="${MO_PARSED:0:${moI}+1}"
    fi

    moI=0

    while [[ "${MO_UNPARSED:${moI}:1}" == " " || "${MO_UNPARSED:${moI}:1}" == $'\t' ]]; do
        moI=$((moI + 1))
    done

    if [[ "${MO_UNPARSED:${moI}:1}" == $'\r' ]]; then
        moI=$((moI + 1))
    fi

    if [[ "${MO_UNPARSED:${moI}:1}" == $'\n' ]]; then
        moI=$((moI + 1))
    fi

    if [[ "$moI" != 0 ]]; then
        MO_UNPARSED=${MO_UNPARSED:${moI}}
    fi
}


# Internal: Apply indentation before any line that has content in MO_UNPARSED.
#
# $1 - Destination variable name.
# $2 - The indentation string.
# $3 - The content that needs the indentation string prepended on each line.
#
# Returns nothing.
mo::indentLines() {
    local moContent moIndentation moResult moN moR moChunk

    moIndentation=$2
    moContent=$3

    if [[ -z "$moIndentation" ]]; then
        mo::debug "Not applying indentation, empty indentation"

        local "$1" && mo::indirect "$1" "$moContent"
        return
    fi

    if [[ -z "$moContent" ]]; then
        mo::debug "Not applying indentation, empty contents"

        local "$1" && mo::indirect "$1" "$moContent"
        return
    fi

    moResult=
    moN=$'\n'
    moR=$'\r'

    mo::debug "Applying indentation: '${moIndentation}'"

    while [[ -n "$moContent" ]]; do
        moChunk=${moContent%%"$moN"*}
        moChunk=${moChunk%%"$moR"*}
        moContent=${moContent:${#moChunk}}

        if [[ -n "$moChunk" ]]; then
            moResult="$moResult$moIndentation$moChunk"
        fi

        moResult="$moResult${moContent:0:1}"
        moContent=${moContent:1}
    done

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


# Internal: Get the content up to the end of the block by minimally parsing and
# balancing blocks. Returns the content before the end tag to the caller and
# removes the content + the end tag from MO_UNPARSED. This can change the
# delimiters, adjusting MO_OPEN_DELIMITER and MO_CLOSE_DELIMITER.
#
# $1 - Destination variable name
# $2 - Token string to match for a closing tag
#
# Returns nothing.
mo::getContentUntilClose() {
    local moChunk moResult moTemp moTokensString moTokens moTarget moTagStack moResultTemp

    moTarget=$1
    moTagStack=("$2")
    mo::debug "Get content until close tag: ${moTagStack[0]}"
    moResult=""

    while [[ -n "$MO_UNPARSED" ]] && [[ "${#moTagStack[@]}" -gt 0 ]]; do
        moChunk=${MO_UNPARSED%%"$MO_OPEN_DELIMITER"*}
        moResult="$moResult$moChunk"
        MO_UNPARSED=${MO_UNPARSED:${#moChunk}}

        if [[ -n "$MO_UNPARSED" ]]; then
            moResultTemp="$MO_OPEN_DELIMITER"
            MO_UNPARSED=${MO_UNPARSED:${#MO_OPEN_DELIMITER}}
            mo::getContentTrim moTemp
            moResultTemp="$moResultTemp$moTemp"
            mo::debug "First character within tag: ${MO_UNPARSED:0:1}"

            case "$MO_UNPARSED" in
                '#'*)
                    #: Increase block
                    moResultTemp="$moResultTemp${MO_UNPARSED:0:1}"
                    MO_UNPARSED=${MO_UNPARSED:1}
                    mo::getContentTrim moTemp
                    mo::getContentWithinTag moTemp "$MO_CLOSE_DELIMITER"
                    moResultTemp="$moResultTemp${moTemp[0]}"
                    moTagStack=("${moTemp[1]}" "${moTagStack[@]}")
                    ;;

                '^'*)
                    #: Increase block
                    moResultTemp="$moResultTemp${MO_UNPARSED:0:1}"
                    MO_UNPARSED=${MO_UNPARSED:1}
                    mo::getContentTrim moTemp
                    mo::getContentWithinTag moTemp "$MO_CLOSE_DELIMITER"
                    moResultTemp="$moResultTemp${moTemp[0]}"
                    moTagStack=("${moTemp[1]}" "${moTagStack[@]}")
                    ;;

                '>'*)
                    #: Partial - ignore
                    moResultTemp="$moResultTemp${MO_UNPARSED:0:1}"
                    MO_UNPARSED=${MO_UNPARSED:1}
                    mo::getContentTrim moTemp
                    mo::getContentWithinTag moTemp "$MO_CLOSE_DELIMITER"
                    moResultTemp="$moResultTemp${moTemp[0]}"
                    ;;

                '/'*)
                    #: Decrease block
                    moResultTemp="$moResultTemp${MO_UNPARSED:0:1}"
                    MO_UNPARSED=${MO_UNPARSED:1}
                    mo::getContentTrim moTemp
                    mo::getContentWithinTag moTemp "$MO_CLOSE_DELIMITER"
                    
                    if [[ "${moTagStack[0]}" == "${moTemp[1]}" ]]; then
                        moResultTemp="$moResultTemp${moTemp[0]}"
                        moTagStack=("${moTagStack[@]:1}")

                        if [[ "${#moTagStack[@]}" -eq 0 ]]; then
                            #: Erase all portions of the close tag
                            moResultTemp=""
                        fi
                    else
                        mo::errorNear "Unbalanced closing tag, expected: ${moTagStack[0]}" "${moTemp[0]}${MO_UNPARSED}"
                    fi
                    ;;

                '!'*)
                    #: Comment - ignore
                    mo::getContentComment moTemp
                    moResultTemp="$moResultTemp$moTemp"
                    ;;

                '='*)
                    #: Change delimiters
                    mo::getContentDelimiter moTemp
                    moResultTemp="$moResultTemp$moTemp"
                    ;;

                '&'*)
                    #: Unescaped - bypass one then ignore
                    moResultTemp="$moResultTemp${MO_UNPARSED:0:1}"
                    MO_UNPARSED=${MO_UNPARSED:1}
                    mo::getContentTrim moTemp
                    moResultTemp="$moResultTemp$moTemp"
                    mo::getContentWithinTag moTemp "$MO_CLOSE_DELIMITER"
                    moResultTemp="$moResultTemp${moTemp[0]}"
                    ;;

                *)
                    #: Normal variable - ignore
                    mo::getContentWithinTag moTemp "$MO_CLOSE_DELIMITER"
                    moResultTemp="$moResultTemp${moTemp[0]}"
                    ;;
            esac

            moResult="$moResult$moResultTemp"
        fi
    done

    MO_STANDALONE_CONTENT="$MO_STANDALONE_CONTENT$moResult"

    if mo::standaloneCheck; then
        moResultTemp=$MO_PARSED
        MO_PARSED=$moResult
        mo::standaloneProcess
        moResult=$MO_PARSED
        MO_PARSED=$moResultTemp
    fi

    local "$moTarget" && mo::indirect "$moTarget" "$moResult"
}


# Internal: Convert a list of tokens to a string
#
# $1 - Destination variable for the string
# $2-$@ - Token list
#
# Returns nothing.
mo::tokensToString() {
    local moTarget moString moTokens

    moTarget=$1
    shift 1
    moTokens=("$@")
    moString=$(declare -p moTokens)
    moString=${moString#*=}

    local "$moTarget" && mo::indirect "$moTarget" "$moString"
}


# Internal: Trims content from MO_UNPARSED, returns trimmed content.
#
# $1 - Destination variable
#
# Returns nothing.
mo::getContentTrim() {
    local moChar moResult
    
    moChar=${MO_UNPARSED:0:1}
    moResult=""

    while [[ "$moChar" == " " ]] || [[ "$moChar" == $'\r' ]] || [[ "$moChar" == $'\t' ]] || [[ "$moChar" == $'\n' ]]; do
        moResult="$moResult$moChar"
        MO_UNPARSED=${MO_UNPARSED:1}
        moChar=${MO_UNPARSED:0:1}
    done

    local "$1" && mo::indirect "$1" "$moResult"
}


# Get the content up to and including a close tag
#
# $1 - Destination variable
#
# Returns nothing.
mo::getContentComment() {
    local moResult

    mo::debug "Getting content for comment"
    moResult=${MO_UNPARSED%%"$MO_CLOSE_DELIMITER"*}
    MO_UNPARSED=${MO_UNPARSED:${#moResult}}

    if [[ "$MO_UNPARSED" == "$MO_CLOSE_DELIMITER"* ]]; then
        moResult="$moResult$MO_CLOSE_DELIMITER"
        MO_UNPARSED=${MO_UNPARSED#"$MO_CLOSE_DELIMITER"}
    fi

    local "$1" && mo::indirect "$1" "$moResult"
}


# Get the content up to and including a close tag. First two non-whitespace
# tokens become the new open and close tag.
#
# $1 - Destination variable
#
# Returns nothing.
mo::getContentDelimiter() {
    local moResult moTemp moOpen moClose

    mo::debug "Getting content for delimiter"
    moResult=""
    mo::getContentTrim moTemp
    moResult="$moResult$moTemp"
    mo::chomp moOpen "$MO_UNPARSED"
    MO_UNPARSED="${MO_UNPARSED:${#moOpen}}"
    moResult="$moResult$moOpen"
    mo::getContentTrim moTemp
    moResult="$moResult$moTemp"
    mo::chomp moClose "${MO_UNPARSED%%="$MO_CLOSE_DELIMITER"*}"
    MO_UNPARSED="${MO_UNPARSED:${#moClose}}"
    moResult="$moResult$moClose"
    mo::getContentTrim moTemp
    moResult="$moResult$moTemp"
    MO_OPEN_DELIMITER="$moOpen"
    MO_CLOSE_DELIMITER="$moClose"

    local "$1" && mo::indirect "$1" "$moResult"
}


# Get the content up to and including a close tag. First two non-whitespace
# tokens become the new open and close tag.
#
# $1 - Destination variable, an array
# $2 - Terminator string
#
# The array contents:
#     [0] The raw content within the tag
#     [1] The parsed tokens as a single string
#
# Returns nothing.
mo::getContentWithinTag() {
    local moUnparsed moTokens

    moUnparsed=${MO_UNPARSED}
    mo::tokenizeTagContents moTokens "$MO_CLOSE_DELIMITER"
    MO_UNPARSED=${MO_UNPARSED#"$MO_CLOSE_DELIMITER"}
    mo::tokensToString moTokensString "${moTokens[@]:1}"
    moParsed=${moUnparsed:0:$((${#moUnparsed} - ${#MO_UNPARSED}))}

    local "$1" && mo::indirectArray "$1" "$moParsed" "$moTokensString"
}


# Internal: Parse MO_UNPARSED and retrieve the content within the tag
# delimiters. Converts everything into an array of string values.
#
# $1 - Destination variable for the array of contents.
# $2 - Stop processing when this content is found.
#
# The list of tokens are in RPN form. The first item in the resulting array is
# the number of actual tokens (after combining command tokens) in the list.
#
# Given: a 'bc' "de\"\n" (f {g 'h'})
# Result: ([0]=4 [1]=NAME [2]=a [3]=VALUE [4]=bc [5]=VALUE [6]=$'de\"\n'
# [7]=NAME [8]=f [9]=NAME [10]=g [11]=VALUE [12]=h
# [13]=BRACE [14]=2 [15]=PAREN [16]=2
#
# Returns nothing
mo::tokenizeTagContents() {
    local moResult moTerminator moTemp moUnparsedOriginal moTokenCount

    moTerminator=$2
    moResult=()
    moUnparsedOriginal=$MO_UNPARSED
    moTokenCount=0
    mo::debug "Tokenizing tag contents until terminator: $moTerminator"

    while true; do
        mo::trimUnparsed

        case "$MO_UNPARSED" in
            "")
                mo::errorNear "Did not find matching terminator: $moTerminator" "$moUnparsedOriginal"
                ;;

            "$moTerminator"*)
                mo::debug "Found terminator"
                local "$1" && mo::indirectArray "$1" "$moTokenCount" ${moResult[@]+"${moResult[@]}"}
                return
                ;;

            '('*)
                #: Do not tokenize the open paren - treat this as RPL
                MO_UNPARSED=${MO_UNPARSED:1}
                mo::tokenizeTagContents moTemp ')'
                moResult=(${moResult[@]+"${moResult[@]}"} "${moTemp[@]:1}" PAREN "${moTemp[0]}")
                MO_UNPARSED=${MO_UNPARSED:1}
                ;;

            '{'*)
                #: Do not tokenize the open brace - treat this as RPL
                MO_UNPARSED=${MO_UNPARSED:1}
                mo::tokenizeTagContents moTemp '}'
                moResult=(${moResult[@]+"${moResult[@]}"} "${moTemp[@]:1}" BRACE "${moTemp[0]}")
                MO_UNPARSED=${MO_UNPARSED:1}
                ;;

            ')'* | '}'*)
                mo::errorNear "Unbalanced closing parenthesis or brace" "$MO_UNPARSED"
                ;;

            "'"*)
                mo::tokenizeTagContentsSingleQuote moTemp
                moResult=(${moResult[@]+"${moResult[@]}"} "${moTemp[@]}")
                ;;

            '"'*)
                mo::tokenizeTagContentsDoubleQuote moTemp
                moResult=(${moResult[@]+"${moResult[@]}"} "${moTemp[@]}")
                ;;

            *)
                mo::tokenizeTagContentsName moTemp
                moResult=(${moResult[@]+"${moResult[@]}"} "${moTemp[@]}")
                ;;
        esac

        mo::debug "Got chunk: ${moTemp[0]} ${moTemp[1]}"
        moTokenCount=$((moTokenCount + 1))
    done
}


# Internal: Get the contents of a variable name.
#
# $1 - Destination variable name for the token list (array of strings)
#
# Returns nothing
mo::tokenizeTagContentsName() {
    local moTemp

    mo::chomp moTemp "${MO_UNPARSED%%"$MO_CLOSE_DELIMITER"*}"
    moTemp=${moTemp%%(*}
    moTemp=${moTemp%%)*}
    moTemp=${moTemp%%\{*}
    moTemp=${moTemp%%\}*}
    MO_UNPARSED=${MO_UNPARSED:${#moTemp}}
    mo::trimUnparsed
    mo::debug "Parsed default token: $moTemp"

    local "$1" && mo::indirectArray "$1" "NAME" "$moTemp"
}


# Internal: Get the contents of a tag in double quotes. Parses the backslash
# sequences.
#
# $1 - Destination variable name for the token list (array of strings)
#
# Returns nothing.
mo::tokenizeTagContentsDoubleQuote() {
    local moResult moUnparsedOriginal

    moUnparsedOriginal=$MO_UNPARSED
    MO_UNPARSED=${MO_UNPARSED:1}
    moResult=
    mo::debug "Getting double quoted tag contents"

    while true; do
        if [[ -z "$MO_UNPARSED" ]]; then
            mo::errorNear "Unbalanced double quote" "$moUnparsedOriginal"
        fi

        case "$MO_UNPARSED" in
            '"'*)
                MO_UNPARSED=${MO_UNPARSED:1}
                local "$1" && mo::indirectArray "$1" "VALUE" "$moResult"
                return
                ;;

            \\b*)
                moResult="$moResult"$'\b'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\e*)
                #: Note, \e is ESC, but in Bash $'\E' is ESC.
                moResult="$moResult"$'\E'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\f*)
                moResult="$moResult"$'\f'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\n*)
                moResult="$moResult"$'\n'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\r*)
                moResult="$moResult"$'\r'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\t*)
                moResult="$moResult"$'\t'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\v*)
                moResult="$moResult"$'\v'
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            \\*)
                moResult="$moResult${MO_UNPARSED:1:1}"
                MO_UNPARSED=${MO_UNPARSED:2}
                ;;

            *)
                moResult="$moResult${MO_UNPARSED:0:1}"
                MO_UNPARSED=${MO_UNPARSED:1}
                ;;
        esac
    done
}


# Internal: Get the contents of a tag in single quotes. Only gets the raw
# value.
#
# $1 - Destination variable name for the token list (array of strings)
#
# Returns nothing.
mo::tokenizeTagContentsSingleQuote() {
    local moResult moUnparsedOriginal

    moUnparsedOriginal=$MO_UNPARSED
    MO_UNPARSED=${MO_UNPARSED:1}
    moResult=
    mo::debug "Getting single quoted tag contents"

    while true; do
        if [[ -z "$MO_UNPARSED" ]]; then
            mo::errorNear "Unbalanced single quote" "$moUnparsedOriginal"
        fi

        case "$MO_UNPARSED" in
            "'"*)
                MO_UNPARSED=${MO_UNPARSED:1}
                local "$1" && mo::indirectArray "$1" VALUE "$moResult"
                return
                ;;

            *)
                moResult="$moResult${MO_UNPARSED:0:1}"
                MO_UNPARSED=${MO_UNPARSED:1}
                ;;
        esac
    done
}


# Save the original command's path for usage later
MO_ORIGINAL_COMMAND="$(cd "${BASH_SOURCE[0]%/*}" || exit 1; pwd)/${BASH_SOURCE[0]##*/}"
MO_VERSION="3.0.7"

# If sourced, load all functions.
# If executed, perform the actions as expected.
if [[ "$0" == "${BASH_SOURCE[0]}" ]] || [[ -z "${BASH_SOURCE[0]}" ]]; then
    mo "$@"
fi
