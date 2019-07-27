import 'dart:convert';
import 'dart:io';
import 'package:curl_testing/json_diff/json_diff.dart';

// from https://github.com/google/dart-json_diff
void printDiff(Map<String, dynamic> curlJsonMap, Map<String, dynamic> dartJsonMap) {
  // filter insignificant diffs
  curlJsonMap['headers'].remove('user-agent');
  dartJsonMap['headers'].remove('user-agent');
  if (curlJsonMap['headers']['accept'] == '*/*' && dartJsonMap['headers']['accept'] == null) {
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
    print("NO SIGNIFICANT DIFFS");
  } else {
    print("DIFFS:");
    for (var key in diff.node.keys) {
      if (diff.node[key].hasRemoved) print('$key removed from CURL: ${diff.node[key].removed}');
      if (diff.node[key].hasAdded) print('$key added to DART:     ${diff.node[key].added}');
      if (diff.node[key].hasChanged) print('$key changed:           ${diff.node[key].changed}');
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

// trim leading and training single and double quotes from the args before handing it to Dart
// otherwise Process.run has some trouble...
final begQuotesRE = RegExp('^(\'|")+');
final endQuotesRE = RegExp('(\'|")+\$');
String trimQuotes(String s) => s.replaceAll(begQuotesRE, '').replaceAll(endQuotesRE, '');
List<String> trimAllQuotes(List<String> ss) => ss.map((s) => trimQuotes(s)).toList();

// from https://github.com/yargs/yargs-parser/blob/master/lib/tokenize-arg-string.js
// take an un-split argv string and tokenize it.
List<String> tokenizeArgString(String argString) {
  argString = argString.trim();

  var i = 0;
  String prevC;
  String c;
  String opening;
  var args = List<String>();

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

// zsh$ for file in dart_output/*.dart; echo $file: `dart bin/main.dart $file | grep DIFF`
void main(List<String> args) {
  if (args.length != 1) {
    print('usage: curl_testing <filename>');
    exit(1);
  }

  // read the Dart file w/ the curl command as the first comment at the top
  var s = File(args[0]).readAsStringSync();
  var curlCmd = s.split('\n')[0].substring(3);
  var curlArgs = tokenizeArgString(curlCmd);

  // replace all of the curl URLs to point to localhost (including in the url arg)
  var curlUrlArgIndex = getCurlUrlIndex(curlArgs);
  assert(curlArgs[curlUrlArgIndex].isNotEmpty);
  curlArgs[curlUrlArgIndex] = Uri.parse(trimQuotes(curlArgs[curlUrlArgIndex])).toString();
  var curlUrlBase = RegExp('(https?:\/\/[^\/]*)\/?').firstMatch(curlArgs[curlUrlArgIndex]).group(0);
  s = s.replaceAll(curlUrlBase, 'http://localhost:8080/');
  curlArgs[curlUrlArgIndex] =
      curlArgs[curlUrlArgIndex].replaceFirst(curlUrlBase, 'http://localhost:8080/');

  // execute curl
  var curlJsonMap = runCmd(curlArgs[0], [...curlArgs.skip(1).toList(), '-s']);

  // execute dart
  var packagesFile = File(".packages");
  var packagesTemplFilename = Directory.systemTemp.path + '/.packages';
  packagesFile.copySync(packagesTemplFilename);
  var tempFilename = Directory.systemTemp.path + '/curl_testing_temp.dart';
  var tempFile = File(tempFilename)..writeAsStringSync(s, flush: true);
  var dartJsonMap = runCmd('dart', [tempFile.path]);
  tempFile.deleteSync();
  File(packagesTemplFilename).deleteSync();

  printDiff(curlJsonMap, dartJsonMap);
}
