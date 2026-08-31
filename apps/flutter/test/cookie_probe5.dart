import 'dart:io';
import 'package:http/http.dart' as http;
void main() async {
  final c = HttpClient();
  final req = await c.getUrl(Uri.parse('http://127.0.0.1:3081/?token=CoiEV4HhgPfOb7V01g2q-FMJyuS72AazKdlSORImREU'));
  req.followRedirects = false;
  final resp = await req.close();
  print('status: ${resp.statusCode}');
  resp.headers.forEach((name, values) {
    for (final v in values) print('${name}: $v');
  });
  c.close();
}
