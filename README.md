# curl_testing

This project provides tests for client-side Dart code generated in
[curlconverter](https://github.com/curlconverter/curlconverter). This code tests
curl commands against the corresponding Dart code to see if the output of both
commands run against an echoing web server returns the same results.

# curl_testing usage

All of these commands run from `../curl_testing`.

To start an echoing web server that reflects both curl and Dart version of an
HTTP call back to the client as JSON for comparison:

```sh
node test/http-request-dump.js
```

To run the curl and Dart versions of a test from `../curlconverter`:

```sh
dart bin/main.dart <test-name>
```

e.g.

```sh
dart bin/main.dart get_basic_auth_no_user
```

To run all of the curl and Dart versions of the tests from `../curlconverter`:

```sh
dart bin/main.dart all
```

# curlconverter usage

All of these commands run from `../curlconverter`.

To update the curlconverter CLI from the `dart.ts` source:

```sh
npm run compile
```

To generate the Dart code for a set of curl arguments:

```sh
node dist/src/cli.js --language dart <curl-arg(s)>
```

e.g.

```sh
node dist/src/cli.js --language dart "http://localhost:28139/" -u ":some_password"
```

To run a particular Dart test:

```sh
npm test -- --language dart --test <test-name>
```

e.g.

```sh
npm test -- --language dart --test get_basic_auth_no_user
```

If a particular test fails, you can debug the diff using the
[curl_diff_explainer](https://github.com/csells/curl_diff_explainer) tool.

To run all of the Dart tests:

```sh
npm test -- --language dart
```

# curlconverter notes

The set of test curl commands: `../curlconverter/test/fixtures/curl_commands`

The set of test Dart files: `../curlconverter/test/fixtures/dart`

The code that generates the Dart files from the curl commands:
`../curlconverter/src/generators/dart.ts`
