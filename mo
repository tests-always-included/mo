#!/bin/bash
#
# Mo is a mustache template rendering software written in bash.  It inserts
# environment variables into templates.
#
# Learn more about mustache templates at https://mustache.github.io/
#
# Mo is under a MIT style licence with an additional non-advertising clause.
# See LICENSE.md for the full text.
#
# This is open source!  Please feel free to contribute.
#
# https://github.com/tests-always-included/mo


# Scan content until the right end tag is found.  Returns an array with the
# following members:
#     [0] = Content before end tag
#     [1] = End tag (complete tag)
#     [2] = Content after end tag
#
# Everything using this function uses the "standalone tags" logic.
#
# Parameters:
#     $1: Where to store the array
#     $2: Content
#     $3: Name of end tag
#     $4: If -z, do standalone tag processing before finishing
mustache-find-end-tag() {
    local CONTENT SCANNED

    # Find open tags
    SCANNED=""
    mustache-split CONTENT "$2" '{{' '}}'

    while [[ "${#CONTENT[@]}" -gt 1 ]]; do
        mustache-trim-whitespace TAG "${CONTENT[1]}"

        # Restore CONTENT[1] before we start using it
        CONTENT[1]='{{'"${CONTENT[1]}"'}}'

        case $TAG in
            '#'* | '^'*)
                # Start another block
                SCANNED="${SCANNED}${CONTENT[0]}${CONTENT[1]}"
                mustache-trim-whitespace TAG "${TAG:1}"
                mustache-find-end-tag CONTENT "${CONTENT[2]}" "$TAG" "loop"
                SCANNED="${SCANNED}${CONTENT[0]}${CONTENT[1]}"
                CONTENT=${CONTENT[2]}
                ;;

            '/'*)
                # End a block - could be ours
                mustache-trim-whitespace TAG "${TAG:1}"
                SCANNED="$SCANNED${CONTENT[0]}"

                if [[ "$TAG" == "$3" ]]; then
                    # Found our end tag
                    if [[ -z "$4" ]] && mustache-is-standalone STANDALONE_BYTES "$SCANNED" "${CONTENT[2]}" true; then
                        # This is also a standalone tag - clean up whitespace
                        # and move those whitespace bytes to the "tag" element
                        STANDALONE_BYTES=( $STANDALONE_BYTES )
                        CONTENT[1]="${SCANNED:${STANDALONE_BYTES[0]}}${CONTENT[1]}${CONTENT[2]:0:${STANDALONE_BYTES[1]}}"
                        SCANNED="${SCANNED:0:${STANDALONE_BYTES[0]}}"
                        CONTENT[2]="${CONTENT[2]:${STANDALONE_BYTES[1]}}"
                    fi

                    local "$1" && mustache-indirect-array "$1" "$SCANNED" "${CONTENT[1]}" "${CONTENT[2]}"
                    return 0
                fi

                SCANNED="$SCANNED${CONTENT[1]}"
                CONTENT=${CONTENT[2]}
                ;;

            *)
                # Ignore all other tags
                SCANNED="${SCANNED}${CONTENT[0]}${CONTENT[1]}"
                CONTENT=${CONTENT[2]}
                ;;
        esac

        mustache-split CONTENT "$CONTENT" '{{' '}}'
    done

    # Did not find our closing tag
    SCANNED="$SCANNED${CONTENT[0]}"
    local "$1" && mustache-indirect-array "$1" "${SCANNED}" "" ""
}


# Find the first index of a substring
#
# Parameters:
#     $1: Destination variable
#     $2: Haystack
#     $3: Needle
mustache-find-string() {
    local POS STRING

    STRING=${2%%$3*}
    [[ "$STRING" == "$2" ]] && POS=-1 || POS=${#STRING}
    local "$1" && mustache-indirect "$1" $POS
}


# Return a dotted name based on current context and target name
#
# Parameters:
#     $1: Target variable to store results
#     $2: Context name
#     $3: Desired variable name
mustache-full-tag-name() {
    if [[ -z "$2" ]]; then
        local "$1" && mustache-indirect "$1" "$3"
    else
        local "$1" && mustache-indirect "$1" "${2}.${3}"
    fi
}


# Return the content to parse.  Can be a list of partials for files or
# the content from stdin.
#
# Parameters:
#     $1: Variable name to assign this content back as
#     $2-*: File names (optional)
mustache-get-content() {
    local CONTENT FILENAME TARGET

    TARGET=$1
    shift
    if [[ "${#@}" -gt 0 ]]; then
        CONTENT=""

        for FILENAME in "$@"; do
            # This is so relative paths work from inside template files
            CONTENT="$CONTENT"'{{>'"$FILENAME"'}}'
        done
    else
        mustache-load-file CONTENT /dev/stdin
    fi

    local "$TARGET" && mustache-indirect "$TARGET" "$CONTENT"
}


# Indent a string, placing the indent at the beginning of every
# line that has any content.
#
# Parameters:
#     $1: Name of destination variable to get an array of lines
#     $2: The indent string
#     $3: The string to reindent
mustache-indent-lines() {
    local CONTENT FRAGMENT LEN POS_N POS_R RESULT TRIMMED

    RESULT=""
    LEN=$((${#3} - 1))
    CONTENT="${3:0:$LEN}" # Remove newline and dot from workaround - in mustache-partial

    if [ -z "$2" ]; then
        local "$1" && mustache-indirect "$1" "$CONTENT"
        return 0
    fi

    mustache-find-string POS_N "$CONTENT" $'\n'
    mustache-find-string POS_R "$CONTENT" $'\r'

    while [[ "$POS_N" -gt -1 ]] || [[ "$POS_R" -gt -1 ]]; do
        if [[ "$POS_N" -gt -1 ]]; then
            FRAGMENT="${CONTENT:0:$POS_N + 1}"
            CONTENT=${CONTENT:$POS_N + 1}
        else
            FRAGMENT="${CONTENT:0:$POS_R + 1}"
            CONTENT=${CONTENT:$POS_R + 1}
        fi

        mustache-trim-chars TRIMMED "$FRAGMENT" false true " " $'\t' $'\n' $'\r'

        if [ ! -z "$TRIMMED" ]; then
            FRAGMENT="$2$FRAGMENT"
        fi

        RESULT="$RESULT$FRAGMENT"
        mustache-find-string POS_N "$CONTENT" $'\n'
        mustache-find-string POS_R "$CONTENT" $'\r'
    done

    mustache-trim-chars TRIMMED "$CONTENT" false true " " $'\t'

    if [ ! -z "$TRIMMED" ]; then
        CONTENT="$2$CONTENT"
    fi

    RESULT="$RESULT$CONTENT"

    local "$1" && mustache-indirect "$1" "$RESULT"
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
    [[ "${MUSTACHE_TEST:0:10}" == "declare -a" ]] && return 0
    [[ "${MUSTACHE_TEST:0:10}" == "declare -A" ]] && return 0

    return 1
}


# Return 0 if the passed name is a function.
#
# Parameters:
#     $1: Name to check if it's a function
#
# Return code:
#     0 if the name is a function, 1 otherwise
mustache-is-function() {
    local FUNCTIONS NAME

    FUNCTIONS=$(declare -F)
    FUNCTIONS=( ${FUNCTIONS//declare -f /} )

    for NAME in ${FUNCTIONS[@]}; do
        if [[ "$NAME" == "$1" ]]; then
            return 0
        fi
    done

    return 1
}


# Determine if the tag is a standalone tag based on whitespace before and
# after the tag.
#
# Passes back a string containing two numbers in the format "BEFORE AFTER"
# like "27 10".  It indicates the number of bytes remaining in the "before"
# string (27) and the number of bytes to trim in the "after" string (10).
# Useful for string manipulation:
#
#     mustache-is-standalone RESULT "$before" "$after" false || return 0
#     RESULT_ARRAY=( $RESULT )
#     echo "${before:0:${RESULT_ARRAY[0]}}...${after:${RESULT_ARRAY[1]}}"
#
# Parameters:
#     $1: Variable to pass data back
#     $2: Content before the tag
#     $3: Content after the tag
#     $4: true/false: is this the beginning of the content?
mustache-is-standalone() {
    local AFTER_TRIMMED BEFORE_TRIMMED CHAR

    mustache-trim-chars BEFORE_TRIMMED "$2" false true " " $'\t'
    mustache-trim-chars AFTER_TRIMMED "$3" true false " " $'\t'
    CHAR=$((${#BEFORE_TRIMMED} - 1))
    CHAR=${BEFORE_TRIMMED:$CHAR}

    if [[ "$CHAR" != $'\n' ]] && [[ "$CHAR" != $'\r' ]]; then
        if [[ ! -z "$CHAR" ]] || ! $4; then
            return 1;
        fi
    fi

    CHAR=${AFTER_TRIMMED:0:1}

    if [[ "$CHAR" != $'\n' ]] && [[ "$CHAR" != $'\r' ]] && [[ ! -z "$CHAR" ]]; then
        return 2;
    fi

    if [[ "$CHAR" == $'\r' ]] && [[ "${AFTER_TRIMMED:1:1}" == $'\n' ]]; then
        CHAR="$CHAR"$'\n'
    fi

    local "$1" && mustache-indirect "$1" "$((${#BEFORE_TRIMMED})) $((${#3} + ${#CHAR} - ${#AFTER_TRIMMED}))"
}


# Join / implode an array
#
# Parameters:
#     $1: Variable name to receive the joined content
#     $2: Joiner
#     $3-$*: Elements to join
mustache-join() {
    local JOINER PART RESULT TARGET

    TARGET=$1
    JOINER=$2
    RESULT=$3
    shift 3

    for PART in "$@"; do
        RESULT="$RESULT$JOINER$PART"
    done

    local "$TARGET" && mustache-indirect "$TARGET" "$RESULT"
}

# Read a file
#
# Parameters:
#     $1: Variable name to receive the file's content
#     $2: Filename to load
mustache-load-file() {
    local CONTENT LEN

    # The subshell removes any trailing newlines.  We forcibly add
    # a dot to the content to preserve all newlines.
    # TODO: remove cat and replace with read loop?
    CONTENT=$(cat $2; echo '.')
    LEN=$((${#CONTENT} - 1))
    CONTENT=${CONTENT:0:$LEN}  # Remove last dot

    local "$1" && mustache-indirect "$1" "$CONTENT"
}


# Process a chunk of content some number of times.
#
# Parameters:
#     $1: Content to parse and reparse and reparse
#     $2: Tag prefix (context name)
#     $3-*: Names to insert into the parsed content
mustache-loop() {
    local CONTENT CONTEXT CONTEXT_BASE IGNORE

    CONTENT=$1
    CONTEXT_BASE=$2
    shift 2

    while [[ "${#@}" -gt 0 ]]; do
        mustache-full-tag-name CONTEXT "$CONTEXT_BASE" "$1"
        mustache-parse "$CONTENT" "$CONTEXT" false
        shift
    done
}


# Parse a block of text
#
# Parameters:
#     $1: Block of text to change
#     $2: Current name (the variable NAME for what {{.}} means)
#     $3: true when no content before this, false otherwise
mustache-parse() {
    # Keep naming variables MUSTACHE_* here to not overwrite needed variables
    # used in the string replacements
    local MUSTACHE_BLOCK MUSTACHE_CONTENT MUSTACHE_CURRENT MUSTACHE_IS_BEGINNING MUSTACHE_TAG

    MUSTACHE_CURRENT=$2
    MUSTACHE_IS_BEGINNING=$3

    # Find open tags
    mustache-split MUSTACHE_CONTENT "$1" '{{' '}}'

    while [[ "${#MUSTACHE_CONTENT[@]}" -gt 1 ]]; do
        mustache-trim-whitespace MUSTACHE_TAG "${MUSTACHE_CONTENT[1]}"

        case $MUSTACHE_TAG in
            '#'*)
                # Loop, if/then, or pass content through function
                # Sets context
                mustache-standalone-allowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                mustache-trim-whitespace MUSTACHE_TAG "${MUSTACHE_TAG:1}"
                mustache-find-end-tag MUSTACHE_BLOCK "$MUSTACHE_CONTENT" "$MUSTACHE_TAG"
                mustache-full-tag-name MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"

                if mustache-test "$MUSTACHE_TAG"; then
                    # Show / loop / pass through function
                    if mustache-is-function "$MUSTACHE_TAG"; then
                        # TODO: Consider piping the output to
                        # mustache-get-content so the lambda does not
                        # execute in a subshell?
                        MUSTACHE_CONTENT=$($MUSTACHE_TAG "${MUSTACHE_BLOCK[0]}")
                        mustache-parse "$MUSTACHE_CONTENT" "$MUSTACHE_CURRENT" false
                        MUSTACHE_CONTENT="${MUSTACHE_BLOCK[2]}"
                    elif mustache-is-array "$MUSTACHE_TAG"; then
                        eval 'mustache-loop "${MUSTACHE_BLOCK[0]}" "$MUSTACHE_TAG" "${!'"$MUSTACHE_TAG"'[@]}"'
                    else
                        mustache-parse "${MUSTACHE_BLOCK[0]}" "$MUSTACHE_CURRENT" false
                    fi
                fi

                MUSTACHE_CONTENT="${MUSTACHE_BLOCK[2]}"
                ;;

            '>'*)
                # Load partial - get name of file relative to cwd
                mustache-partial MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING "$MUSTACHE_CURRENT"
                ;;

            '/'*)
                # Closing tag - If hit in this loop, we simply ignore
                # Matching tags are found in mustache-find-end-tag
                mustache-standalone-allowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                ;;

            '^'*)
                # Display section if named thing does not exist
                mustache-standalone-allowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                mustache-trim-whitespace MUSTACHE_TAG "${MUSTACHE_TAG:1}"
                mustache-find-end-tag MUSTACHE_BLOCK "$MUSTACHE_CONTENT" "$MUSTACHE_TAG"
                mustache-full-tag-name MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"

                if ! mustache-test "$MUSTACHE_TAG"; then
                    mustache-parse "${MUSTACHE_BLOCK[0]}" "$MUSTACHE_CURRENT" false "$MUSTACHE_CURRENT"
                fi

                MUSTACHE_CONTENT="${MUSTACHE_BLOCK[2]}"
                ;;

            '!'*)
                # Comment - ignore the tag content entirely
                # Trim spaces/tabs before the comment
                mustache-standalone-allowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                ;;

            .)
                # Current content (environment variable or function)
                mustache-standalone-denied MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}"
                mustache-show "$MUSTACHE_CURRENT" "$MUSTACHE_CURRENT"
                ;;

            '=')
                # Change delimiters
                # Any two non-whitespace sequences separated by whitespace.
                # TODO
                mustache-standalone-allowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                ;;

            '{'*)
                # Unescaped - split on }}} not }}
                mustache-standalone-denied MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}"
                MUSTACHE_CONTENT="${MUSTACHE_TAG:1}"'}}'"$MUSTACHE_CONTENT"
                mustache-split MUSTACHE_CONTENT "$MUSTACHE_CONTENT" '}}}'
                mustache-trim-whitespace MUSTACHE_TAG "${MUSTACHE_CONTENT[0]}"
                mustache-full-tag-name MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"
                MUSTACHE_CONTENT=${MUSTACHE_CONTENT[1]}

                # Now show the value
                mustache-show "$MUSTACHE_TAG" "$MUSTACHE_CURRENT"
                ;;

            '&'*)
                # Unescaped
                mustache-standalone-denied MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}"
                mustache-trim-whitespace MUSTACHE_TAG "${MUSTACHE_TAG:1}"
                mustache-full-tag-name MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"
                mustache-show "$MUSTACHE_TAG" "$MUSTACHE_CURRENT"
                ;;

            *)
                # Normal environment variable or function call
                mustache-standalone-denied MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}"
                mustache-full-tag-name MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"
                mustache-show "$MUSTACHE_TAG" "$MUSTACHE_CURRENT"
                ;;
        esac

        MUSTACHE_IS_BEGINNING=false
        mustache-split MUSTACHE_CONTENT "$MUSTACHE_CONTENT" '{{' '}}'
    done

    echo -n "${MUSTACHE_CONTENT[0]}"
}


# Process a partial
#
# Indentation should be applied to the entire partial
#
# Prefix all variables
#
# Parameters:
#     $1: Name of destination "content" variable.
#     $2: Content before the tag that was not yet written
#     $3: Tag content
#     $4: Content after the tag
#     $5: true/false: is this the beginning of the content?
#     $6: Current context name
mustache-partial() {
    local MUSTACHE_CONTENT MUSTACHE_FILENAME MUSTACHE_INDENT MUSTACHE_LINE MUSTACHE_PARTIAL MUSTACHE_STANDALONE

    if mustache-is-standalone MUSTACHE_STANDALONE "$2" "$4" $5; then
        MUSTACHE_STANDALONE=( $MUSTACHE_STANDALONE )
        echo -n "${2:0:${MUSTACHE_STANDALONE[0]}}"
        MUSTACHE_INDENT=${2:${MUSTACHE_STANDALONE[0]}}
        MUSTACHE_CONTENT=${4:${MUSTACHE_STANDALONE[1]}}
    else
        MUSTACHE_INDENT=""
        echo -n "$2"
        MUSTACHE_CONTENT=$4
    fi

    mustache-trim-whitespace MUSTACHE_FILENAME "${3:1}"

    # Execute in subshell to preserve current cwd and environment
    (
        # TODO:  Remove dirname and use a function instead
        cd "$(dirname "$MUSTACHE_FILENAME")"
        mustache-indent-lines MUSTACHE_PARTIAL "$MUSTACHE_INDENT" "$(
            mustache-load-file MUSTACHE_PARTIAL "${MUSTACHE_FILENAME##*/}"

            # Fix bash handling of subshells
            # The extra dot is removed in mustache-indent-lines
            echo -n "${MUSTACHE_PARTIAL}."
        )"
        mustache-parse "$MUSTACHE_PARTIAL" "$6" true
    )

    local "$1" && mustache-indirect "$1" "$MUSTACHE_CONTENT"
}


# Show an environment variable or the output of a function.
#
# Limit/prefix any variables used
#
# Parameters:
#     $1: Name of environment variable or function
#     $2: Current context
mustache-show() {
    local JOINED MUSTACHE_NAME_PARTS

    if mustache-is-function "$1"; then
        CONTENT=$($1 "")
        mustache-parse "$CONTENT" "$2" false
        return 0
    fi

    mustache-split MUSTACHE_NAME_PARTS "$1" "."

    if [[ -z "${MUSTACHE_NAME_PARTS[1]}" ]]; then
        if mustache-is-array "$1"; then
            eval mustache-join JOINED "," "\${$1[@]}"
            echo -n "$JOINED"
        else
            echo -n "${!1}"
        fi
    else
        # Further subindexes are disallowed
        eval 'echo -n "${'"${MUSTACHE_NAME_PARTS[0]}"'['"${MUSTACHE_NAME_PARTS[1]%%.*}"']}"'
    fi
}


# Split a larger string into an array
#
# Parameters:
#     $1: Destination variable
#     $2: String to split
#     $3: Starting delimiter
#     $4: Ending delimiter (optional)
mustache-split() {
    local POS RESULT

    RESULT=( "$2" )
    mustache-find-string POS "${RESULT[0]}" "$3"

    if [[ "$POS" -ne -1 ]]; then
        # The first delimiter was found
        RESULT[1]=${RESULT[0]:$POS + ${#3}}
        RESULT[0]=${RESULT[0]:0:$POS}

        if [[ ! -z "$4" ]]; then
            mustache-find-string POS "${RESULT[1]}" "$4"

            if [[ "$POS" -ne -1 ]]; then
                # The second delimiter was found
                RESULT[2]="${RESULT[1]:$POS + ${#4}}"
                RESULT[1]="${RESULT[1]:0:$POS}"
            fi
        fi
    fi

    local "$1" && mustache-indirect-array "$1" "${RESULT[@]}"
}


# Handle the content for a standalone tag.  This means removing whitespace
# (not newlines) before a tag and whitespace and a newline after a tag.
# That is, assuming, that the line is otherwise empty.
#
# Parameters:
#     $1: Name of destination "content" variable.
#     $2: Content before the tag that was not yet written
#     $3: Tag content (not used)
#     $4: Content after the tag
#     $5: true/false: is this the beginning of the content?
mustache-standalone-allowed() {
    local STANDALONE_BYTES

    if mustache-is-standalone STANDALONE_BYTES "$2" "$4" $5; then
        STANDALONE_BYTES=( $STANDALONE_BYTES )
        echo -n "${2:0:${STANDALONE_BYTES[0]}}"
        local "$1" && mustache-indirect "$1" "${4:${STANDALONE_BYTES[1]}}"
    else
        echo -n "$2"
        local "$1" && mustache-indirect "$1" "$4"
    fi
}


# Handle the content for a tag that is never "standalone".  No adjustments
# are made for newlines and whitespace.
#
# Parameters:
#     $1: Name of destination "content" variable.
#     $2: Content before the tag that was not yet written
#     $3: Tag content (not used)
#     $4: Content after the tag
mustache-standalone-denied() {
    echo -n "$2"
    local "$1" && mustache-indirect "$1" "$4"
}


# Returns 0 (success) if the named thing is a function or if it is a non-empty
# environment variable.
#
# Do not use unprefixed variables here if possible as this needs to check
# if any name exists in the environment
#
# Parameters:
#     $1: Name of environment variable or function
#     $2: Current value (our context)
#
# Return code:
#     0 if the name is not empty, 1 otherwise
mustache-test() {
    # Test for functions
    mustache-is-function "$1" && return 0

    if mustache-is-array "$1"; then
        # Arrays must have at least 1 element
        eval '[[ "${#'"$1"'[@]}" -gt 0 ]]' && return 0
    else
        # Environment variables must not be empty
        [[ ! -z "${!1}" ]] && return 0
    fi

    return 1
}


# Trim the leading whitespace only
#
# Parameters:
#     $1: Name of destination variable
#     $2: The string
#     $3: true/false - trim front?
#     $4: true/false - trim end?
#     $5-*: Characters to trim
mustache-trim-chars() {
    local BACK CURRENT FRONT LAST TARGET VAR

    TARGET=$1
    CURRENT=$2
    FRONT=$3
    BACK=$4
    LAST=""
    shift # Remove target
    shift # Remove string
    shift # Remove trim front flag
    shift # Remove trim end flag

    while [[ "$CURRENT" != "$LAST" ]]; do
        LAST=$CURRENT

        for VAR in "$@"; do
            $FRONT && CURRENT="${CURRENT/#$VAR}"
            $BACK && CURRENT="${CURRENT/%$VAR}"
        done
    done

    local "$TARGET" && mustache-indirect "$TARGET" "$CURRENT"
}


# Trim leading and trailing whitespace from a string
#
# Parameters:
#     $1: Name of variable to store trimmed string
#     $2: The string
mustache-trim-whitespace() {
    local RESULT

    mustache-trim-chars RESULT "$2" true true $'\r' $'\n' $'\t' " "
    local "$1" && mustache-indirect "$1" "$RESULT"
}


mustache-get-content MUSTACHE_CONTENT "$@"
mustache-parse "$MUSTACHE_CONTENT" "" true
