// curl -L http://www.google.com
import 'package:http/http.dart' as http;

void main() async {
  var res = await http.get('http://www.google.com');
  if (res.statusCode != 200) throw Exception('get error: statusCode= ${res.statusCode}');
  print(res.body);
}
