Mo - Mustache Templates in Bash
===============================

[Mustache] templates are simple, logic-less templates.  Because of their simplicity, they are able to be ported to many languages.  The syntax is quite simple.

    Hello, {{NAME}}.

    I hope your {{TIME_PERIOD}} was fun.

Let's try using this with some data in bash.  Save those lines to `trip.txt` and run a command like this:

    NAME=Tyler TIME_PERIOD=weekend ./mo weekend-trip.txt

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


Concessions
-----------

I admit that implementing everything in bash just doesn't make a lot of sense.  For example, the following things just don't work.

* Bash does not support nested structures like fancy objects.  The best you can do are arrays.  I'm not able to add super complex structures to bash - it's just a shell after all!
* There's no "top level" object that `{.}` refers to in `mo`.  In other languages you can say the data for the template is a string.  That's ok because using `{.}` when processing a top level scope is rare.  Using `{.}` works great when iterating over an array.
* HTML encoding is not built into `mo`.  The `{{{...}}}` and `{{...}}` tags both work.  `echo '{{TEST}}' | TEST='<b>' mo` will give you "`<b>`" instead of "`&gt;b&lt;`".
* You must make sure the data is in the environment when `mo` runs.  The easiest way to do that is to source `mo` in your shell script after setting up lots of other environment variables / functions.
* Associative arrays are not addressable via their index.  You can't use `{{VARIABLE_NAME.INDEX_NAME}}` and expect it to work.  Associative arrays aren't supported in Bash 3.
* Changing the delimiters.  Really this could be done, but I often don't have the need to do this.  File an issue or submit a pull request if this is something ou'd really like to see.


Developing
----------

Check out the code and hack away.  Please add tests to show off bugs before fixing them.  New functionality should also be covered by a test.

To run against the official specs, you need to make sure you have the "spec" submodule.  If you see a `spec/` folder with stuff in it, you're already set.  Otherwise run `git submodule update --init`.  After that you need to install node.js and run `npm install async` (no, I didn't make a package.json to just list one dependency).  Finally, `./run-spec.js spec/specs/*.json` will run against the official tests - there's over 100 of them.


License
-------

This program is licensed under an MIT license with an additional non-advertising clause.  See [LICENSE.md](LICENSE.md) for the full text.


[Mustache]: https://mustache.github.io/
