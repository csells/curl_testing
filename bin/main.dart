import 'dart:convert';
import 'dart:io';
import 'package:curl_testing/json_diff/json_diff.dart';
import 'package:path/path.dart' as path;

// from https://github.com/google/dart-json_diff
void printDiff(
    Map<String, dynamic> curlJsonMap, Map<String, dynamic> dartJsonMap) {
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

  // diff
  var curlJson = JsonEncoder().convert(curlJsonMap);
  var dartJson = JsonEncoder().convert(dartJsonMap);
  var diff = JsonDiffer(curlJson, dartJson).diff();

  if (diff.hasNothing) {
    print('NO SIGNIFICANT DIFFS');
  } else {
    print('DIFFS:');
    for (var key in diff.node.keys) {
      if (diff.node[key].hasRemoved) {
        print('$key removed from CURL: ${diff.node[key].removed}');
      }

      if (diff.node[key].hasAdded) {
        print('$key added to DART:     ${diff.node[key].added}');
      }

      if (diff.node[key].hasChanged) {
        print('$key changed:           ${diff.node[key].changed}');
      }

      print('');
    }
  }
}

Map<String, dynamic> runCmd(String cmd, List<String> args) {
  args = trimAllQuotes(args);
  stdout.write('${cmd.toUpperCase()}: ');
  var res = Process.runSync(cmd, args, runInShell: true);
  if (res.stderr.toString().isNotEmpty) throw Exception(res.stderr.toString());

  var encoder = JsonEncoder.withIndent('  ');
  var jsonMap = jsonDecode(res.stdout);
  print(encoder.convert(jsonMap));
  print('');

  return jsonMap;
}

// trim a leading and trailing single and double quote from the args before handing it to Dart
// otherwise Process.run has some trouble...
List<String> trimAllQuotes(List<String> ss) =>
    ss.map((s) => trimQuotes(s)).toList();
String trimQuotes(String s) {
  // only trim off quotes in a balanced way, or we screw with the semantics
  if (s.startsWith("'") || s.startsWith('"')) {
    assert(s.endsWith(s[0]));
    s = s.substring(1, s.length - 1);
    assert(!s.startsWith("'") && !s.startsWith('"'));
  }

  return s;
}

// from https://github.com/yargs/yargs-parser/blob/master/lib/tokenize-arg-string.js
// take an un-split argv string and tokenize it.
List<String> tokenizeArgString(String argString) {
  argString = argString.trim();

  var i = 0;
  String prevC;
  String c;
  String opening;
  var args = <String>[];

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

// from https://github.com/NickCarneiro/curlconverter/blob/master/util.js
int getCurlUrlIndex(List<String> args) {
  assert(args[0] == 'curl');
  var i = 1;

  // if url argument wasn't where we expected it, try to find it in the other arguments
  if (args[i].isEmpty || args[i].startsWith('-')) {
    for (var j = 2; j < args.length; j++) {
      if (args[j].startsWith('http') || args[j].startsWith('www.')) {
        i = j;
        break;
      }
    }
  }

  return i;
}

const fixturesDir = '../curlconverter/test/fixtures';

void test(String testName) {
  // read the Dart file w/ the curl command as the first comment at the top
  var s = File('$fixturesDir/dart/$testName.dart').readAsStringSync();
  var curlCmd = File('$fixturesDir/curl_commands/$testName.sh')
      .readAsStringSync()
      .replaceAll(RegExp('\r|\n'), '');
  var curlArgs = tokenizeArgString(curlCmd);

  // replace all of the curl URLs to point to localhost (including in the url arg)
  var curlUrlArgIndex = getCurlUrlIndex(curlArgs);
  assert(curlArgs[curlUrlArgIndex].isNotEmpty);
  curlArgs[curlUrlArgIndex] =
      Uri.parse(trimQuotes(curlArgs[curlUrlArgIndex])).toString();
  var curlUrlBase = RegExp('(https?://[^/]*)/?')
      .firstMatch(curlArgs[curlUrlArgIndex])
      .group(0);
  s = s.replaceAll(curlUrlBase, 'http://localhost:8080/');
  curlArgs[curlUrlArgIndex] = curlArgs[curlUrlArgIndex]
      .replaceFirst(curlUrlBase, 'http://localhost:8080/');

  // execute curl
  var curlJsonMap = runCmd(curlArgs[0], [...curlArgs.skip(1).toList(), '-s']);

  // prepare to run dart
  final pubspecFile = File('${Directory.systemTemp.path}/pubspec.yaml')
    ..writeAsStringSync('''
name: foo
environment:
  sdk: ">=2.4.0 <3.0.0"
dependencies:
  http:
''');

  // execute dart
  var tempFilename = '${Directory.systemTemp.path}/curl_testing_temp.dart';
  var tempFile = File(tempFilename)..writeAsStringSync(s, flush: true);
  var dartJsonMap = runCmd('dart', [tempFile.path]);
  tempFile.deleteSync();
  pubspecFile.deleteSync();

  printDiff(curlJsonMap, dartJsonMap);
}

// e.g.
// $ dart bin/main.dart post_escaped_double_quotes_in_single_quotes
// $ dart bin/main.dart all | grep DIFFS
void main(List<String> args) {
  print('${Directory.current}\n\r');
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
