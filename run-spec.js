#!/usr/bin/env node

var async, exec, fs, summary, specFiles;

function makeShellString(value) {
    if (typeof value === 'string') {
        return JSON.stringify(value);
    }

    if (typeof value === 'number') {
        return value;
    }

    return 'ERR_CONVERTING';
}

function addToEnvironment(name, value) {
    var result;

    if (Array.isArray(value)) {
        result = [
            '('
        ];
        value.forEach(function (subValue) {
            result.push(makeShellString(subValue));
        });
        result.push(')');

        return name + '=' + result.join(' ');
    }

    if (typeof value === 'object') {
        return '# ' + name + ' is an object and will not work in bash';
    }

    if (typeof value === 'boolean') {
        if (value) {
            return name + '="true"';
        }

        return name + '=""';
    }

    return name + '=' + makeShellString(value);
}

function runTest(test, done) {
    var output, script;

    script = [
        '#!/bin/bash'
    ];

    Object.keys(test.data).forEach(function (name) {
        script.push(addToEnvironment(name, test.data[name]));
    });
    script.push('. mo spec-template');
    test.script = script.join('\n');
    async.series([
        function (taskDone) {
            fs.writeFile('spec-script', test.script, taskDone);
        },
        function (taskDone) {
            fs.writeFile('spec-template', test.template, taskDone);
        },
        function (taskDone) {
            exec('bash spec-script', function (err, stdout) {
                if (err) {
                    return taskDone(err);
                }

                output = stdout;
                taskDone();
            });
        },
        function (taskDone) {
            fs.unlink('spec-script', taskDone);
        },
        function (taskDone) {
            fs.unlink('spec-template', taskDone);
        }
    ], function (err) {
        if (err) {
            return done(err);
        }
        
        done(null, output);
    });
    
    return '';
}

function prepareAndRunTest(test, done) {
    async.waterfall([
        function (taskDone) {
            console.log('### ' + test.name);
            console.log('');
            console.log(test.desc);
            console.log('');
            runTest(test, taskDone);
        },
        function (actual, taskDone) {
            test.actual = actual;
            test.pass = (test.actual === test.expected);

            if (test.pass) {
                console.log('Passed.');
            } else {
                console.log('Failed.');
                console.log('');
                console.log(test);
            }

            console.log('');
            taskDone();
        }
    ], done);
}

function specFileToName(file) {
    return file.replace(/.*\//, '').replace('.json', '').replace('~', '').replace(/(^|-)[a-z]/g, function (match) {
        return match.toUpperCase();
    });
}

function processSpecFile(specFile, done) {
    fs.readFile(specFile, 'utf8', function (err, data) {
        var name;

        if (err) {
            return done(err);
        }

        name = specFileToName(specFile);
        data = JSON.parse(data);
        console.log(name);
        console.log('====================');
        console.log('');
        console.log(data.overview);
        console.log('');
        console.log('Tests');
        console.log('-----');
        console.log('');
        async.series([
            function (taskDone) {
                async.eachSeries(data.tests, prepareAndRunTest, taskDone);
            },
            function (taskDone) {
                summary[name] = {};
                data.tests.forEach(function (test) {
                    summary[name][test.name] = test.pass;
                });
                taskDone();
            }
        ], done);
    });
}

// 0 = node, 1 = script, 2 = file
if (process.argv.length < 3) {
    console.log('Specify spec files on the command line');
    process.exit();
}

async = require('async');
fs = require('fs');
exec = require('child_process').exec;
summary = {};
async.eachSeries(process.argv.slice(2), processSpecFile, function () {
    var fail, pass;

    console.log('');
    console.log('Summary');
    console.log('=======');
    console.log('');
    pass = 0;
    fail = 0;
    Object.keys(summary).forEach(function (name) {
        var groupPass, groupFail, testResults;
       
        testResults = [];
        groupPass = 0;
        groupFail = 0;
        Object.keys(summary[name]).forEach(function (testName) {
            if (summary[name][testName]) {
                testResults.push('    * pass - ' + testName);
                groupPass += 1;
                pass += 1;
            } else {
                testResults.push('    * FAIL - ' + testName);
                groupFail += 1;
                fail += 1;
            }
        });
        testResults.unshift('* ' + name + ' (failed ' + groupFail + ' out of ' + (groupPass + groupFail) + ' tests)');
        console.log(testResults.join('\n'));
    });

    console.log('');
    console.log('Failed ' + fail + ' out of ' + (pass + fail) + ' tests');
});
