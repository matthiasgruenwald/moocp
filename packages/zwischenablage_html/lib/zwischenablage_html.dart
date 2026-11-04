// HTML und Text zugleich in die Zwischenablage. Flutter selbst kennt nur Text;
// mit HTML fügt Strg+V in einem Editor wie dem von Moodle formatiert ein,
// der Text daneben dient Feldern, die nur Text nehmen.
//
// Nativ je Plattform über den Kanal „zwischenablage_html", derzeit nur
// Windows (E34). Auf anderen Plattformen, etwa dem Mac, wird der Kanal gar
// nicht erst gerufen: Es bleibt beim Text, ohne Absturz (E29). Scheitert der
// native Teil, bleibt es ebenfalls beim Text.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const _kanal = MethodChannel('zwischenablage_html');

/// Legt [html] als HTML in die Zwischenablage und [text] (ohne Angabe: den
/// Quelltext von [html]) als Text daneben. Gibt zurück, ob HTML dabei ist;
/// bei `false` liegt nur der Text in der Zwischenablage.
Future<bool> alsHtmlKopieren(String html, {String? text}) async {
  text ??= html;
  if (!Platform.isWindows) {
    await Clipboard.setData(ClipboardData(text: text));
    return false;
  }
  try {
    await _kanal.invokeMethod<void>('kopieren', {
      // Windows erwartet das Format „HTML Format" mit Kopf.
      'html': cfHtml(html),
      'text': text,
    });
    return true;
  } on PlatformException {
    // Zwischenablage gerade belegt oder Speicher fehlt: weiter mit Text.
  } on MissingPluginException {
    // Plattform ohne nativen Teil.
  }
  await Clipboard.setData(ClipboardData(text: text));
  return false;
}

/// Ein HTML-Fragment im Windows-Format „HTML Format" (CF_HTML): ein Kopf mit
/// den Stellen in Bytes von UTF-8, dann das Dokument mit den Marken um das
/// Fragment. Stimmen die Stellen nicht, fügt der Editor abgeschnittenen oder
/// verschobenen Text ein -- mit Umlauten zuerst, weil sie zwei Bytes haben.
String cfHtml(String fragment) {
  const vor = '<html><body><!--StartFragment-->';
  const nach = '<!--EndFragment--></body></html>';
  String kopf(int sh, int eh, int sf, int ef) => 'Version:0.9\r\n'
      'StartHTML:${'$sh'.padLeft(10, '0')}\r\n'
      'EndHTML:${'$eh'.padLeft(10, '0')}\r\n'
      'StartFragment:${'$sf'.padLeft(10, '0')}\r\n'
      'EndFragment:${'$ef'.padLeft(10, '0')}\r\n';
  int bytes(String s) => utf8.encode(s).length;
  final sh = bytes(kopf(0, 0, 0, 0));
  final sf = sh + bytes(vor);
  final ef = sf + bytes(fragment);
  final eh = ef + bytes(nach);
  return '${kopf(sh, eh, sf, ef)}$vor$fragment$nach';
}
