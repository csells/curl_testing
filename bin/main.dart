import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import '../json_diff/json_diff.dart';

// from https://github.com/google/dart-json_diff
void printDiff(Map<String, dynamic> curlJsonMap, Map<String, dynamic> dartJsonMap) {
  // filter insignificant diffs
  curlJsonMap['headers'].remove('user-agent');
  dartJsonMap['headers'].remove('user-agent');
  if (curlJsonMap['headers']['accept'] == '*/*') curlJsonMap['headers'].remove('accept');
  if (dartJsonMap['headers']['accept-encoding'] == 'gzip')
    dartJsonMap['headers'].remove('accept-encoding');
  if (dartJsonMap['headers']['content-length'] == '0')
    dartJsonMap['headers'].remove('content-length');

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
  stdout.write('${cmd.toUpperCase()}: ');
  var res = Process.runSync(cmd, args);
  if (res.stderr.toString().isNotEmpty) throw Exception(res.stderr.toString());

  var encoder = JsonEncoder.withIndent('  ');
  var jsonMap = jsonDecode(res.stdout);
  print(encoder.convert(jsonMap));
  print('');

  return jsonMap;
}

void main(List<String> args) {
  if (args.length != 1) {
    print('usage: curl_testing <filename>');
    exit(1);
  }

  // replace all of the URLs to point to localhost
  // NOTE: this assumes something running on localhost:8080 for testing
  var s = File(args[0]).readAsStringSync();
  var re = RegExp(r'https?:\/\/[^\/]*\/');
  s = s.replaceAll(re, 'http://localhost:8080/');

  // execute curl
  var curlCmd = s.split('\n')[0].substring(3);
  var csvConverter = CsvToListConverter(fieldDelimiter: ' ');
  var curlArgs = csvConverter.convert(curlCmd)[0].map((i) => i.toString()).toList();
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
