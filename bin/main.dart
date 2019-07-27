import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:convert/convert.dart';

void runCmd(String cmd, List<String> args) {
  print('${cmd.toUpperCase()}:*******************************************************************');
  var res = Process.runSync(cmd, args);
  if (res.stderr.toString().isNotEmpty) throw Exception(res.stderr.toString());

  if (res.stdout[0] == '{') {
    var encoder = JsonEncoder.withIndent('  ');
    print(encoder.convert(jsonDecode(res.stdout)));
  } else {
    print(res.stdout);
  }
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
  runCmd(curlArgs[0], [...curlArgs.skip(1).toList(), '-s']);

  // execute dart
  var packagesFile = File(".packages");
  var packagesTemplFilename = Directory.systemTemp.path + '/.packages';
  packagesFile.copySync(packagesTemplFilename);
  var tempFilename = Directory.systemTemp.path + '/curl_testing_temp.dart';
  var tempFile = File(tempFilename)..writeAsStringSync(s, flush: true);
  runCmd('dart', [tempFile.path]);
  tempFile.deleteSync();
  File(packagesTemplFilename).deleteSync();
}
