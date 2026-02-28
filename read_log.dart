import 'dart:io';

void main() {
  var bytes = File('verification_log.txt').readAsBytesSync();
  var text = String.fromCharCodes(bytes);
  print(text);
}
