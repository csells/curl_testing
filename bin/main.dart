import 'dart:convert';
import 'dart:io';
import 'package:curl_testing/json_diff/json_diff.dart';
import 'package:curl_testing/curl_parser.dart';

// from https://github.com/google/dart-json_diff
void printDiff(Map<String, dynamic> curlJsonMap, Map<String, dynamic> dartJsonMap) {
  // filter insignificant diffs
  curlJsonMap['headers'].remove('user-agent');
  dartJsonMap['headers'].remove('user-agent');
  if (curlJsonMap['headers']['accept'] == '*/*' && dartJsonMap['headers']['accept'] == null) {
    dartJsonMap['headers']['accept'] = '*/*';
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

// zsh$ for file in dart_output/*.dart; echo $file: `dart bin/main.dart $file | grep DIFF`
void main(List<String> args) {
  if (args.length != 1) {
    print('usage: curl_testing <filename>');
    exit(1);
  }

  var s = File(args[0]).readAsStringSync();
  var re = RegExp(r'https?:\/\/[^\/]*\/');

  // NOTE: for testing purposes, make sure that the first line of the Dart file with the comment containing the curl command
  // contains a host that ends in / or the temp Dart file below is going to be screwed up (sorry... regexes are hard!);
  // NOTE2: also make sure that the URL from the curl command is the same in the expected Dart code, too!
  // NOTE3: the right code will still be generated!
  assert(s.split('\n')[0].contains(re));

  // replace all of the URLs to point to localhost
  // NOTE: this assumes test/http-request-dump.js running on localhost:8080
  s = s.replaceAll(re, 'http://localhost:8080/');

  // execute curl
  var curlCmd = s.split('\n')[0].substring(3);
  var curlArgs = tokenizeArgString(curlCmd);
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
