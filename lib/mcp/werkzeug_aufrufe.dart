// MCP-Aufrufe: Validierung, Abbruch, Freigabehinweis und Fehlerantworten.
import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../freigabe.dart';
import '../log.dart';
import '../moodle/moodle_zugang.dart';
import '../protokoll.dart';

class WerkzeugAufrufe {
  WerkzeugAufrufe(this.protokoll, this.freigaben, {required this.ausfuehren});
  final Future<String> Function(
    String,
    Map<String, dynamic>,
    Future<String> Function(),
  )
  ausfuehren;
  final Protokoll protokoll;
  final Freigaben freigaben;

  /// Ein Werkzeug: Aufruf ins Protokoll, Fehler als Werkzeugfehler zurück.
  void registrieren(
    McpServer server,
    String name, {
    required String titel,
    required String beschreibung,
    Map<String, JsonSchema> parameter = const {},
    List<String> pflicht = const [],
    bool nurLesen = false,
    bool zerstoerend = false,
    required Future<String> Function(Map<String, dynamic> a) ausfuehren,
  }) {
    server.registerTool(
      name,
      description: beschreibung,
      inputSchema: JsonSchema.object(properties: parameter, required: pflicht),
      annotations: ToolAnnotations(
        title: titel,
        readOnlyHint: nurLesen,
        destructiveHint: zerstoerend,
        openWorldHint: false,
      ),
      callback: (args, extra) async {
        final aufruf = jsonEncode(args);
        protokoll.eintrag(
          Art.werkzeug,
          '$name(${aufruf.length > 200 ? '${aufruf.substring(0, 199)}…' : aufruf})',
        );
        for (final p in pflicht) {
          if (args[p] == null) return _fehler('$p fehlt.');
        }
        // Hat das Werkzeug wegen der eingestellten Stufe ohne Freigabe
        // geschrieben, erfährt Claude das hier -- an einer Stelle für alle
        // Werkzeuge. Sonst kündigte der Skill eine Rückfrage an, die nie kommt.
        // Nur bei schreibenden Werkzeugen: Liefen zwei Aufrufe gleichzeitig,
        // zählte der Zähler sonst eine Freigabe dem lesenden zu.
        final vorher = freigaben.ausgelassen;
        final testsVorher = freigaben.testfreigaben;
        // Bricht der Client ab (sein Zeitlimit, ein Abbruch in der Sitzung),
        // verfallen die offenen Freigaben dieses Aufrufs (Freigaben.mitAbbruch).
        final abbruch = Completer<void>();
        void abbrechen() {
          if (!abbruch.isCompleted) abbruch.complete();
        }

        if (extra.signal.aborted) abbrechen();
        final horcht = extra.signal.onAbort.listen((_) => abbrechen());
        try {
          final text = await Freigaben.mitAbbruch(
            abbruch.future,
            () => this.ausfuehren(name, args, () => ausfuehren(args)),
          );
          protokoll.eintrag(Art.info, '$name: ${text.split('\n').first}');
          return CallToolResult.fromContent([
            TextContent(
              text:
                  '$text${nurLesen ? '' : _ohneFreigabe(freigaben.ausgelassen - vorher)}'
                  '${freigaben.testfreigaben > testsVorher ? '\nDebug-Testbetrieb: automatisch freigegeben, ohne persönliche Freigabe.' : ''}',
            ),
          ]);
        } on MoodleFehler catch (x) {
          protokoll.eintrag(Art.fehler, '$name: ${x.meldung}');
          return _fehler(x.meldung);
        } catch (x, st) {
          final b = fehlerBeschreibung(x, st);
          protokoll.eintrag(Art.fehler, '$name: $b');
          return _fehler('Unerwarteter Fehler: $b');
        } finally {
          await horcht.cancel();
        }
      },
    );
  }

  /// Angehängt an die Antwort eines Werkzeugs, das [n] Freigaben wegen der
  /// eingestellten Stufe ausgelassen hat.
  String _ohneFreigabe(int n) => n <= 0
      ? ''
      : '\n\nOhne Freigabe ausgeführt ($n ${n == 1 ? 'Vorgang' : 'Vorgänge'}): Die Lehrkraft hat '
            'die Bestätigungen in der App auf „${freigaben.stufe.text}" gestellt. Kündige keine '
            'Freigabe an, die nicht kommt, und schlage nicht vor, die Stufe zu ändern -- das ist '
            'ihre Entscheidung.';

  CallToolResult _fehler(String text) =>
      CallToolResult(content: [TextContent(text: text)], isError: true);
}
