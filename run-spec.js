#!/usr/bin/env node

const exec = require("child_process").exec;
const fsPromises = require("fs").promises;

// Skip or override portions of tests. The goal is to still have as much
// coverage as possible, but skip things that Bash does not support.
//
// To skip a test, define a "skip" property and explain why the test is
// skipped.
//
// To override any test property, just define that property. It replaces the
// original property, not augmenting it.
const testOverrides = {
    "Comments -> Variable Name Collision": {
        // Can't use variables with exclamation points easily
        data: {
            comment: 4
        }
    },
    "Interpolation -> Dotted Names - Arbitrary Depth": {
        skip: "Not able to use more than one level of depth"
    },
    "Interpolation -> Dotted Names - Broken Chain Resolution": {
        data: {
            a: {
                b: "wrong"
            },
            name: "Jim"
        },
        template: '"{{a.name}}" == ""'
    },
    "Interpolation -> Dotted Names - Initial Resolution": {
        data: {
            a: {
                name: "Phil"
            },
            name: "Wrong"
        },
        template: "\"{{#a}}{{name}}{{/a}}\" == \"Phil\""
    },
    "Interpolation -> Implicit Iterators - Ampersand": {
        skip: "HTML escaping is not supported"
    },
    "Interpolation -> Implicit Iterators - Basic Interpolation": {
        skip: "Can not use {{.}} outside of a loop. Need to use a variable name."
    },
    "Interpolation -> Implicit Iterators - Basic Integer Interpolation": {
        skip: "Can not use {{.}} outside of a loop. Need to use a variable name."
    },
    "Interpolation -> Implicit Iterators - Triple Mustache": {
        skip: "Can not use {{.}} outside of a loop. Need to use a variable name."
    },
    "Interpolation -> HTML Escaping": {
        skip: "HTML escaping is not supported"
    },
    "Interpolation -> Implicit Iterators - HTML Escaping": {
        skip: "HTML escaping is not supported"
    },
    "Inverted -> Dotted Names - Falsey": {
        data: {
            a: {
                b: ""
            }
        },
        template: '"{{^a.b}}Not Here{{/a.b}}" == "Not Here"'
    },
    "Inverted -> Dotted Names - Truthy": {
        data: {
            a: {
                b: "1"
            }
        },
        template: '"{{^a.b}}Not Here{{/a.b}}" == ""'
    },
    "Lambdas -> Escaping": {
        skip: "HTML escaping is not supported"
    },
    "Lambdas -> Interpolation - Alternate Delimiters": {
        skip: "There is no difference between a lamba used as a value and a lambda used as a block. Both will parse using the current delimiters."
    },
    "Lambdas -> Inverted Section": {
        // This one passed mostly by accident. Correcting so the test still
        // tests what is was designed to illustrate.
        data: {
            static: "static",
            lambda: {
                __tag__: 'code',
                bash: 'false'
            }
        }
    },
    "Lambdas -> Interpolation": {
        data: {
            lambda: {
                __tag__: 'code',
                bash: 'echo -n "world"'
            }
        }
    },
    "Lambdas -> Interpolation - Expansion": {
        data: {
            lambda: {
                __tag__: 'code',
                bash: 'mo::parse result "{{planet}}"; echo -n "$result"'
            },
            planet: 'world'
        }
    },
    "Lambdas -> Interpolation - Multiple Calls": {
        skip: "Calls are not cached, but they run in isolated environments, so saving a global variable does not work."
    },
    "Lambdas -> Section": {
        data: {
            lambda: {
                __tag__: 'code',
                bash: 'if [[ "$(cat)" == "{{x}}" ]]; then echo -n yes; else echo -n no; fi'
            },
            x: "Error!"
        }
    },
    "Lambdas -> Section - Alternate Delimiters": {
        data: {
            lambda: {
                __tag__: 'code',
                bash: 'local content=$(cat); mo::parse content "$content{{planet}} => |planet|$content"; echo -n "$content"'
            },
            planet: 'Earth'
        }
    },
    "Lambdas -> Section - Expansion": {
        data: {
            lambda: {
                __tag__: 'code',
                bash: 'local content=$(cat); mo::parse content "$content{{planet}}$content"; echo -n "$content"'
            },
            planet: "Earth"
        }
    },
    "Lambdas -> Section - Multiple Calls": {
        data: {
            lambda: {
                __tag__: 'code',
                bash: 'echo -n "__$(cat)__"'
            }
        }
    },
    "Partials -> Recursion": {
        skip: "Complex objects are not supported and context is reset to the global level, so the recursion will loop forever"
    },
    "Sections -> Deeply Nested Contexts": {
        skip: "Nested objects are not supported"
    },
    "Sections -> Dotted Names - Broken Chains": {
        // Complex objects are not supported
        template: `"{{#a.b}}Here{{/a.b}}" == ""`
    },
    "Sections -> Dotted Names - Falsey": {
        // Complex objects are not supported
        data: { a: { b: false } },
        template: `"{{#a.b}}Here{{/a.b}}" == ""`
    },
    "Sections -> Dotted Names - Truthy": {
        // Complex objects are not supported
        data: { a: { b: true } },
        template: `"{{#a.b}}Here{{/a.b}}" == "Here"`
    },
    "Sections -> Implicit Iterator - Array": {
        skip: "Nested arrays are not supported"
    },
    "Sections -> List": {
        // Arrays of objects are not supported
        data: { list: [1, 2, 3] },
        template: `"{{#list}}{{.}}{{/list}}"`
    },
    "Sections -> List Context": {
        skip: "Deeply nested objects are not supported"
    },
    "Sections -> List Contexts": {
        skip: "Deeply nested objects are not supported"
    }
};

function specFileToName(file) {
    return file
        .replace(/.*\//, "")
        .replace(".json", "")
        .replace("~", "")
        .replace(/(^|-)[a-z]/g, function (match) {
            return match.toUpperCase();
        });
}

function processArraySequentially(array, callback) {
    function processCopy() {
        if (arrayCopy.length) {
            const item = arrayCopy.shift();
            return Promise.resolve(item)
                .then(callback)
                .then((singleResult) => {
                    result.push(singleResult);

                    return processCopy();
                });
        } else {
            return Promise.resolve(result);
        }
    }

    const result = [];
    const arrayCopy = array.slice();

    return processCopy();
}

function debug(...args) {
    if (process.env.DEBUG) {
        console.debug(...args);
    }
}

function makeShellString(value) {
    if (typeof value === "boolean") {
        return value ? '"true"' : '""';
    }

    if (typeof value === "string") {
        // Newlines are tricky
        return value
            .split(/\n/)
            .map(function (chunk) {
                return JSON.stringify(chunk);
            })
            .join('"\n"');
    }

    if (typeof value === "number") {
        return value;
    }

    return "ERR_CONVERTING";
}

function addToEnvironmentArray(name, value) {
    const result = ["("];
    value.forEach(function (subValue) {
        result.push(makeShellString(subValue));
    });
    result.push(")");

    return name + "=" + result.join(" ");
}

function addToEnvironmentObjectConvertedToAssociativeArray(name, value) {
    const values = [];

    for (const [k, v] of Object.entries(value)) {
        if (typeof v === "object") {
            if (v) {
                // An object - abort
                return `# ${name}.${k} is an object that can not be converted to an associative array`;
            }

            // null
            values.push(`[${k}]=`);
        } else {
            values.push(`[${k}]=${makeShellString(v)}`);
        }
    }

    return `declare -A ${name}\n${name}=(${values.join(" ")})`;
}

function addToEnvironmentObject(name, value) {
    if (!value) {
        // null
        return `#${name} is null`;
    }

    if (value.__tag__ === "code") {
        return `${name}() { ${value.bash || 'echo "NO BASH VERSION OF CODE"'}; }`;
    }

    return addToEnvironmentObjectConvertedToAssociativeArray(name, value);
}

function addToEnvironment(name, value) {
    if (Array.isArray(value)) {
        return addToEnvironmentArray(name, value);
    }

    if (typeof value === "object") {
        return addToEnvironmentObject(name, value);
    }

    return `${name}=${makeShellString(value)}`;
}

function buildScript(test) {
    const script = ["#!/usr/bin/env bash"];
    Object.keys(test.data).forEach(function (name) {
        script.push(addToEnvironment(name, test.data[name]));
    });
    script.push(". ./mo");
    script.push("mo spec-runner/spec-template");
    script.push("");

    return script.join("\n");
}

function writePartials(test) {
    return processArraySequentially(
        Object.keys(test.partials),
        (partialName) => {
            debug("Writing partial:", partialName);

            return fsPromises.writeFile(
                "spec-runner/" + partialName,
                test.partials[partialName]
            );
        }
    );
}

function setupEnvironment(test) {
    return cleanup()
        .then(() => fsPromises.mkdir("spec-runner/"))
        .then(() =>
            fsPromises.writeFile("spec-runner/spec-script", test.script)
        )
        .then(() =>
            fsPromises.writeFile("spec-runner/spec-template", test.template)
        )
        .then(() => writePartials(test));
}

function executeScript(test) {
    return new Promise((resolve) => {
        exec(
            "bash spec-runner/spec-script 2>&1",
            {
                timeout: 2000
            },
            (err, stdout) => {
                if (err) {
                    test.scriptError = err.toString();
                }

                test.output = stdout;
                resolve();
            }
        );
    });
}

function cleanup() {
    return fsPromises.rm("spec-runner/", { force: true, recursive: true });
}

function detectFailure(test) {
    if (test.scriptError) {
        return true;
    }

    if (test.output !== test.expected) {
        return true;
    }

    return false;
}

function showFailureDetails(test) {
    console.log(`FAILURE: ${test.fullName}`);
    console.log("");
    console.log(test.desc);
    console.log("");
    console.log(JSON.stringify(test, null, 4));
}

function applyTestOverrides(test) {
    const overrides = testOverrides[test.fullName];
    const originals = {};

    if (!overrides) {
        return;
    }

    for (const [key, value] of Object.entries(overrides)) {
        originals[key] = test[key];
        test[key] = value;
    }

    test.overridesApplied = true;
    test.valuesBeforeOverride = originals;
}

function runTest(testSet, test) {
    test.partials = test.partials || {};
    test.fullName = `${testSet.name} -> ${test.name}`;
    applyTestOverrides(test);
    test.script = buildScript(test);

    if (test.skip) {
        debug("Skipping test:", test.fullName, `(${test.skip})`);

        return Promise.resolve();
    }

    debug("Running test:", test.fullName);

    return setupEnvironment(test)
        .then(() => executeScript(test))
        .then(cleanup)
        .then(() => {
            test.isFailure = detectFailure(test);

            if (test.isFailure) {
                showFailureDetails(test);
            } else {
                debug('Test pass:', test.fullName);
            }
        });
}

function processSpecFile(filename) {
    debug("Read spec file:", filename);

    return fsPromises.readFile(filename, "utf8").then((fileContents) => {
        const testSet = JSON.parse(fileContents);
        testSet.name = specFileToName(filename);

        return processArraySequentially(testSet.tests, (test) =>
            runTest(testSet, test)
        ).then(() => {
            testSet.pass = 0;
            testSet.fail = 0;
            testSet.skip = 0;
            testSet.passOverride = 0;

            for (const test of testSet.tests) {
                if (test.isFailure) {
                    testSet.fail += 1;
                } else if (test.skip) {
                    testSet.skip += 1;
                } else {
                    testSet.pass += 1;

                    if (test.overridesApplied) {
                        testSet.passOverride += 1;
                    }
                }
            }
            console.log(
                `### ${testSet.name} Results = ${testSet.pass} passed (with ${testSet.passOverride} overridden), ${testSet.fail} failed, ${testSet.skip} skipped`
            );

            return testSet;
        });
    });
}

// 0 = node, 1 = script, 2 = file
if (process.argv.length < 3) {
    console.log("Specify one or more JSON spec files on the command line");
    process.exit();
}

processArraySequentially(process.argv.slice(2), processSpecFile).then(
    (result) => {
        console.log("=========================================");
        console.log("");
        console.log("Failed Test Summary");
        console.log("");
        let pass = 0,
            fail = 0,
            skip = 0,
            total = 0,
            passOverride = 0;

        for (const testSet of result) {
            pass += testSet.pass;
            fail += testSet.fail;
            skip += testSet.skip;
            total += testSet.tests.length;
            passOverride += testSet.passOverride;

            console.log(
                `* ${testSet.name}: ${testSet.tests.length} total, ${testSet.pass} pass (with ${passOverride} overridden), ${testSet.fail} fail, ${testSet.skip} skip`
            );

            for (const test of testSet.tests) {
                if (test.isFailure) {
                    console.log(`    * Failure: ${test.name}`);
                }
            }
        }

        console.log("");
        console.log(
            `Final result: ${total} total, ${pass} pass (with ${passOverride} overridden), ${fail} fail, ${skip} skip`
        );

        if (fail) {
            process.exit(1);
        }
    },
    (err) => {
        console.error(err);
        console.error("FAILURE RUNNING SCRIPT");
        console.error("Testing artifacts are left in script-runner/ folder");
    }
);
