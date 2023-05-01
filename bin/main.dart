// ignore_for_file: avoid_dynamic_calls, avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:curl_testing/json_diff/json_diff.dart';
import 'package:path/path.dart' as path;

// from https://github.com/google/dart-json_diff
void printDiff(
  Map<String, dynamic> curlJsonMap,
  Map<String, dynamic> dartJsonMap,
) {
  // filter insignificant diffs
  curlJsonMap['headers'].remove('user-agent');
  dartJsonMap['headers'].remove('user-agent');
  if (curlJsonMap['headers']['accept'] == '*/*' &&
      dartJsonMap['headers']['accept'] == null) {
    dartJsonMap['headers']['accept'] = '*/*';
  }
  if (curlJsonMap['headers']['accept-encoding'] == 'gzip, deflate, sdch' &&
      dartJsonMap['headers']['accept-encoding'] == 'gzip') {
    curlJsonMap['headers'].remove('accept-encoding');
  }
  if (curlJsonMap['headers']['accept-encoding'] == 'deflate, gzip' &&
      dartJsonMap['headers']['accept-encoding'] == 'gzip') {
    curlJsonMap['headers'].remove('accept-encoding');
  }
  if (dartJsonMap['headers']['accept-encoding'] == 'gzip') {
    dartJsonMap['headers'].remove('accept-encoding');
  }
  if (dartJsonMap['headers']['content-length'] == '0') {
    dartJsonMap['headers'].remove('content-length');
  }

  const encoder = JsonEncoder.withIndent('  ');
  print('CURL: ${encoder.convert(curlJsonMap)}');
  print('');
  print('DART: ${encoder.convert(dartJsonMap)}');
  print('');

  // diff
  final diff = JsonDiffer(curlJsonMap, dartJsonMap).diff();

  if (diff.hasNothing) {
    print('NO SIGNIFICANT DIFFS');
  } else {
    print('DIFFS:');
    for (final key in diff.removed.keys) {
      print('  $key removed from CURL: ${diff.removed[key]}');
    }

    for (final key in diff.added.keys) {
      print('  $key added to DART:     ${diff.added[key]}');
    }

    for (final key in diff.changed.keys) {
      print('  $key changed:           ${diff.changed[key]}');
    }
    
    print('');
  }
}

Map<String, dynamic> runCmd(String cmd, List<String> argsRaw) {
  final args = trimAllQuotes(argsRaw);
  final res = Process.runSync(cmd, args, runInShell: true);

  final err = res.stderr.toString();
  if (err.isNotEmpty) throw Exception(err);

  final out = res.stdout.toString();
  if (out.isEmpty) throw Exception('Error: no response');

  return jsonDecode(out) as Map<String, dynamic>;
}

// trim a leading and trailing single and double quote from the args before
// handing it to Dart otherwise Process.run has some trouble...
List<String> trimAllQuotes(List<String> ss) => ss.map(trimQuotes).toList();
String trimQuotes(String s) {
  // only trim off quotes in a balanced way, or we screw with the semantics
  if (s.startsWith("'") || s.startsWith('"')) {
    assert(s.endsWith(s[0]));
    final s2 = s.substring(1, s.length - 1);
    assert(!s2.startsWith("'") && !s2.startsWith('"'));
    return s2;
  }

  return s;
}

// from https://github.com/yargs/yargs-parser/blob/master/lib/tokenize-arg-string.js
// take an un-split argv string and tokenize it.
List<String> tokenizeArgString(String argStringRaw) {
  final argString = argStringRaw.trim();

  var i = 0;
  String prevC;
  String c;
  String opening;
  final args = <String>[];

  for (var ii = 0; ii < argString.length; ii++) {
    prevC = c;
    c = argString[ii];

    // split on spaces unless we're in quotes.
    if (c == ' ' && opening == null) {
      if (prevC != ' ') i++;
      continue;
    }

    // don't split the string if we're in matching
    // opening or closing single and double quotes.
    if (c == opening) {
      opening = null;
    } else if ((c == "'" || c == '"') && opening == null) {
      opening = c;
    }

    if (args.length == i) args.add('');
    args[i] += c;
  }

  return args;
}

const fixturesDir = '../curlconverter/test/fixtures';

void test(String testName) {
  // read the Dart file w/ the curl command as the first comment at the top
  final s = File('$fixturesDir/dart/$testName.dart').readAsStringSync();
  final curlCmd = File('$fixturesDir/curl_commands/$testName.sh')
      .readAsStringSync()
      .replaceAll(RegExp('\r|\n'), '');
  final curlArgs = tokenizeArgString(curlCmd);

  // execute curl
  final curlJsonMap = runCmd(curlArgs[0], [...curlArgs.skip(1), '-s']);

  // prepare to execute dart
  final pubspecFile = File('${Directory.systemTemp.path}/pubspec.yaml')
    ..writeAsStringSync('''
name: foo
environment:
  sdk: ">=2.4.0 <3.0.0"
dependencies:
  http:
''');

  // execute dart
  final tempFilename = '${Directory.systemTemp.path}/curl_testing_temp.dart';
  final tempFile = File(tempFilename)..writeAsStringSync(s, flush: true);
  final dartJsonMap = runCmd('dart', [tempFile.path]);
  tempFile.deleteSync();
  pubspecFile.deleteSync();

  printDiff(curlJsonMap, dartJsonMap);
}

// e.g.
// $ dart bin/main.dart post_escaped_double_quotes_in_single_quotes
// $ dart bin/main.dart all | grep DIFFS
void main(List<String> args) {
  if (args.length != 1) {
    print('usage: curl_testing <testname>|all');
    exit(1);
  }

  if (args[0] == 'all') {
    Directory('$fixturesDir/dart/')
        .listSync()
        .where((fse) => fse.path.endsWith('.dart'))
        .map((fse) => path.basenameWithoutExtension(fse.path))
        .forEach((tn) {
      print('DIFFS for $tn');
      test(tn);
      print('');
    });
  } else {
    test(args[0]);
  }
}
