// Die Zwischenablage der Übergabe als HTML (Paket zwischenablage_html): Windows
// liest das Fragment über die Stellen im Kopf, in Bytes von UTF-8. Stimmen
// sie nicht, fügt der Editor abgeschnittenen oder verschobenen Text ein --
// mit Umlauten zuerst, weil sie zwei Bytes haben.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zwischenablage_html/zwischenablage_html.dart';

void main() {
  test('Die Stellen im Kopf treffen Dokument und Fragment, auch mit Umlauten', () {
    const fragment = '<p>Prüfung: „Größe" &amp; Maß</p><pre class="language-html"><code>&lt;b&gt;</code></pre>';
    final cf = cfHtml(fragment);
    final bytes = utf8.encode(cf);
    int stelle(String name) => int.parse(RegExp('$name:(\\d{10})').firstMatch(cf)!.group(1)!);
    String zwischen(int von, int bis) => utf8.decode(bytes.sublist(von, bis));

    expect(cf, startsWith('Version:0.9\r\n'));
    expect(zwischen(stelle('StartFragment'), stelle('EndFragment')), fragment);
    expect(zwischen(stelle('StartHTML'), stelle('EndHTML')),
        '<html><body><!--StartFragment-->$fragment<!--EndFragment--></body></html>');
    expect(stelle('EndHTML'), bytes.length);
  });
}
