part of 'mcp_dienst.dart';

extension _Lernlandkarten on McpDienst {
  void _lernlandkartenRegistrieren(McpServer server) {
    _aufrufe.registrieren(
      server,
      'lernlandkarte_verknuepfungen_setzen',
      titel: 'Lernlandkarten-Ziele ändern',
      beschreibung:
          'Ändert ausdrücklich entschiedene Zuordnungen von Kartenorten zu vorhandenen Aktivitäten '
          'derselben Kursstruktur. Lies die Karte vorher mit aktivitaet_lesen; aktuell und ziel sind cmids, '
          '0 steht für keine Verknüpfung. Das Werkzeug prüft Kartenname, Ortskennung, bisherigen Stand, '
          'Zielkurs und Zielaktivität, fragt in der App nach Freigabe und liest den geschriebenen Stand zurück. '
          'SVG, Wege, Farben und nicht genannte Orte bleiben unverändert. Mehrdeutige oder fehlende Ziele '
          'werden nicht automatisch entschieden.',
      parameter: {
        'cmid': McpDienst._cmid,
        'name': McpDienst._name,
        'zuordnungen': JsonSchema.array(
          items: JsonSchema.object(
            properties: {
              'ort': JsonSchema.string(
                description: 'Ortskennung aus der gelesenen Lernlandkarte',
              ),
              'aktuell': JsonSchema.integer(
                description: 'Bisherige cmid am Ort; 0, wenn nicht verknüpft',
              ),
              'ziel': JsonSchema.integer(
                description:
                    'Entschiedene Ziel-cmid im selben Kurs; 0 zum Lösen',
              ),
            },
            required: ['ort', 'aktuell', 'ziel'],
          ),
        ),
      },
      pflicht: ['cmid', 'name', 'zuordnungen'],
      zerstoerend: true,
      ausfuehren: (a) => lernlandkarteVerknuepfungenSetzen(
        moodle,
        freigaben,
        arbeitsordner: arbeitsordner,
        cmid: _zahl(a, 'cmid'),
        name: _text(a, 'name'),
        zuordnungen: [
          for (final x in (a['zuordnungen'] as List).whereType<Map>())
            x.cast<String, Object?>(),
        ],
      ),
    );

  }
}
