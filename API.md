API / Function Documentation
============================

This documentation is generated automatically from the source of [mo] thanks to [tomdoc.sh].


`mo()`
------

Public: Template parser function.  Writes templates to stdout.

* $0 - Name of the mo file, used for getting the help message.
* $@ - Filenames to parse.

Returns nothing.


`mo::debug()`
-------------

Internal: Show a debug message

* $1 - The debug message to show

Returns nothing.


`mo::debugShowState()`
----------------------

Internal: Show a debug message and internal state information

No arguments

Returns nothing.


`mo::error()`
-------------

Internal: Show an error message and exit

* $1 - The error message to show
* $2 - Error code

Returns nothing. Exits the program.


`mo::errorNear()`
-----------------

Internal: Show an error message with a snippet of context and exit

* $1 - The error message to show
* $2 - The starting point
* $3 - Error code

Returns nothing. Exits the program.


`mo::usage()`
-------------

Internal: Displays the usage for mo.  Pulls this from the file that contained the `mo` function.  Can only work when the right filename comes is the one argument, and that only happens when `mo` is called with `$0` set to this file.

* $1 - Filename that has the help message

Returns nothing.


`mo::content()`
---------------

Internal: Fetches the content to parse into MO_UNPARSED.  Can be a list of partials for files or the content from stdin.

* $1 - Destination variable name
* $2-@ - File names (optional), read from stdin otherwise

Returns nothing.


`mo::contentFile()`
-------------------

Internal: Read a file into MO_UNPARSED.

* $1 - Destination variable name.
* $2 - Filename to load - if empty, defaults to /dev/stdin

Returns nothing.


`mo::indirect()`
----------------

Internal: Send a variable up to the parent of the caller of this function.

* $1 - Variable name
* $2 - Value

Examples

    callFunc () {
        local "$1" && mo::indirect "$1" "the value"
    }
    callFunc dest
    echo "$dest"  # writes "the value"

Returns nothing.


`mo::indirectArray()`
---------------------

Internal: Send an array as a variable up to caller of a function

* $1 - Variable name
* $2-@ - Array elements

Examples

    callFunc () {
        local myArray=(one two three)
        local "$1" && mo::indirectArray "$1" "${myArray[@]}"
    }
    callFunc dest
    echo "${dest[@]}" # writes "one two three"

Returns nothing.


`mo::trimUnparsed()`
--------------------

Internal: Trim leading characters from MO_UNPARSED

Returns nothing.


`mo::chomp()`
-------------

Internal: Remove whitespace and content after whitespace

* $1 - Name of the destination variable
* $2 - The string to chomp

Returns nothing.


`mo::parse()`
-------------

Public: Parses text, interpolates mustache tags. Utilizes the current value of MO_OPEN_DELIMITER, MO_CLOSE_DELIMITER, and MO_STANDALONE_CONTENT. Those three variables shouldn't be changed by user-defined functions.

* $1 - Destination variable name - where to store the finished content
* $2 - Content to parse
* $3 - Preserve standalone status/content - truthy if not empty. When set to a value, that becomes the standalone content value

Returns nothing.


`mo::parseInternal()`
---------------------

Internal: Parse MO_UNPARSED, writing content to MO_PARSED. Interpolates mustache tags.

No arguments

Returns nothing.


`mo::parseBlock()`
------------------

Internal: Handle parsing a block

* $1 - Invert condition ("true" or "false")

Returns nothing


`mo::parseBlockFunction()`
--------------------------

Internal: Handle parsing a block whose first argument is a function

* $1 - Invert condition ("true" or "false")
* $2-@ - The parsed tokens from inside the block tags

Returns nothing


`mo::parseBlockArray()`
-----------------------

Internal: Handle parsing a block whose first argument is an array

* $1 - Invert condition ("true" or "false")
* $2-@ - The parsed tokens from inside the block tags

Returns nothing


`mo::parseBlockValue()`
-----------------------

Internal: Handle parsing a block whose first argument is a value

* $1 - Invert condition ("true" or "false")
* $2-@ - The parsed tokens from inside the block tags

Returns nothing


`mo::parsePartial()`
--------------------

Internal: Handle parsing a partial

No arguments.

Indentation will be applied to the entire partial's contents before parsing. This indentation is based on the whitespace that ends the previously parsed content.

Returns nothing


`mo::parseComment()`
--------------------

Internal: Handle parsing a comment

No arguments.

Returns nothing


`mo::parseDelimiter()`
----------------------

Internal: Handle parsing the change of delimiters

No arguments.

Returns nothing


`mo::parseValue()`
------------------

Internal: Handle parsing value or function call

No arguments.

Returns nothing


`mo::isFunction()`
------------------

Internal: Determine if the given name is a defined function.

* $1 - Function name to check

Be extremely careful.  Even if strict mode is enabled, it is not honored in newer versions of Bash.  Any errors that crop up here will not be caught automatically.

Examples

    moo () {
        echo "This is a function"
    }
    if mo::isFunction moo; then
        echo "moo is a defined function"
    fi

Returns 0 if the name is a function, 1 otherwise.


`mo::isArray()`
---------------

Internal: Determine if a given environment variable exists and if it is an array.

* $1 - Name of environment variable

Be extremely careful.  Even if strict mode is enabled, it is not honored in newer versions of Bash.  Any errors that crop up here will not be caught automatically.

Examples

    var=(abc)
    if moIsArray var; then
       echo "This is an array"
       echo "Make sure you don't accidentally use \$var"
    fi

Returns 0 if the name is not empty, 1 otherwise.


`mo::isArrayIndexValid()`
-------------------------

Internal: Determine if an array index exists.

* $1 - Variable name to check
* $2 - The index to check

Has to check if the variable is an array and if the index is valid for that type of array.

Returns true (0) if everything was ok, 1 if there's any condition that fails.


`mo::isVarSet()`
----------------

Internal: Determine if a variable is assigned, even if it is assigned an empty value.

* $1 - Variable name to check.

Can not use logic like this in case invalid variable names are passed.      [[ "${!1-a}" == "${!1-b}" ]]

Returns true (0) if the variable is set, 1 if the variable is unset.


`mo::isTruthy()`
----------------

Internal: Determine if a value is considered truthy.

* $1 - The value to test
* $2 - Invert the value, either "true" or "false"

Returns true (0) if truthy, 1 otherwise.


`mo::evaluate()`
----------------

Internal: Convert token list to values

* $1 - Destination variable name
* $2-@ - Tokens to convert

Sample call:

      mo::evaluate dest NAME username VALUE abc123 PAREN 2

Returns nothing.


`mo::evaluateListOfSingles()`
-----------------------------

Internal: Convert an argument list to individual values.

* $1 - Destination variable name
* $2-@ - A list of argument types and argument name/value.

This assumes each value is separate from the rest. In contrast, mo::evaluate will pass all arguments to a function if the first value is a function.

Sample call:

      mo::evaluateListOfSingles dest NAME username VALUE abc123

Returns nothing.


`mo::evaluateSingle()`
----------------------

Internal: Evaluate a single argument

* $1 - Name of variable for result
* $2 - Type of argument, either NAME or VALUE
* $3 - Argument

Returns nothing


`mo::evaluateKey()`
-------------------

Internal: Return the value for @key based on current's name

* $1 - Name of variable for result

Returns nothing


`mo::evaluateVariable()`
------------------------

Internal: Handle a variable name

* $1 - Destination variable name
* $2 - Variable name

Returns nothing.


`mo::findVariableName()`
------------------------

Internal: Find the name of a variable to use

* $1 - Destination variable name, receives an array
* $2 - Variable name from the template

The array contains the following values
    * [0] - Variable name
    * [1] - Array index, or empty string

Example variables      a="a"
      b="b"
      c=("c.0" "c.1")
      d=([b]="d.b" [d]="d.d")

Given these inputs (function input, current value), produce these outputs      a c => a
      a c.0 => a
      b d => d.b
      b d.d => d.b
      a d => d.a
      a d.d => d.a
      c.0 d => c.0
      d.b d => d.b
      '' c => c
      '' c.0 => c.0
 Returns nothing.


`mo::join()`
------------

Internal: Join / implode an array

* $1    - Variable name to receive the joined content
* $2    - Joiner
* $3-@ - Elements to join

Returns nothing.


`mo::evaluateFunction()`
------------------------

Internal: Call a function.

* $1 - Variable for output
* $2 - Content to pass
* $3 - Function to call
* $4-@ - Additional arguments as list of type, value/name

Returns nothing.


`mo::standaloneCheck()`
-----------------------

Internal: Check if a tag appears to have only whitespace before it and after it on a line. There must be a new line before and there must be a newline after or the end of a string

No arguments.

Returns 0 if this is a standalone tag, 1 otherwise.


`mo::standaloneProcess()`
-------------------------

Internal: Process content before and after a tag. Remove prior whitespace up to the previous newline. Remove following whitespace up to and including the next newline.

No arguments.

Returns nothing.


`mo::indentLines()`
-------------------

Internal: Apply indentation before any line that has content in MO_UNPARSED.

* $1 - Destination variable name.
* $2 - The indentation string.
* $3 - The content that needs the indentation string prepended on each line.

Returns nothing.


`mo::escape()`
--------------

Internal: Escape a value

* $1 - Destination variable name
* $2 - Value to escape

Returns nothing


`mo::getContentUntilClose()`
----------------------------

Internal: Get the content up to the end of the block by minimally parsing and balancing blocks. Returns the content before the end tag to the caller and removes the content + the end tag from MO_UNPARSED. This can change the delimiters, adjusting MO_OPEN_DELIMITER and MO_CLOSE_DELIMITER.

* $1 - Destination variable name
* $2 - Token string to match for a closing tag

Returns nothing.


`mo::tokensToString()`
----------------------

Internal: Convert a list of tokens to a string

* $1 - Destination variable for the string
* $2-$@ - Token list

Returns nothing.


`mo::getContentTrim()`
----------------------

Internal: Trims content from MO_UNPARSED, returns trimmed content.

* $1 - Destination variable

Returns nothing.


`mo::getContentComment()`
-------------------------

Get the content up to and including a close tag

* $1 - Destination variable

Returns nothing.


`mo::getContentDelimiter()`
---------------------------

Get the content up to and including a close tag. First two non-whitespace tokens become the new open and close tag.

* $1 - Destination variable

Returns nothing.


`mo::getContentWithinTag()`
---------------------------

Get the content up to and including a close tag. First two non-whitespace tokens become the new open and close tag.

* $1 - Destination variable, an array
* $2 - Terminator string

The array contents:      [0] The raw content within the tag
      [1] The parsed tokens as a single string

Returns nothing.


`mo::tokenizeTagContents()`
---------------------------

Internal: Parse MO_UNPARSED and retrieve the content within the tag delimiters. Converts everything into an array of string values.

* $1 - Destination variable for the array of contents.
* $2 - Stop processing when this content is found.

The list of tokens are in RPN form. The first item in the resulting array is the number of actual tokens (after combining command tokens) in the list.

Given: a 'bc' "de\"\n" (f {g 'h'}) Result: ([0]=4 [1]=NAME [2]=a [3]=VALUE [4]=bc [5]=VALUE [6]=$'de\"\n' [7]=NAME [8]=f [9]=NAME [10]=g [11]=VALUE [12]=h [13]=BRACE [14]=2 [15]=PAREN [16]=2

Returns nothing


`mo::tokenizeTagContentsName()`
-------------------------------

Internal: Get the contents of a variable name.

* $1 - Destination variable name for the token list (array of strings)

Returns nothing


`mo::tokenizeTagContentsDoubleQuote()`
--------------------------------------

Internal: Get the contents of a tag in double quotes. Parses the backslash sequences.

* $1 - Destination variable name for the token list (array of strings)

Returns nothing.


`mo::tokenizeTagContentsSingleQuote()`
--------------------------------------

Internal: Get the contents of a tag in single quotes. Only gets the raw value.

* $1 - Destination variable name for the token list (array of strings)

Returns nothing.


`MO_ORIGINAL_COMMAND`
---------------------

Save the original command's path for usage later


[mo]: ./mo
[tomdoc.sh]: https://github.com/tests-always-included/tomdoc.sh
