API / Function Documentation
============================

This documentation is generated automatically from the source of [mo] thanks to [tomdoc.sh].


mo()
----

Public: Template parser function.  Writes templates to stdout.

* $0             - Name of the mo file, used for getting the help message.
* --fail-not-set - Fail upon expansion of an unset variable.  Default behavior is to silently ignore and expand into empty string.
* --false        - Treat "false" as an empty value.  You may set the MO_FALSE_IS_EMPTY environment variable instead to a non-empty value to enable this behavior.
* --help         - Display a help message.
* --source=FILE  - Source a file into the environment before processint template files.
* --             - Used to indicate the end of options.  You may optionally use this when filenames may start with two hyphens.
* $@             - Filenames to parse.

Mo uses the following environment variables:

* MO_FAIL_ON_UNSET    - When set to a non-empty value, expansion of an unset env variable will be aborted with an error.
* MO_FALSE_IS_EMPTY   - When set to a non-empty value, the string "false" will be treated as an empty value for the purposes of conditionals.
* MO_ORIGINAL_COMMAND - Used to find the `mo` program in order to generate a help message.

Returns nothing.


files
-----

After we encounter two hyphens together, all the rest of the arguments are files.


MO_FAIL_ON_UNSET
----------------

shellcheck disable=SC2030


MO_FALSE_IS_EMPTY
-----------------

shellcheck disable=SC2030


doubleHyphens
-------------

Set a flag indicating we've encountered double hyphens


files
-----

Every arg that is not a flag or a option should be a file


moFindEndTag()
--------------

Internal: Scan content until the right end tag is found.  Creates an array with the following members:

    [0] = Content before end tag
    [1] = End tag (complete tag)
    [2] = Content after end tag

Everything using this function uses the "standalone tags" logic.

* $1 - Name of variable for the array
* $2 - Content
* $3 - Name of end tag
* $4 - If -z, do standalone tag processing before finishing

Returns nothing.


moFindString()
--------------

Internal: Find the first index of a substring.  If not found, sets the index to -1.

* $1 - Destination variable for the index
* $2 - Haystack
* $3 - Needle

Returns nothing.


moFullTagName()
---------------

Internal: Generate a dotted name based on current context and target name.

* $1 - Target variable to store results
* $2 - Context name
* $3 - Desired variable name

Returns nothing.


moGetContent()
--------------

Internal: Fetches the content to parse into a variable.  Can be a list of partials for files or the content from stdin.

* $1   - Variable name to assign this content back as
* $2-@ - File names (optional)

Returns nothing.


moIndentLines()
---------------

Internal: Indent a string, placing the indent at the beginning of every line that has any content.

* $1 - Name of destination variable to get an array of lines
* $2 - The indent string
* $3 - The string to reindent

Returns nothing.


moIndirect()
------------

Internal: Send a variable up to the parent of the caller of this function.

* $1 - Variable name
* $2 - Value

Examples

    callFunc () {
        local "$1" && moIndirect "$1" "the value"
    }
    callFunc dest
    echo "$dest"  # writes "the value"

Returns nothing.


moIndirectArray()
-----------------

Internal: Send an array as a variable up to caller of a function

* $1   - Variable name
* $2-@ - Array elements

Examples

    callFunc () {
        local myArray=(one two three)
        local "$1" && moIndirectArray "$1" "${myArray[@]}"
    }
    callFunc dest
    echo "${dest[@]}" # writes "one two three"

Returns nothing.


moIsArray()
-----------

Internal: Determine if a given environment variable exists and if it is an array.

* $1 - Name of environment variable

Be extremely careful.  Even if strict mode is enabled, it is not honored in newer versions of Bash.  Any errors that crop up here will not be caught automatically.

Examples

    var=(abc)
    if moIsArray var; the
       echo "This is an array"
       echo "Make sure you don't accidentally use $var"
    fi

Returns 0 if the name is not empty, 1 otherwise.


moIsFunction()
--------------

Internal: Determine if the given name is a defined function.

* $1 - Function name to check

Be extremely careful.  Even if strict mode is enabled, it is not honored in newer versions of Bash.  Any errors that crop up here will not be caught automatically.

Examples

    moo () {
        echo "This is a function"
    }
    if moIsFunction moo; then
        echo "moo is a defined function"
    fi

Returns 0 if the name is a function, 1 otherwise.


moIsStandalone()
----------------

Internal: Determine if the tag is a standalone tag based on whitespace before and after the tag.

Passes back a string containing two numbers in the format "BEFORE AFTER" like "27 10".  It indicates the number of bytes remaining in the "before" string (27) and the number of bytes to trim in the "after" string (10). Useful for string manipulation:

* $1 - Variable to set for passing data back
* $2 - Content before the tag
* $3 - Content after the tag
* $4 - true/false: is this the beginning of the content?

Examples

    moIsStandalone RESULT "$before" "$after" false || return 0
    RESULT_ARRAY=( $RESULT )
    echo "${before:0:${RESULT_ARRAY[0]}}...${after:${RESULT_ARRAY[1]}}"

Returns nothing.


moJoin()
--------

Internal: Join / implode an array

* $1    - Variable name to receive the joined content
* $2    - Joiner
* $3-$* - Elements to join

Returns nothing.


moLoadFile()
------------

Internal: Read a file into a variable.

* $1 - Variable name to receive the file's content
* $2 - Filename to load

Returns nothing.


moLoop()
--------

Internal: Process a chunk of content some number of times.  Writes output to stdout.

* $1   - Content to parse repeatedly
* $2   - Tag prefix (context name)
* $3-@ - Names to insert into the parsed content

Returns nothing.


moParse()
---------

Internal: Parse a block of text, writing the result to stdout.

* $1 - Block of text to change
* $2 - Current name (the variable NAME for what {{.}} means)
* $3 - true when no content before this, false otherwise

Returns nothing.


moPartial()
-----------

Internal: Process a partial.

Indentation should be applied to the entire partial.

This sends back the "is beginning" flag because the newline after a standalone partial is consumed. That newline is very important in the middle of content. We send back this flag to reset the processing loop's `moIsBeginning` variable, so the software thinks we are back at the beginning of a file and standalone processing continues to work.

Prefix all variables.

* $1 - Name of destination variable. Element [0] is the content, [1] is the true/false flag indicating if we are at the beginning of content.
* $2 - Content before the tag that was not yet written
* $3 - Tag content
* $4 - Content after the tag
* $5 - true/false: is this the beginning of the content?
* $6 - Current context name

Returns nothing.


moShow()
--------

Internal: Show an environment variable or the output of a function to stdout.

Limit/prefix any variables used.

* $1 - Name of environment variable or function
* $2 - Current context

Returns nothing.


moSplit()
---------

Internal: Split a larger string into an array.

* $1 - Destination variable
* $2 - String to split
* $3 - Starting delimiter
* $4 - Ending delimiter (optional)

Returns nothing.


moStandaloneAllowed()
---------------------

Internal: Handle the content for a standalone tag.  This means removing whitespace (not newlines) before a tag and whitespace and a newline after a tag.  That is, assuming, that the line is otherwise empty.

* $1 - Name of destination "content" variable.
* $2 - Content before the tag that was not yet written
* $3 - Tag content (not used)
* $4 - Content after the tag
* $5 - true/false: is this the beginning of the content?

Returns nothing.


moStandaloneDenied()
--------------------

Internal: Handle the content for a tag that is never "standalone".  No adjustments are made for newlines and whitespace.

* $1 - Name of destination "content" variable.
* $2 - Content before the tag that was not yet written
* $3 - Tag content (not used)
* $4 - Content after the tag

Returns nothing.


moTest()
--------

Internal: Determines if the named thing is a function or if it is a non-empty environment variable.  When MO_FALSE_IS_EMPTY is set to a non-empty value, then "false" is also treated is an empty value.

Do not use variables without prefixes here if possible as this needs to check if any name exists in the environment

* $1                - Name of environment variable or function
* $2                - Current value (our context)
* MO_FALSE_IS_EMPTY - When set to a non-empty value, this will say the string value "false" is empty.

Returns 0 if the name is not empty, 1 otherwise.  When MO_FALSE_IS_EMPTY is set, this returns 1 if the name is "false".


moTestVarSet()
--------------

Internal: Determine if a variable is assigned, even if it is assigned an empty value.

* $1 - Variable name to check.

Returns true (0) if the variable is set, 1 if the variable is unset.


moTrimChars()
-------------

Internal: Trim the leading whitespace only.

* $1   - Name of destination variable
* $2   - The string
* $3   - true/false - trim front?
* $4   - true/false - trim end?
* $5-@ - Characters to trim

Returns nothing.


moTrimWhitespace()
------------------

Internal: Trim leading and trailing whitespace from a string.

* $1 - Name of variable to store trimmed string
* $2 - The string

Returns nothing.


moUsage()
---------

Internal: Displays the usage for mo.  Pulls this from the file that contained the `mo` function.  Can only work when the right filename comes is the one argument, and that only happens when `mo` is called with `$0` set to this file.

* $1 - Filename that has the help message

Returns nothing.


MO_ORIGINAL_COMMAND
-------------------

Save the original command's path for usage later


[mo]: ./mo
[tomdoc.sh]: https://github.com/mlafeldt/tomdoc.sh
