#!/bin/bash

# Return 0 if the passed name is a function.  Function names are captured
# at the start of the program and are stored in the $MUSTACHE_FUNCTIONS array.
#
# Parameters:
#     $1: Name to check if it's a function
#
# Return code:
#     0 if the name is a function, 1 otherwise
mustache-is-function() {
    local NAME

    for NAME in ${MUSTACHE_FUNCTIONS[@]}; do
        if [[ "$NAME" == "$1" ]]; then
            return 0
        fi
    done

    return 1
}


# Process a chunk of content some number of times.
#
# Parameters:
#     $1: Destination variable name for the modified content
#     $2: Content to parse and reparse and reparse
#     $3: Ending tag for the parser
#     $4-*: Values to insert into the parsed content
mustache-loop() {
    local CONTENT DEST_NAME END_TAG MODIFIED_CONTENT

    DEST_NAME="$1"
    CONTENT="$2"
    END_TAG="$3"
    shift 3

    # This MUST loop at least once or assignment back to ${!DEST_NAME}
    # will not work.
    while [[ ${#@} -gt 0 ]]; do
        mustache-parse MODIFIED_CONTENT "$CONTENT" "$END_TAG" "$1"
        shift
    done

    local "$DEST_NAME" && mustache-indirect "$DEST_NAME" "$MODIFIED_CONTENT"
}


# Parse a block of text
#
# Parameters:
#     $1: Where to store content left after parsing
#     $2: Block of text to change
#     $3: Stop at this closing tag  (eg "/NAME")
#     $4: Current value (what {{.}} will mean)
mustache-parse() {
    # Keep naming variables MUSTACHE_* here to not overwrite needed variables
    # used in the string replacements
    local MUSTACHE_CONTENT MUSTACHE_CURRENT MUSTACHE_END_TAG MUSTACHE_TAG

    MUSTACHE_END_TAG="$3"
    MUSTACHE_CURRENT="$4"

    # Find open tags
    mustache-split MUSTACHE_CONTENT "$2" '{{' '}}'

    while [[ ${#MUSTACHE_CONTENT[@]} -gt 1 ]]; do
        echo -n "${MUSTACHE_CONTENT[0]}"
        mustache-trim MUSTACHE_TAG "${MUSTACHE_CONTENT[1]}"
        MUSTACHE_CONTENT="${MUSTACHE_CONTENT[2]}"

        case "$MUSTACHE_TAG" in
            '#'*)
                # Loop, if/then, or pass content through function
                # Sets context
                mustache-trim MUSTACHE_TAG "${MUSTACHE_TAG:1}"

                if mustache-test "$MUSTACHE_TAG"; then
                    # Show / loop / pass through function
                    if mustache-is-function "$MUSTACHE_TAG"; then
                        # This is slower - need to parse twice to avoid
                        # subshells.  First, pass content to function but
                        # the updated MUSTACHE_CONTENT is lost due to subshell.
                        $MUSTACHE_TAG "$(mustache-parse MUSTACHE_CONTENT "$MUSTACHE_CONTENT" "$MUSTACHE_TAG")"

                        # Secondly, update MUSTACHE_CONTENT but do not output.
                        mustache-parse MUSTACHE_CONTENT "$MUSTACHE_CONTENT" "$MUSTACHE_TAG" > /dev/null 2>&1
                    elif mustache-is-array "$MUSTACHE_TAG"; then
                        eval 'mustache-loop MUSTACHE_CONTENT "$MUSTACHE_CONTENT" "$MUSTACHE_TAG" "${'"$MUSTACHE_TAG"'[@]}"'
                    else
                        mustache-parse MUSTACHE_CONTENT "$MUSTACHE_CONTENT" "$MUSTACHE_TAG" "$(mustache-show "$MUSTACHE_TAG")"
                    fi
                else
                    # Do not show
                    mustache-parse MUSTACHE_CONTENT "$MUSTACHE_CONTENT" "$MUSTACHE_TAG" > /dev/null
                fi
                ;;

            '>'*)
                # Load partial - get name of file relative to cwd
                mustache-trim MUSTACHE_TAG "${MUSTACHE_TAG:1}"

                # Execute in subshell to preserve current cwd
                (
                    cd "$(dirname "$MUSTACHE_TAG")"
                    MUSTACHE_TAG=$(basename "$MUSTACHE_TAG")
                    MUSTACHE_TAG=$(cat "$MUSTACHE_TAG" 2>/dev/null)
                    mustache-parse MUSTACHE_TAG "$MUSTACHE_TAG" "" "$MUSTACHE_CURRENT"
                    echo -n $MUSTACHE_TAG
                )
                ;;

            '/'*)
                # Closing tag - If we hit MUSTACHE_END_TAG, we're done.
                mustache-trim MUSTACHE_TAG "${MUSTACHE_TAG:1}"

                if [[ "$MUSTACHE_TAG" == "$MUSTACHE_END_TAG" ]]; then
                    # Tag hit - done
                    local "$1" && mustache-indirect "$1" "$MUSTACHE_CONTENT"
                    return 0
                fi

                # If the tag does not match, we ignore this tag
                ;;

            '^'*)
                # Display section if named thing does not exist
                mustache-trim MUSTACHE_TAG "${MUSTACHE_TAG:1}"

                if mustache-test "$MUSTACHE_TAG"; then
                    # Do not show
                    mustache-parse MUSTACHE_CONTENT "$MUSTACHE_CONTENT" "$MUSTACHE_TAG" > /dev/null 2>&1
                else
                    # Show
                    mustache-parse MUSTACHE_CONTENT "$MUSTACHE_CONTENT" "$MUSTACHE_TAG"
                fi
                ;;

            '!'*)
                # Comment - ignore the tag entirely
                ;;

            .)
                # Current content (environment variable or function)
                echo -n "$MUSTACHE_CURRENT"
                ;;

            '{'*)
                # Unescaped - split on }}} not }}
                MUSTACHE_CONTENT="${MUSTACHE_TAG:1}"'}}'"$MUSTACHE_CONTENT"
                mustache-split MUSTACHE_CONTENT "$MUSTACHE_CONTENT" '}}}'
                mustache-trim MUSTACHE_TAG "${MUSTACHE_CONTENT[0]}"
                MUSTACHE_CONTENT="${MUSTACHE_CONTENT[1]}"

                # Now show the value
                mustache-show "$MUSTACHE_TAG"
                ;;

            *)
                # Normal environment variable or function call
                mustache-show "$MUSTACHE_TAG"
                ;;
        esac

        mustache-split MUSTACHE_CONTENT "$MUSTACHE_CONTENT" '{{' '}}'
    done

    echo -n "${MUSTACHE_CONTENT[0]}"
    local "$1" && mustache-indirect "$1" ""
}


# Show an environment variable or the output of a function.
#
# Parameters:
#     $1: Name of environment variable or function
mustache-show() {
    if mustache-is-function "$1"; then
        $1
    else
        echo -n "${!1}"
    fi
}


# Returns 0 (success) if the named thing is a function or if it is a non-empty
# environment variable.
#
# Do not use unprefixed variables here if possible as this needs to check
# if any name exists in the environment
#
# Parameters:
#     $1: Name of environment variable or function
#
# Return code:
#     0 if the name is not empty, 1 otherwise
mustache-test() {
    # Test for functions
    mustache-is-function "$1" && return 0

    if mustache-is-array "$1"; then
        # Arrays must have at least 1 element
        eval '[[ ${#'"$1"'} -gt 0 ]]' && return 0
    else
        # Environment variables must not be empty
        [[ ! -z "${!1}" ]] && return 0
    fi

    return 1
}


# Determine if a given environment variable exists and if it is an array.
#
# Parameters:
#     $1: Name of environment variable
#
# Return code:
#     0 if the name is not empty, 1 otherwise
mustache-is-array() {
    local MUSTACHE_TEST

    MUSTACHE_TEST=$(declare -p "$1" 2>/dev/null) || return 1
    [[ "${MUSTACHE_TEST:0:10}" == "declare -a" ]] || return 1
}


# Trim leading and trailing whitespace from a string
#
# Parameters:
#     $1: Name of variable to store trimmed string
#     $2: The string
mustache-trim() {
    local CR CURRENT MODIFIED NEEDLE NL TAB SPACE VAR

    CR="$'\r'"
    NL="$'\n'"
    TAB="$'\t'"
    SPACE=" "
    CURRENT="$2"
    LAST=""

    while [[ "$CURRENT" != "$LAST" ]]; do
        LAST="$CURRENT"

        for VAR in CR NL TAB SPACE; do
            NEEDLE="${!VAR}"
            CURRENT="${CURRENT/#$NEEDLE}"
            CURRENT="${CURRENT/%$NEEDLE}"
        done
    done

    local "$1" && mustache-indirect "$1" "$CURRENT"
}


# Split a larger string into an array
#
# Parameters:
#     $1: Destination variable
#     $2: String to split
#     $3: Starting delimeter
#     $4: Ending delimeter (optional)
mustache-split() {
    local POS RESULT

    RESULT=( "$2" )
    mustache-find-string POS "${RESULT[0]}" "$3"

    if [[ $POS -ne -1 ]]; then
        # The first delimeter was found
        RESULT[1]="${RESULT[0]:$POS + ${#3}}"
        RESULT[0]="${RESULT[0]:0:$POS}"

        if [[ ! -z "$4" ]]; then
            mustache-find-string POS "${RESULT[1]}" "$4"

            if [[ $POS -ne -1 ]]; then
                # The second delimeter was found
                RESULT[2]="${RESULT[1]:$POS + ${#4}}"
                RESULT[1]="${RESULT[1]:0:$POS}"
            fi
        fi
    fi

    local "$1" && mustache-indirect-array "$1" "${RESULT[@]}"
}

# Find the first index of a substring
#
# Parameters:
#     $1: Destination variable
#     $2: Haystack
#     $3: Needle
mustache-find-string() {
    local POS STRING

    STRING="${2%%$3*}"
    [[ "$STRING" == "$2" ]] && POS=-1 || POS=${#STRING}
    local "$1" && mustache-indirect "$1" $POS
}


# Send a variable up to caller of a function
#
# Parameters:
#     $1: Variable name
#     $2: Value
mustache-indirect() {
    unset -v "$1"
    printf -v "$1" '%s' "$2"
}


# Send an array up to caller of a function
#
# Parameters:
#     $1: Variable name
#     $2-*: Array elements
mustache-indirect-array() {
    unset -v "$1"
    eval $1=\(\"\${@:2}\"\)
}


# Return the content to parse.  Can be a list of partials for files or
# the content from stdin.
#
# Parameters:
#     $1: Variable name to assign this content back as
#     $2-*: File names (optional)
mustache-get-content() {
    local CONTENT FILENAME TARGET

    TARGET="$1"
    shift
    if [[ ${#@} -gt 0 ]]; then
        CONTENT=""

        for FILENAME in ${1+"$@"}; do
            CONTENT="$CONTENT"'{{>'"$FILENAME"'}}'
        done
    else
        # Workaround to avoid newlines being gobbled by the subshell
        CONTENT="$(cat -; echo .)"
        CONTENT=${CONTENT:0: -1}
    fi

    local "$TARGET" && mustache-indirect "$TARGET" "$CONTENT"
}


# Save the list of functions as an array
MUSTACHE_FUNCTIONS=$(declare -F)
MUSTACHE_FUNCTIONS=( ${MUSTACHE_FUNCTIONS//declare -f /} )
mustache-get-content MUSTACHE_CONTENT ${1+"$@"}
mustache-parse MUSTACHE_CONTENT "$MUSTACHE_CONTENT"
