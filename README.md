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
    curl -sSL https://git.io/get-mo -o mo

    # Make executable
    chmod +x mo

    # Move to the right folder
    sudo mv mo /usr/local/bin/

    # Test
    echo "works" | mo


### Locally; For Yourself

This is very similar to installing it globally but it does not require root privileges.  It is very important that your PATH includes the destination folder otherwise it won't work.  Some local folders that are typically used are `~/bin/` and `~/.local/bin/`.

    # Download
    curl -sSL https://git.io/get-mo -o mo

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
    curl -sSL https://git.io/get-mo -o mo

    # Move into your project folder
    mv mo ~/projects/amazing-things/lib/

To allow it to work this way, you either should source the file (`. "lib/mo"`) or make it executable (`chmod +x lib/mo`) and run it from your scripts.


How to Use
----------

If you only plan using strings and numbers, nothing could be simpler.  In your shell script you can choose to export the variables.  The below script is [`demo/using-strings`](demo/using-strings).

    #!/bin/bash
    cd "$(dirname "$0")" # Go to the script's directory
    export TEST="This is a test"
    echo "Your message:  {{TEST}}" | ../mo

The result?  "Your message:  This is a test".

Using arrays adds a slight level of complexity.  *You must source `mo`.*  Look at [`demo/using-arrays`](demo/using-arrays).

    #!/bin/bash
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


Concessions
-----------

I admit that implementing everything in bash just doesn't make a lot of sense.  For example, the following things just don't work because they don't really mesh with the "bash way".

Pull requests to solve the following issues would be helpful.


### Mustache Syntax

* Dotted names are supported but only for associative arrays (Bash 4).  See [`demo/associative-arrays`](demo/associative-arrays) for an example.
* There's no "top level" object, so `echo '{.}' | ./mo` does not do anything useful.  In other languages you can say the data for the template is a string and in `mo` the data is always the environment.  Luckily this type of usage is rare and `{.}` works great when iterating over an array.
* HTML encoding is not built into `mo`.  `{{{var}}}`, `{{&var}}` and `{{var}}` all do the same thing.  `echo '{{TEST}}' | TEST='<b>' mo` will give you "`<b>`" instead of "`&gt;b&lt;`".
* You can not change the delimiters.


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

There is a diagnostic script that is aimed to help at making sure the internal functions all work when testing the script out on a version of bash or in an environment that is causing issues.  When adding new functions, please make sure this script gets updated to properly test your code.


### Failed Specs

It is acceptable for some of the official spec tests to fail.  Anything dealing with multiple levels of objects (eg. `{{a.b.c}}`) and changing the delimiters (`{{= | | =}}`) will fail.  Other than that, this bash implementation of the mustache spec should pass tests.

Specific issues:
 * Interpolation - Multiple Calls:  This fails because lambdas execute in a subshell so their output can be captured.  This is flagged as a TODO in the code.
 * HTML Escaping - Since bash is not often executed in a web server context, it makes no sense to have the output escaped as HTML.  Performing shell escaping of variables may be an option in the future if there's a demand.


### Future Enhancements

There's a few places in the code marked with `TODO` to signify areas that could use improvement.  Care to help?  Keep in mind that this uses bash exclusively, so it might not look the prettiest.


License
-------

This program is licensed under an MIT license with an additional non-advertising clause.  See [LICENSE.md](LICENSE.md) for the full text.


[Mustache]: https://mustache.github.io/
[ShellCheck]: https://github.com/koalaman/shellcheck
