import 'dart:io';
import 'package:csv/csv.dart';

main(List<String> args) {
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
  var curlArgs =
      CsvToListConverter(fieldDelimiter: ' ').convert(curlCmd)[0].map((i) => i.toString()).toList();
  var curlRes = Process.runSync(curlArgs[0], [...curlArgs.skip(1).toList(), '-s']);
  print('CURL:***********************************************************************************');
  print(curlRes.stdout);
  print(curlRes.stderr);

  // execute dart
  var packagesFile = File(".packages");
  var packagesTemplFilename = Directory.systemTemp.path + '/.packages';
  packagesFile.copySync(packagesTemplFilename);

  var tempFilename = Directory.systemTemp.path + '/curl_testing_temp.dart';
  var tempFile = File(tempFilename)..writeAsStringSync(s, flush: true);
  var dartRes = Process.runSync('dart', [tempFile.path]);
  tempFile.deleteSync();
  File(packagesTemplFilename).deleteSync();

  print('DART:***********************************************************************************');
  print(dartRes.stdout);
  print(dartRes.stderr);
}
