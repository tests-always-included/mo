Mo - Mustache Templates in Bash
===============================

[Mustache] templates are simple, logic-less templates.  Because of their simplicity, they are able to be ported to many languages.  The syntax is quite simple.

    Hello, {{NAME}}.

    I hope your {{TIME_PERIOD}} was fun.

The above file is [`demo/fun-trip.mo`](demo/fun-trip.mo).  Let's try using this template some data from bash's environment.  Go to your checked out copy of the project and run a command like this:

    NAME=Tyler TIME_PERIOD=weekend ./mo demo/fun-trip.mo

Your result?

    Hello, Tyler.

    I hope your weekend was fun.

This bash version supports conditionals, functions (both as filters and as values), as well as indexed arrays (for iteration).  You are able to leverage these additional features by adding more information into the environment.  It is easiest to do this when you source `mo`.  See the [demo scripts](demo/) for further examples.


Requirements
------------

* Bash 3.x (the aim is to make it work on Macs)
* The "coreutils" package (`basename` and `cat`)
* ... that's it.  Why?  Because bash **can**!

If you intend to develop this and run the official specs, you also need node.js.


Installation
------------

There are a few ways you can install this tool.  How you install it depends on how you want to use it.


### Globally; For Everyone

You can install this file in `/usr/local/bin/` or `/usr/bin/` by simply downloading it, changing the permissions, then moving it to the right location.  Double check that your system's PATH includes the destination folder, otherwise users may have a hard time starting the command.

    # Download
    curl -sSL https://raw.githubusercontent.com/tests-always-included/mo/master/mo -o mo

    # Make executable
    chmod +x mo

    # Move to the right folder
    sudo mv mo /usr/local/bin/

    # Test
    echo "works" | mo


### Locally; For Yourself

This is very similar to installing it globally but it does not require root privileges.  It is very important that your PATH includes the destination folder otherwise it won't work.  Some local folders that are typically used are `~/bin/` and `~/.local/bin/`.

    # Download
    curl -sSL https://raw.githubusercontent.com/tests-always-included/mo/master/mo -o mo

    # Make executable
    chmod +x mo

    # Ensure destination folder exists
    mkdir -p ~/.local/bin/

    # Move to the right folder
    mv mo ~/.local/bin/

    # Test
    echo "works" | mo


### As A Library; For A Tool

Bash scripts can source `mo` to include the functionality in their own routines.  This usage typically would have `mo` saved to a `lib/` folder in an application and your other scripts would use `. lib/mo` to bring it into your project.

    # Download
    curl -sSL https://raw.githubusercontent.com/tests-always-included/mo/master/mo -o mo

    # Move into your project folder
    mv mo ~/projects/amazing-things/lib/

To allow it to work this way, you either should source the file (`. "lib/mo"`) or make it executable (`chmod +x lib/mo`) and run it from your scripts.


How to Use
----------

If you only plan using strings and numbers, nothing could be simpler.  In your shell script you can choose to export the variables.  The below script is [`demo/using-strings`](demo/using-strings).

    #!/usr/bin/env bash
    cd "$(dirname "$0")" # Go to the script's directory
    export TEST="This is a test"
    echo "Your message:  {{TEST}}" | ../mo

The result?  "Your message:  This is a test".

Using arrays adds a slight level of complexity.  *You must source `mo`.*  Look at [`demo/using-arrays`](demo/using-arrays).

    #!/usr/bin/env bash
    cd "$(dirname "$0")" # Go to the script's directory
    export ARRAY=( one two "three three three" four five )
    . ../mo # This loads the "mo" function
    cat << EOF | mo
    Here are the items in the array:
    {{#ARRAY}}
        * {{.}}
    {{/ARRAY}}
    EOF

The result?  You get a list of the five elements in the array.  It is vital that you source `mo` and run the function when you want arrays to work because you can not execute a command and have arrays passed to that command's environment.  Instead, we first source the file to load the function and then run the function directly.

There are more scripts available in the [demos directory](demo/) that could help illustrate how you would use this program.

There are additional features that the program supports. Try using `mo --help` to see what is available.

Please note that this command is written in Bash and pulls data from either the environment or (when using `--source`) from a text file that will be sourced and loaded into the environment, which means you will need to have Bash-style variables defined. Please see the examples in `demo/` for different ways you can use `mo`.


Enhancements
------------

In addition to many of the features built-in to Mustache, `mo` includes a number of unique features that make it a bit more powerful.

### Loop @key

`mo` implements Handlebar's `@key` references for outputting the key inside of a loop:

Env:
```bash
myarr=( foo bar )

# Bash v4+
declare -A myassoc
myassoc[hello]="mo"
myassoc[world]="is great"
```

Template:
```handlebars
{{#myarr}}
 - {{@key}} {{.}}
{{/myarr}}

{{#myassoc}}
 * {{@key}} {{.}}
{{/myassoc}}
```

Output:
```markdown
 - 0 foo
 - 1 bar

 * hello mo
 * world is great
```


### Helpers / Function Arguments

Function Arguments are not a part of the official Mustache implementation, and are more often associated with Handlebar's Helper functionality.

`mo` allows for passing strings to functions.

```handlebars
{{myfunc foo bar}}
```

For security reasons, these arguments are not immediately available to function calls without a flag.

#### with `--allow-function-arguments`

```bash
myfunc() {
    # Outputs "foo, bar"
    echo "$1, $2";
}
```

#### Using `$MO_FUNCTION_ARGS`

```bash
myfunc() {
    # Outputs "foo, bar"
    echo "${MO_FUNCTION_ARGS[0]}, ${MO_FUNCTION_ARGS[1]}";
}
```

### Triple Mustache, Parenthesis, and Quotes

Normally, triple mustache syntax, such as `{{{var}}}` will avoid HTML escaping of the variable. Because HTML escaping is not supported in `mo`, this is now used differently. Anything within braces will be looked up and the values will be concatenated together and the result will be treated as a value. Anything in parenthesis will be looked up, concatenated, and treated as a name. Also, anything in single quotes is passed as a value; double quoted things first are unescaped and then passed as a value.

```
# Example input
var=abc
user=admin
admin=Administrator
u=user
abc=([0]=zero [1]=one [2]=two)
```

| Mustache syntax | Resulting output | Notes |
|-----------------|------------------|-------|
| `{{var}}` | `abc` | Normal behavior |
| `{{var us}}` | `abcus` | Concatenation |
| `{{'var'}}` | `var` | Passing as a value |
| `{{"a\tb"}}` | `a       b` | There was an escaped tab in the value |
| `{{u}}` | `user` | Normal behavior |
| `{{{u}}}` | `user` | Look up "$u", treat as the value `{{'user'}}` |
| `{{(u)}}` | `admin` | Look up "$u", treat as the name `{{user}}` |
| `{{var user}}` | `abcuser` | Concatenation |
| `{{(var '.1')}}` | `one` | Look up "$var", treat as "abc", then concatenate ".1" and look up `{{abc.1}}` |

In double-quoted strings, the following escape sequences are defined.

* `\"` - Quote
* `\b` - Bell
* `\e` - Escape (note that Bash typically uses $'\E' for the same thing)
* `\f` - Form feed
* `\n` - Newline
* `\r` - Carriage return
* `\t` - Tab
* `\v` - Vertical tab
* Anything else will skip the `\` and place the next character. However, this implementation is allowed to change in the future if a different escape character mapping becomes commonplace.


Environment Variables and Functions
-----------------------------------

There are several functions and variables used to process templates. `mo` reserves variables that start with `MO_` for variables exposing data or configuration, functions starting with `mo::`, and local variables starting with `mo[A-Z]`. You are welcome to use internal functions, though only ones that are marked as "Public" should not change their interface. Scripts may also read any of the variables.

Functions are all executed in a subshell, with another subshell for lambdas. Thus, your lambda can't affect the parsing of a template. There's more information about lambdas when talking about tests that fail.

* `MO_ALLOW_FUNCTION_ARGUMENTS` - When set to a non-empty value, this allows functions referenced in templates to receive additional options and arguments.
* `MO_CLOSE_DELIMITER` - The string used when closing a tag. Defaults to "}}". Used internally.
* `MO_CLOSE_DELIMITER_DEFAULT` - The default value of `MO_CLOSE_DELIMITER`. Used when resetting the close delimiter, such as when parsing a partial.
* `MO_CURRENT` - Variable name to use for ".".
* `MO_DEBUG` - When set to a non-empty value, additional debug information is written to stderr.
* `MO_FUNCTION_ARGS` - Arguments passed to the function.
* `MO_FAIL_ON_FILE` - If a filename from the command-line is missing or a partial does not exist, abort with an error.
* `MO_FAIL_ON_FUNCTION` - If a function returns a non-zero status code, abort with an error.
* `MO_FAIL_ON_UNSET` - When set to a non-empty value, expansion of an unset env variable will be aborted with an error.
* `MO_FALSE_IS_EMPTY` - When set to a non-empty value, the string "false" will be treated as an empty value for the purposes of conditionals.
* `MO_OPEN_DELIMITER` - The string used when opening a tag. Defaults to "{{". Used internally.
* `MO_OPEN_DELIMITER_DEFAULT` - The default value of MO_OPEN_DELIMITER. Used when resetting the open delimiter, such as when parsing a partial.
* `MO_ORIGINAL_COMMAND` - Used to find the `mo` program in order to generate a help message.
* `MO_PARSED` - Content that has made it through the template engine.
* `MO_STANDALONE_CONTENT` - The unparsed content that preceeded the current tag. When a standalone tag is encountered, this is checked to see if it only contains whitespace. If this and the whitespace condition after a tag is met, then this will be reset to $'\n'.
* `MO_UNPARSED` - Template content yet to make it through the parser.


Concessions
-----------

I admit that implementing everything in bash just doesn't make a lot of sense.  For example, the following things just don't work because they don't really mesh with the "bash way".

Pull requests to solve the following issues would be helpful.


### Mustache Syntax

* Dotted names are supported but only for associative arrays (Bash 4).  See [`demo/associative-arrays`](demo/associative-arrays) for an example.
* There's no "top level" object, so `echo '{{.}}' | ./mo` does not do anything useful.  In other languages you can say the data for the template is a string and in `mo` the data is always the environment.  Luckily this type of usage is rare and `{{.}}` works great when iterating over an array.
* [Parents](https://mustache.github.io/mustache.5.html#Parents), where a template can override chunks of a partial, are not supported.
* HTML encoding is not built into `mo`.  `{{{var}}}`, `{{&var}}` and `{{var}}` all do the same thing.  `echo '{{TEST}}' | TEST='<b>' mo` will give you "`<b>`" instead of "`&gt;b&lt;`".


### General Scripting Issues

* Using binary files as templates is simply not allowed.
* Bash does not support anything more complex than strings/numbers inside of associative arrays.  I'm not able to add objects nor nested arrays to bash - it's just a shell after all!
* You must make sure the data is in the environment when `mo` runs.  The easiest way to do that is to source `mo` in your shell script after setting up lots of other environment variables / functions.


Developing
----------

Check out the code and hack away.  Please add tests to show off bugs before fixing them.  New functionality should also be covered by a test.

First, make sure you install Node.js. After that, run `npm run install-tests` to get the dependencies and the repository of YAML tests. Run `npm run test` to run the JavaScript tests. There's over 100 of them, which is great. Not all of them will pass, but that's discussed later.

When submitting patches, make sure to run them past [ShellCheck] and ensure no problems are found.  Also please use Bash 3 syntax if you are manipulating arrays.


### Porting and Backporting

In case of problems, setting MO_DEBUG to a non-empty value will give you LOTS of output.

    MO_DEBUG=1 ./mo my-template


### Failed Specs

It is acceptable for some of the official spec tests to fail. The spec runner has specific exclusions and overrides to test similar functionality that avoid the following issues.

 * Using `{{.}}` outside of a loop - In order to access any variable, you must use its name. In a loop, `{{.}}` will refer to the current value, but outside the loop you are unable to use this dot notation because there is no current value.
 * Deeply nested data - Bash doesn't support complex data structure. Basically, just strings and arrays of strings.
 * Interpolation; Multiple Calls:  This fails because lambdas execute in a subshell so their output can be captured. If you want state to be preserved, you will need to write it outside of the current environment and load it again later.
 * HTML Escaping - Since bash is not often executed in a web server context, it makes no sense to have the output escaped as HTML.  Performing shell escaping of variables may be an option in the future if there's a demand.
 * Lambdas - Function results are *not* automatically interpreted again. If you want to parse the results as Mustache content, use `mo::parse`. When they use `mo::parse`, it will use the current delimiters.

 For lambdas, these examples may help.

 ```bash
 # Retrieve content into a variable.
 content=$(cat)

 # Retrieve all content and do not trim newlines at the end.
 content=$(cat; echo -n '.')
 content=${content%.}

 # Parse content using the current delimiters
 mo::parse results "This is my content. Hello, {{username}}"
 echo -n "$results"

 # Parse content using the default delimiters
 MO_OPEN_DELIMITER=$MO_OPEN_DELIMITER_DEFAULT
 MO_CLOSE_DELIMITER=$MO_CLOSE_DELIMITER_DEFAULT
 mo::parse results "This is my content. Hello, {{username}}"
 echo -n "$results"
 ```


### Future Enhancements

There's a few places in the code marked with `TODO` to signify areas that could use improvement.  Care to help?  Keep in mind that this uses bash exclusively, so it might not look the prettiest.


License
-------

This program is licensed under an MIT license with an additional non-advertising clause.  See [LICENSE.md](LICENSE.md) for the full text.


[Mustache]: https://mustache.github.io/
[ShellCheck]: https://github.com/koalaman/shellcheck
