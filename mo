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
# $* - Filenames to parse.  Can use -h or --help as the only option
#      in order to show a help message.
#
# Returns nothing.
mo() (
    # This function executes in a subshell so IFS is reset
    local MUSTACHE_CONTENT

    IFS=$' \n\t'
    
    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--h|--he|--hel|--help)
                moUsage "$0"
                exit 0
                ;;
        esac
    fi

    moGetContent MUSTACHE_CONTENT "$@"
    moParse "$MUSTACHE_CONTENT" "" true
)


# Internal: Scan content until the right end tag is found.  Creates an array
# with the following members:
#
#   [0] = Content before end tag
#   [1] = End tag (complete tag)
#   [2] = Content after end tag
#
# Everything using this function uses the "standalone tags" logic.
#
# $1 - Name of variable for the array
# $2 - Content
# $3 - Name of end tag
# $4 - If -z, do standalone tag processing before finishing
#
# Returns nothing.
moFindEndTag() {
    local CONTENT SCANNED

    #: Find open tags
    SCANNED=""
    moSplit CONTENT "$2" '{{' '}}'

    while [[ "${#CONTENT[@]}" -gt 1 ]]; do
        moTrimWhitespace TAG "${CONTENT[1]}"

        #: Restore CONTENT[1] before we start using it
        CONTENT[1]='{{'"${CONTENT[1]}"'}}'

        case $TAG in
            '#'* | '^'*)
                #: Start another block
                SCANNED="${SCANNED}${CONTENT[0]}${CONTENT[1]}"
                moTrimWhitespace TAG "${TAG:1}"
                moFindEndTag CONTENT "${CONTENT[2]}" "$TAG" "loop"
                SCANNED="${SCANNED}${CONTENT[0]}${CONTENT[1]}"
                CONTENT=${CONTENT[2]}
                ;;

            '/'*)
                #: End a block - could be ours
                moTrimWhitespace TAG "${TAG:1}"
                SCANNED="$SCANNED${CONTENT[0]}"

                if [[ "$TAG" == "$3" ]]; then
                    #: Found our end tag
                    if [[ -z "$4" ]] && moIsStandalone STANDALONE_BYTES "$SCANNED" "${CONTENT[2]}" true; then
                        #: This is also a standalone tag - clean up whitespace
                        #: and move those whitespace bytes to the "tag" element
                        STANDALONE_BYTES=( $STANDALONE_BYTES )
                        CONTENT[1]="${SCANNED:${STANDALONE_BYTES[0]}}${CONTENT[1]}${CONTENT[2]:0:${STANDALONE_BYTES[1]}}"
                        SCANNED="${SCANNED:0:${STANDALONE_BYTES[0]}}"
                        CONTENT[2]="${CONTENT[2]:${STANDALONE_BYTES[1]}}"
                    fi

                    local "$1" && moIndirectArray "$1" "$SCANNED" "${CONTENT[1]}" "${CONTENT[2]}"
                    return 0
                fi

                SCANNED="$SCANNED${CONTENT[1]}"
                CONTENT=${CONTENT[2]}
                ;;

            *)
                #: Ignore all other tags
                SCANNED="${SCANNED}${CONTENT[0]}${CONTENT[1]}"
                CONTENT=${CONTENT[2]}
                ;;
        esac

        moSplit CONTENT "$CONTENT" '{{' '}}'
    done

    #: Did not find our closing tag
    SCANNED="$SCANNED${CONTENT[0]}"
    local "$1" && moIndirectArray "$1" "${SCANNED}" "" ""
}


# Internal: Find the first index of a substring.  If not found, sets the
# index to -1.
#
# $1 - Destination variable for the index
# $2 - Haystack
# $3 - Needle
#
# Returns nothing.
moFindString() {
    local POS STRING

    STRING=${2%%$3*}
    [[ "$STRING" == "$2" ]] && POS=-1 || POS=${#STRING}
    local "$1" && moIndirect "$1" $POS
}


# Internal: Generate a dotted name based on current context and target name.
#
# $1 - Target variable to store results
# $2 - Context name
# $3 - Desired variable name
#
# Returns nothing.
moFullTagName() {
    if [[ -z "$2" ]] || [[ "$2" == *.* ]]; then
        local "$1" && moIndirect "$1" "$3"
    else
        local "$1" && moIndirect "$1" "${2}.${3}"
    fi
}


# Internal: Fetches the content to parse into a variable.  Can be a list of
# partials for files or the content from stdin.
#
# $1   - Variable name to assign this content back as
# $2-* - File names (optional)
#
# Returns nothing.
moGetContent() {
    local CONTENT FILENAME TARGET

    TARGET=$1
    shift
    if [[ "${#@}" -gt 0 ]]; then
        CONTENT=""

        for FILENAME in "$@"; do
            #: This is so relative paths work from inside template files
            CONTENT="$CONTENT"'{{>'"$FILENAME"'}}'
        done
    else
        moLoadFile CONTENT /dev/stdin
    fi

    local "$TARGET" && moIndirect "$TARGET" "$CONTENT"
}


# Internal: Indent a string, placing the indent at the beginning of every
# line that has any content.
#
# $1 - Name of destination variable to get an array of lines
# $2 - The indent string
# $3 - The string to reindent
#
# Returns nothing.
moIndentLines() {
    local CONTENT FRAGMENT LEN POS_N POS_R RESULT TRIMMED

    RESULT=""
    LEN=$((${#3} - 1))

    #: This removes newline and dot from the workaround in moPartial
    CONTENT="${3:0:$LEN}"

    if [ -z "$2" ]; then
        local "$1" && moIndirect "$1" "$CONTENT"
        return 0
    fi

    moFindString POS_N "$CONTENT" $'\n'
    moFindString POS_R "$CONTENT" $'\r'

    while [[ "$POS_N" -gt -1 ]] || [[ "$POS_R" -gt -1 ]]; do
        if [[ "$POS_N" -gt -1 ]]; then
            FRAGMENT="${CONTENT:0:$POS_N + 1}"
            CONTENT=${CONTENT:$POS_N + 1}
        else
            FRAGMENT="${CONTENT:0:$POS_R + 1}"
            CONTENT=${CONTENT:$POS_R + 1}
        fi

        moTrimChars TRIMMED "$FRAGMENT" false true " " $'\t' $'\n' $'\r'

        if [ ! -z "$TRIMMED" ]; then
            FRAGMENT="$2$FRAGMENT"
        fi

        RESULT="$RESULT$FRAGMENT"
        moFindString POS_N "$CONTENT" $'\n'
        moFindString POS_R "$CONTENT" $'\r'
    done

    moTrimChars TRIMMED "$CONTENT" false true " " $'\t'

    if [ ! -z "$TRIMMED" ]; then
        CONTENT="$2$CONTENT"
    fi

    RESULT="$RESULT$CONTENT"

    local "$1" && moIndirect "$1" "$RESULT"
}


# Internal: Send a variable up to the parent of the caller of this function.
#
# $1 - Variable name
# $2 - Value
#
# Examples
#
#   callFunc () {
#       local "$1" && moIndirect "$1" "the value"
#   }
#   callFunc DEST
#   echo "$DEST"  # writes "the value"
#
# Returns nothing.
moIndirect() {
    unset -v "$1"
    printf -v "$1" '%s' "$2"
}


# Internal: Send an array as a variable up to caller of a function
#
# $1   - Variable name
# $2-* - Array elements
#
# Examples
#
#   callFunc () {
#       local myArray=(one two three)
#       local "$1" && moIndirectArray "$1" "${myArray[@]}"
#   }
#   callFunc DEST
#   echo "${DEST[@]}" # writes "one two three"
#
# Returns nothing.
moIndirectArray() {
    unset -v "$1"
    eval $1=\(\"\${@:2}\"\)
}


# Internal: Determine if a given environment variable exists and if it is
# an array.
#
# $1 - Name of environment variable
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
moIsArray() {
    local MUSTACHE_TEST

    MUSTACHE_TEST=$(declare -p "$1" 2>/dev/null) || return 1
    [[ "${MUSTACHE_TEST:0:10}" == "declare -a" ]] && return 0
    [[ "${MUSTACHE_TEST:0:10}" == "declare -A" ]] && return 0

    return 1
}


# Internal: Determine if the given name is a defined function.
#
# $1 - Function name to check
#
# Examples
#
#   moo () {
#       echo "This is a function"
#   }
#   if moIsFunction moo; then
#       echo "moo is a defined function"
#   fi
#
# Returns 0 if the name is a function, 1 otherwise.
moIsFunction() {
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


# Internal: Determine if the tag is a standalone tag based on whitespace
# before and after the tag.
#
# Passes back a string containing two numbers in the format "BEFORE AFTER"
# like "27 10".  It indicates the number of bytes remaining in the "before"
# string (27) and the number of bytes to trim in the "after" string (10).
# Useful for string manipulation:
#
# $1 - Variable to set for passing data back
# $2 - Content before the tag
# $3 - Content after the tag
# $4 - true/false: is this the beginning of the content?
#
# Examples
#
#   moIsStandalone RESULT "$before" "$after" false || return 0
#   RESULT_ARRAY=( $RESULT )
#   echo "${before:0:${RESULT_ARRAY[0]}}...${after:${RESULT_ARRAY[1]}}"
#
# Returns nothing.
moIsStandalone() {
    local AFTER_TRIMMED BEFORE_TRIMMED CHAR

    moTrimChars BEFORE_TRIMMED "$2" false true " " $'\t'
    moTrimChars AFTER_TRIMMED "$3" true false " " $'\t'
    CHAR=$((${#BEFORE_TRIMMED} - 1))
    CHAR=${BEFORE_TRIMMED:$CHAR}

    if [[ "$CHAR" != $'\n' ]] && [[ "$CHAR" != $'\r' ]]; then
        if [[ ! -z "$CHAR" ]] || ! $4; then
            return 1
        fi
    fi

    CHAR=${AFTER_TRIMMED:0:1}

    if [[ "$CHAR" != $'\n' ]] && [[ "$CHAR" != $'\r' ]] && [[ ! -z "$CHAR" ]]; then
        return 2
    fi

    if [[ "$CHAR" == $'\r' ]] && [[ "${AFTER_TRIMMED:1:1}" == $'\n' ]]; then
        CHAR="$CHAR"$'\n'
    fi

    local "$1" && moIndirect "$1" "$((${#BEFORE_TRIMMED})) $((${#3} + ${#CHAR} - ${#AFTER_TRIMMED}))"
}


# Internal: Join / implode an array
#
# $1    - Variable name to receive the joined content
# $2    - Joiner
# $3-$* - Elements to join
#
# Returns nothing.
moJoin() {
    local JOINER PART RESULT TARGET

    TARGET=$1
    JOINER=$2
    RESULT=$3
    shift 3

    for PART in "$@"; do
        RESULT="$RESULT$JOINER$PART"
    done

    local "$TARGET" && moIndirect "$TARGET" "$RESULT"
}

# Internal: Read a file into a variable.
#
# $1 - Variable name to receive the file's content
# $2 - Filename to load
#
# Returns nothing.
moLoadFile() {
    local CONTENT LEN

    # The subshell removes any trailing newlines.  We forcibly add
    # a dot to the content to preserve all newlines.
    # TODO: remove cat and replace with read loop?

    CONTENT=$(cat $2; echo '.')
    LEN=$((${#CONTENT} - 1))
    CONTENT=${CONTENT:0:$LEN}  # Remove last dot

    local "$1" && moIndirect "$1" "$CONTENT"
}


# Internal: Process a chunk of content some number of times.  Writes output
# to stdout.
#
# $1   - Content to parse repeatedly
# $2   - Tag prefix (context name)
# $3-* - Names to insert into the parsed content
#
# Returns nothing.
moLoop() {
    local CONTENT CONTEXT CONTEXT_BASE IGNORE

    CONTENT=$1
    CONTEXT_BASE=$2
    shift 2

    while [[ "${#@}" -gt 0 ]]; do
        moFullTagName CONTEXT "$CONTEXT_BASE" "$1"
        moParse "$CONTENT" "$CONTEXT" false
        shift
    done
}


# Internal: Parse a block of text, writing the result to stdout.
#
# $1 - Block of text to change
# $2 - Current name (the variable NAME for what {{.}} means)
# $3 - true when no content before this, false otherwise
#
# Returns nothing.
moParse() {
    # Keep naming variables MUSTACHE_* here to not overwrite needed variables
    # used in the string replacements
    local MUSTACHE_BLOCK MUSTACHE_CONTENT MUSTACHE_CURRENT MUSTACHE_IS_BEGINNING MUSTACHE_TAG

    MUSTACHE_CURRENT=$2
    MUSTACHE_IS_BEGINNING=$3

    # Find open tags
    moSplit MUSTACHE_CONTENT "$1" '{{' '}}'

    while [[ "${#MUSTACHE_CONTENT[@]}" -gt 1 ]]; do
        moTrimWhitespace MUSTACHE_TAG "${MUSTACHE_CONTENT[1]}"

        case $MUSTACHE_TAG in
            '#'*)
                # Loop, if/then, or pass content through function
                # Sets context
                moStandaloneAllowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                moTrimWhitespace MUSTACHE_TAG "${MUSTACHE_TAG:1}"
                moFindEndTag MUSTACHE_BLOCK "$MUSTACHE_CONTENT" "$MUSTACHE_TAG"
                moFullTagName MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"

                if moTest "$MUSTACHE_TAG"; then
                    # Show / loop / pass through function
                    if moIsFunction "$MUSTACHE_TAG"; then
                        #: TODO: Consider piping the output to moGetContent
                        #: so the lambda does not execute in a subshell?
                        MUSTACHE_CONTENT=$($MUSTACHE_TAG "${MUSTACHE_BLOCK[0]}")
                        moParse "$MUSTACHE_CONTENT" "$MUSTACHE_CURRENT" false
                        MUSTACHE_CONTENT="${MUSTACHE_BLOCK[2]}"
                    elif moIsArray "$MUSTACHE_TAG"; then
                        eval 'moLoop "${MUSTACHE_BLOCK[0]}" "$MUSTACHE_TAG" "${!'"$MUSTACHE_TAG"'[@]}"'
                    else
                        moParse "${MUSTACHE_BLOCK[0]}" "$MUSTACHE_CURRENT" false
                    fi
                fi

                MUSTACHE_CONTENT="${MUSTACHE_BLOCK[2]}"
                ;;

            '>'*)
                # Load partial - get name of file relative to cwd
                moPartial MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING "$MUSTACHE_CURRENT"
                ;;

            '/'*)
                # Closing tag - If hit in this loop, we simply ignore
                # Matching tags are found in moFindEndTag
                moStandaloneAllowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                ;;

            '^'*)
                # Display section if named thing does not exist
                moStandaloneAllowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                moTrimWhitespace MUSTACHE_TAG "${MUSTACHE_TAG:1}"
                moFindEndTag MUSTACHE_BLOCK "$MUSTACHE_CONTENT" "$MUSTACHE_TAG"
                moFullTagName MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"

                if ! moTest "$MUSTACHE_TAG"; then
                    moParse "${MUSTACHE_BLOCK[0]}" "$MUSTACHE_CURRENT" false "$MUSTACHE_CURRENT"
                fi

                MUSTACHE_CONTENT="${MUSTACHE_BLOCK[2]}"
                ;;

            '!'*)
                # Comment - ignore the tag content entirely
                # Trim spaces/tabs before the comment
                moStandaloneAllowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                ;;

            .)
                # Current content (environment variable or function)
                moStandaloneDenied MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}"
                moShow "$MUSTACHE_CURRENT" "$MUSTACHE_CURRENT"
                ;;

            '=')
                # Change delimiters
                # Any two non-whitespace sequences separated by whitespace.
                # TODO
                moStandaloneAllowed MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}" $MUSTACHE_IS_BEGINNING
                ;;

            '{'*)
                # Unescaped - split on }}} not }}
                moStandaloneDenied MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}"
                MUSTACHE_CONTENT="${MUSTACHE_TAG:1}"'}}'"$MUSTACHE_CONTENT"
                moSplit MUSTACHE_CONTENT "$MUSTACHE_CONTENT" '}}}'
                moTrimWhitespace MUSTACHE_TAG "${MUSTACHE_CONTENT[0]}"
                moFullTagName MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"
                MUSTACHE_CONTENT=${MUSTACHE_CONTENT[1]}

                # Now show the value
                moShow "$MUSTACHE_TAG" "$MUSTACHE_CURRENT"
                ;;

            '&'*)
                # Unescaped
                moStandaloneDenied MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}"
                moTrimWhitespace MUSTACHE_TAG "${MUSTACHE_TAG:1}"
                moFullTagName MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"
                moShow "$MUSTACHE_TAG" "$MUSTACHE_CURRENT"
                ;;

            *)
                # Normal environment variable or function call
                moStandaloneDenied MUSTACHE_CONTENT "${MUSTACHE_CONTENT[@]}"
                moFullTagName MUSTACHE_TAG "$MUSTACHE_CURRENT" "$MUSTACHE_TAG"
                moShow "$MUSTACHE_TAG" "$MUSTACHE_CURRENT"
                ;;
        esac

        MUSTACHE_IS_BEGINNING=false
        moSplit MUSTACHE_CONTENT "$MUSTACHE_CONTENT" '{{' '}}'
    done

    echo -n "${MUSTACHE_CONTENT[0]}"
}


# Internal: Process a partial.
#
# Indentation should be applied to the entire partial
#
# Prefix all variables.
#
# $1 - Name of destination "content" variable.
# $2 - Content before the tag that was not yet written
# $3 - Tag content
# $4 - Content after the tag
# $5 - true/false: is this the beginning of the content?
# $6 - Current context name
#
# Returns nothing.
moPartial() {
    local MUSTACHE_CONTENT MUSTACHE_FILENAME MUSTACHE_INDENT MUSTACHE_LINE MUSTACHE_PARTIAL MUSTACHE_STANDALONE

    if moIsStandalone MUSTACHE_STANDALONE "$2" "$4" $5; then
        MUSTACHE_STANDALONE=( $MUSTACHE_STANDALONE )
        echo -n "${2:0:${MUSTACHE_STANDALONE[0]}}"
        MUSTACHE_INDENT=${2:${MUSTACHE_STANDALONE[0]}}
        MUSTACHE_CONTENT=${4:${MUSTACHE_STANDALONE[1]}}
    else
        MUSTACHE_INDENT=""
        echo -n "$2"
        MUSTACHE_CONTENT=$4
    fi

    moTrimWhitespace MUSTACHE_FILENAME "${3:1}"

    # Execute in subshell to preserve current cwd and environment
    (
        # TODO:  Remove dirname and use a function instead
        cd "$(dirname "$MUSTACHE_FILENAME")"
        moIndentLines MUSTACHE_PARTIAL "$MUSTACHE_INDENT" "$(
            moLoadFile MUSTACHE_PARTIAL "${MUSTACHE_FILENAME##*/}"

            # Fix bash handling of subshells
            # The extra dot is removed in moIndentLines
            echo -n "${MUSTACHE_PARTIAL}."
        )"
        moParse "$MUSTACHE_PARTIAL" "$6" true
    )

    local "$1" && moIndirect "$1" "$MUSTACHE_CONTENT"
}


# Internal: Show an environment variable or the output of a function to
# stdout.
#
# Limit/prefix any variables used.
#
# $1 - Name of environment variable or function
# $2 - Current context
#
# Returns nothing.
moShow() {
    local JOINED MUSTACHE_NAME_PARTS

    if moIsFunction "$1"; then
        CONTENT=$($1 "")
        moParse "$CONTENT" "$2" false
        return 0
    fi

    moSplit MUSTACHE_NAME_PARTS "$1" "."

    if [[ -z "${MUSTACHE_NAME_PARTS[1]}" ]]; then
        if moIsArray "$1"; then
            eval moJoin JOINED "," "\${$1[@]}"
            echo -n "$JOINED"
        else
            echo -n "${!1}"
        fi
    else
        # Further subindexes are disallowed
        eval 'echo -n "${'"${MUSTACHE_NAME_PARTS[0]}"'['"${MUSTACHE_NAME_PARTS[1]%%.*}"']}"'
    fi
}


# Internal: Split a larger string into an array.
#
# $1 - Destination variable
# $2 - String to split
# $3 - Starting delimiter
# $4 - Ending delimiter (optional)
#
# Returns nothing.
moSplit() {
    local POS RESULT

    RESULT=( "$2" )
    moFindString POS "${RESULT[0]}" "$3"

    if [[ "$POS" -ne -1 ]]; then
        # The first delimiter was found
        RESULT[1]=${RESULT[0]:$POS + ${#3}}
        RESULT[0]=${RESULT[0]:0:$POS}

        if [[ ! -z "$4" ]]; then
            moFindString POS "${RESULT[1]}" "$4"

            if [[ "$POS" -ne -1 ]]; then
                # The second delimiter was found
                RESULT[2]="${RESULT[1]:$POS + ${#4}}"
                RESULT[1]="${RESULT[1]:0:$POS}"
            fi
        fi
    fi

    local "$1" && moIndirectArray "$1" "${RESULT[@]}"
}


# Internal: Handle the content for a standalone tag.  This means removing
# whitespace (not newlines) before a tag and whitespace and a newline after
# a tag.  That is, assuming, that the line is otherwise empty.
#
# $1 - Name of destination "content" variable.
# $2 - Content before the tag that was not yet written
# $3 - Tag content (not used)
# $4 - Content after the tag
# $5 - true/false: is this the beginning of the content?
#
# Returns nothing.
moStandaloneAllowed() {
    local STANDALONE_BYTES

    if moIsStandalone STANDALONE_BYTES "$2" "$4" $5; then
        STANDALONE_BYTES=( $STANDALONE_BYTES )
        echo -n "${2:0:${STANDALONE_BYTES[0]}}"
        local "$1" && moIndirect "$1" "${4:${STANDALONE_BYTES[1]}}"
    else
        echo -n "$2"
        local "$1" && moIndirect "$1" "$4"
    fi
}


# Internal: Handle the content for a tag that is never "standalone".  No
# adjustments are made for newlines and whitespace.
#
# $1 - Name of destination "content" variable.
# $2 - Content before the tag that was not yet written
# $3 - Tag content (not used)
# $4 - Content after the tag
#
# Returns nothing.
moStandaloneDenied() {
    echo -n "$2"
    local "$1" && moIndirect "$1" "$4"
}


# Internal: Determines if the named thing is a function or if it is a
# non-empty environment variable.
#
# Do not use variables without prefixes here if possible as this needs to
# check if any name exists in the environment
#
# $1 - Name of environment variable or function
# $2 - Current value (our context)
#
# Returns 0 if the name is not empty, 1 otherwise.
moTest() {
    # Test for functions
    moIsFunction "$1" && return 0

    if moIsArray "$1"; then
        # Arrays must have at least 1 element
        eval '[[ "${#'"$1"'[@]}" -gt 0 ]]' && return 0
    else
        # Environment variables must not be empty
        [[ ! -z "${!1}" ]] && return 0
    fi

    return 1
}


# Internal: Trim the leading whitespace only.
#
# $1   - Name of destination variable
# $2   - The string
# $3   - true/false - trim front?
# $4   - true/false - trim end?
# $5-* - Characters to trim
#
# Returns nothing.
moTrimChars() {
    local BACK CURRENT FRONT LAST TARGET VAR

    TARGET=$1
    CURRENT=$2
    FRONT=$3
    BACK=$4
    LAST=""
    shift 4 # Remove target, string, trim front flag, trim end flag

    while [[ "$CURRENT" != "$LAST" ]]; do
        LAST=$CURRENT

        for VAR in "$@"; do
            $FRONT && CURRENT="${CURRENT/#$VAR}"
            $BACK && CURRENT="${CURRENT/%$VAR}"
        done
    done

    local "$TARGET" && moIndirect "$TARGET" "$CURRENT"
}


# Internal: Trim leading and trailing whitespace from a string.
#
# $1 - Name of variable to store trimmed string
# $2 - The string
#
# Returns nothing.
moTrimWhitespace() {
    local RESULT

    moTrimChars RESULT "$2" true true $'\r' $'\n' $'\t' " "
    local "$1" && moIndirect "$1" "$RESULT"
}


# Internal: Displays the usage for mo.  Pulls this from the file that
# contained the `mo` function.  Can only work when the right filename
# comes is the one argument, and that only happens when `mo` is called
# with `$0` set to this file.
#
# $1 - Filename that has the help message
#
# Returns nothing.
moUsage() {
    grep '^#/' < "$1" | cut -c 4-
}


# If sourced, load all functions.
# If executed, perform the actions as expected.
if [[ "$0" == "$BASH_SOURCE" ]] || ! [[ -n "$BASH_SOURCE" ]]; then
    mo "$@"
fi
