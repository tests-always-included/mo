#!/usr/bin/env node

const exec = require("child_process").exec;
const fsPromises = require("fs").promises;

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

function addToEnvironmentObject(name, value) {
    // Sometimes the __tag__ property of the code in the lambdas may
    // be missing.  :-(
    if (
        (value && value.__tag__ === "code") ||
        (value.ruby && value.php && value.perl)
    ) {
        if (value.bash) {
            return `${name}() { ${value.bash}; }`;
        }

        return `${name}() { perl -e 'print ((${value.perl})->("'"$1"'"))'; }`;
    }

    if (value) {
        return `#${name} is an object and will not work in Bash`;
    }

    // null
    return `#${name} is null`;
}

function addToEnvironment(name, value) {
    if (Array.isArray(value)) {
        return addToEnvironmentArray(name, value);
    }

    if (typeof value === "object" && value) {
        return addToEnvironmentObject(name, value);
    }

    if (typeof value === "boolean") {
        return `${name}="${value ? "true" : ""}"`;
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
        exec("bash spec-runner/spec-script 2>&1", {
            timeout: 2000
        }, (err, stdout) => {
            if (err) {
                test.scriptError = err.toString();
            }

            test.output = stdout;
            resolve();
        });
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

function showFailureDetails(testSet, test) {
    if (!test.isFailure) {
        return;
    }

    console.log(`FAILURE: ${testSet.name} -> ${test.name}`)
    console.log('');
    console.log(test.desc);
    console.log('');
    console.log(test);
}

function runTest(testSet, test) {
    test.script = buildScript(test);
    test.partials = test.partials || {};
    debug('Running test:', testSet.name, "->", test.name);

    return setupEnvironment(test)
        .then(() => executeScript(test))
        .then(cleanup)
        .then(() => test.isFailure = detectFailure(test))
        .then(() => showFailureDetails(testSet, test));
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

            for (const test of testSet.tests) {
                if (test.isFailure) {
                    testSet.fail += 1;
                } else {
                    testSet.pass += 1;
                }
            }
            console.log(`### ${testSet.name} Results = ${testSet.pass} pass, ${testSet.fail} fail`);

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
        console.log('=========================================');
        console.log('');
        console.log('Failed Test Summary');
        console.log('');

        for (const testSet of result) {
            console.log(`* ${testSet.name}: ${testSet.tests.length} total, ${testSet.pass} pass, ${testSet.fail} fail`);

            for (const test of testSet.tests) {
                if (test.isFailure) {
                    console.log(`    * Failure: ${test.name}`);
                }
            }
        }
    },
    (err) => {
        console.error(err);
        console.error("FAILURE RUNNING SCRIPT");
        console.error("Testing artifacts are left in script-runner/ folder");
    }
);
