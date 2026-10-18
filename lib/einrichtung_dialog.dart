// Der Dialog „KI-Werkzeuge einrichten": zeigt je gefundenem KI-Werkzeug, was
// an Verbindung und Skills nicht zu dieser App passt, und schreibt erst nach
// dem Klick auf „Installieren".
//
// Die App läuft nur, wenn mindestens ein Werkzeug eingerichtet ist. Wer das
// nicht kann oder will, beendet sie hier; einen Zustand „die App läuft, aber
// kein KI-Werkzeug kann mit ihr arbeiten" gibt es nicht. Darum kein
// „Abbrechen", und nach einem Fehler „Nochmal versuchen" statt weiter. Ein
// Skill, der nicht zur App passt, ruft Werkzeuge falsch auf. Haken gibt es
// bei den Werkzeugen und bei den wählbaren Skills (wahlSkills in
// einrichtung.dart); was gewählt ist, wird streng geprüft, was abgewählt
// ist, entfernt „Installieren".
//
// Die App öffnet den Dialog beim Start, wenn etwas nicht passt, und jederzeit
// über den Knopf „KI-Werkzeuge einrichten" in der Titelzeile.
//
// Rückgabe: true, wenn mindestens ein Werkzeug eingerichtet ist; sonst
// beendet der Aufrufer die App.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'einrichtung.dart';
import 'einstellungen.dart';
import 'log.dart';
import 'protokoll.dart';

class EinrichtungDialog extends StatefulWidget {
  const EinrichtungDialog({
    required this.stand,
    required this.pruefen,
    required this.einstellungen,
    required this.protokoll,
    required this.port,
    this.servername = mcpName,
    super.key,
  });

  /// Stand der Prüfung beim Start; null, wenn sie fehlgeschlagen ist.
  final Einrichtungsstand? stand;

  /// Dieselbe Prüfung wie beim Start, für „Nochmal prüfen" und nach dem
  /// Installieren.
  final Future<Einrichtungsstand> Function() pruefen;

  final Einstellungen einstellungen;
  final Protokoll protokoll;

  /// Port und Servername des Profils, für das die Einrichtung gilt (E31).
  final int port;
  final String servername;

  @override
  State<EinrichtungDialog> createState() => _EinrichtungDialogState();
}

class _EinrichtungDialogState extends State<EinrichtungDialog> {
  late Einrichtungsstand? _s = widget.stand;
  bool _laeuft = false;

  /// Ob in diesem Dialog etwas installiert wurde: Dann braucht es eine neue
  /// Sitzung im KI-Werkzeug.
  bool _installiert = false;

  /// Ergebnis je Zeile nach dem letzten Installieren; steht dort statt des
  /// Stands. Schlüssel: `<werkzeug>/verbindung` und `<werkzeug>/skills`.
  Map<String, String> _ergebnis = {};

  /// Alles erledigt: Nur noch „Weiter".
  bool get _fertig => _s != null && !_s!.brauchtEtwas;

  /// Mindestens ein Werkzeug ist eingerichtet: Die App kann laufen, auch
  /// wenn bei einem anderen noch etwas fehlt -- eines genügt.
  bool get _bereit => _s != null && _s!.bereit;

  void _protokoll(Art art, String text) => widget.protokoll.eintrag(art, 'KI-Werkzeuge einrichten: $text');

  Future<Einrichtungsstand?> _neuPruefen() async {
    try {
      return await widget.pruefen();
    } catch (x, st) {
      _protokoll(Art.fehler, 'Prüfung fehlgeschlagen: ${fehlerBeschreibung(x, st)}');
      return null;
    }
  }

  Future<void> _nochmalPruefen() async {
    setState(() => _laeuft = true);
    final neu = await _neuPruefen();
    if (!mounted) return;
    setState(() {
      _s = neu;
      _ergebnis = {};
      _laeuft = false;
    });
  }

  Future<void> _speichern() async {
    try {
      await widget.einstellungen.speichern();
    } catch (x, st) {
      _protokoll(Art.fehler, 'Wahl nicht gespeichert: ${fehlerBeschreibung(x, st)}');
    }
  }

  /// Haken bei einem wählbaren Skill: gleich speichern und neu prüfen, damit
  /// die Zeilen zeigen, was „Installieren" jetzt tun würde.
  Future<void> _skillWaehlen(String name, bool an) async {
    final neu = {...?_s?.gewaehlt};
    an ? neu.add(name) : neu.remove(name);
    widget.einstellungen.wahlSkills = neu;
    await _speichern();
    await _nochmalPruefen();
  }

  /// Haken bei einem Werkzeug, ebenso.
  Future<void> _werkzeugWaehlen(String id, bool an) async {
    final e = widget.einstellungen;
    final neu = {...e.werkzeugeAbgewaehlt};
    an ? neu.remove(id) : neu.add(id);
    e.werkzeugeAbgewaehlt = neu;
    await _speichern();
    await _nochmalPruefen();
  }

  Future<void> _installieren() async {
    final s = _s!;
    setState(() => _laeuft = true);
    final e = widget.einstellungen;
    final fehler = <String, String>{};
    final geblieben = <String, List<String>>{};

    for (final ws in s.werkzeuge) {
      if (!ws.brauchtEtwas) continue;
      final w = ws.werkzeug;
      final soll = ws.gewaehlt;
      // Die Verbindung: eintragen, wenn gewählt, sonst austragen -- beides
      // nur, wenn das Werkzeug es zulässt (Claude Code ohne claude.exe nicht).
      if (soll ? w.bedienbar && !ws.verbunden : ws.austragbar && ws.verbindung != Verbindung.fehlt) {
        try {
          final f = soll
              ? await w.eintragen(widget.port, e.schluessel, name: widget.servername)
              : await w.austragen(name: widget.servername);
          if (f != null) fehler['${w.id}/verbindung'] = f;
        } catch (x, st) {
          fehler['${w.id}/verbindung'] = 'Fehler (${x.runtimeType})';
          _protokoll(Art.fehler, '${w.name}, Verbindung: ${fehlerBeschreibung(x, st)}');
        }
      }
      final rest = <String>[];
      for (final paket in ws.skills) {
        if (ws.stand[paket.name]!.aktuell) continue;
        try {
          rest.addAll(skillInstallieren(paket, Directory(p.join(w.skillOrdner.path, paket.name))));
        } catch (x, st) {
          fehler['${w.id}/skills'] = 'Skill ${paket.name}: Fehler (${x.runtimeType})';
          _protokoll(Art.fehler, '${w.name}, Skill ${paket.name}: ${fehlerBeschreibung(x, st)}');
        }
      }
      for (final name in ws.entfernen) {
        try {
          rest.addAll(skillEntfernen(Directory(p.join(w.skillOrdner.path, name))).map((f) => '$name/$f'));
        } catch (x, st) {
          fehler['${w.id}/skills'] = 'Skill $name entfernen: Fehler (${x.runtimeType})';
          _protokoll(Art.fehler, '${w.name}, Skill $name entfernen: ${fehlerBeschreibung(x, st)}');
        }
      }
      geblieben[w.id] = rest;
    }

    // Ob es angekommen ist, sagt dieselbe Prüfung wie beim Start, nicht der
    // Rückgabewert eines Programms oder Schreibvorgangs.
    final neu = await _neuPruefen();
    final ergebnis = <String, String>{};
    if (neu != null) {
      for (final vorher in s.werkzeuge) {
        if (!vorher.brauchtEtwas) continue;
        final w = vorher.werkzeug;
        final jetzt = neu.werkzeuge.where((x) => x.werkzeug.id == w.id).firstOrNull;
        if (jetzt == null) continue;
        final vk = '${w.id}/verbindung';
        final verbindungSoll = vorher.gewaehlt ? Verbindung.aktuell : Verbindung.fehlt;
        // Nur, was die App versucht hat; was von Hand geht, steht als Hinweis
        // in der Zeile.
        if (vorher.verbindung != verbindungSoll && (vorher.gewaehlt ? w.bedienbar : vorher.austragbar)) {
          if (jetzt.verbindung == verbindungSoll) {
            ergebnis[vk] = vorher.gewaehlt ? 'eingetragen' : 'ausgetragen';
            _protokoll(Art.info, '${w.name}: Verbindung ${ergebnis[vk]}');
          } else {
            final f = fehler[vk] ?? w.hindernis;
            ergebnis[vk] = 'nicht angekommen${f == null ? '' : ' ($f)'}';
            _protokoll(Art.fehler, '${w.name}: Verbindung ${ergebnis[vk]}');
          }
        }
        final sk = '${w.id}/skills';
        final skillsVorher = vorher.skills.any((x) => !vorher.stand[x.name]!.aktuell) || vorher.entfernen.isNotEmpty;
        if (skillsVorher) {
          final offen = [
            for (final x in jetzt.skills)
              if (!jetzt.stand[x.name]!.aktuell) x.name,
            ...jetzt.entfernen,
          ];
          if (offen.isEmpty) {
            ergebnis[sk] = 'erledigt';
            _protokoll(Art.info, '${w.name}: Skills erledigt');
          } else {
            final weg = geblieben[w.id] ?? const <String>[];
            ergebnis[sk] = fehler[sk] ??
                'weicht noch ab: ${offen.join(', ')}${weg.isEmpty ? '' : '; nicht entfernbar: ${weg.join(', ')}'}';
            _protokoll(Art.fehler, '${w.name}: Skills ${ergebnis[sk]}');
          }
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _s = neu;
      _ergebnis = ergebnis;
      _installiert = true;
      _laeuft = false;
    });
  }

  String _verbindungText(Werkzeugstand ws) {
    final w = ws.werkzeug;
    if (!ws.gewaehlt) {
      if (ws.verbindung == Verbindung.fehlt) return 'nicht eingetragen';
      if (ws.austragbar) return 'wird ausgetragen';
      return 'eingetragen, lässt sich nicht austragen';
    }
    return w.verbindungText(ws.verbindung);
  }

  /// Ein Satz für alle Skills eines Werkzeugs: welche fehlen, welche
  /// veraltet sind, welche wegkommen. Je Skill eine Zeile wäre bei drei
  /// Werkzeugen ein Dutzend Zeilen, die alle dasselbe sagen.
  String _skillText(Werkzeugstand ws) {
    final fehlen = [for (final x in ws.skills) if (ws.stand[x.name]!.ordnerFehlt) x.name];
    final alt = [for (final x in ws.skills) if (!ws.stand[x.name]!.ordnerFehlt && !ws.stand[x.name]!.aktuell) x.name];
    final teile = [
      if (fehlen.isNotEmpty) 'nicht installiert: ${fehlen.join(', ')}',
      if (alt.isNotEmpty) 'müssen aktualisiert werden: ${alt.join(', ')}',
      if (ws.entfernen.isNotEmpty) 'werden entfernt: ${ws.entfernen.join(', ')}',
    ];
    if (teile.isNotEmpty) return teile.join('; ');
    if (!ws.gewaehlt) return 'keine installiert';
    return 'aktuell';
  }

  bool _skillsAktuell(Werkzeugstand ws) => ws.skills.every((x) => ws.stand[x.name]!.aktuell) && ws.entfernen.isEmpty;

  Widget _zeile(String titel, String schluessel, bool aktuell, String stand) {
    final gescheitert = !aktuell && _ergebnis.containsKey(schluessel);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 40),
      leading: Icon(
        aktuell
            ? Icons.check_circle
            : gescheitert
                ? Icons.error_outline
                : Icons.radio_button_unchecked,
        color: aktuell
            ? Colors.green
            : gescheitert
                ? Theme.of(context).colorScheme.error
                : null,
      ),
      title: Text(titel),
      subtitle: Text(_ergebnis[schluessel] ?? stand),
    );
  }

  /// Ein Werkzeug: Haken mit Name und wohin die Inhalte gehen, darunter
  /// Verbindung und Skills.
  List<Widget> _werkzeug(Werkzeugstand ws) {
    final w = ws.werkzeug;
    final skillNamen = ws.skills.map((x) => x.name).join(', ');
    return [
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: ws.gewaehlt,
        onChanged: _laeuft ? null : (v) => _werkzeugWaehlen(w.id, v ?? false),
        title: Text(w.name, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(ws.gewaehlt ? w.datenziel : '${w.datenziel} -- nicht gewählt'),
      ),
      _zeile('Verbindung', '${w.id}/verbindung', ws.gewaehlt ? ws.verbunden : ws.verbindung == Verbindung.fehlt,
          _verbindungText(ws)),
      _zeile(ws.gewaehlt ? 'Skills ($skillNamen)' : 'Skills', '${w.id}/skills', _skillsAktuell(ws), _skillText(ws)),
      if (ws.brauchtEtwas && w.hindernis != null)
        Padding(padding: const EdgeInsets.only(left: 40), child: _hinweis(w.hindernis!)),
    ];
  }

  /// Ein wählbarer Skill: Haken, darunter wofür er ist. Die Wahl gilt für
  /// alle Werkzeuge -- einen Skill nur in einem zu wollen, ergibt keinen Sinn.
  Widget _wahlZeile(Einrichtungsstand s, SkillPaket paket) {
    final name = paket.name;
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: s.gewaehlt.contains(name),
      onChanged: _laeuft ? null : (v) => _skillWaehlen(name, v ?? false),
      title: Text('Skill $name'),
      subtitle: Text(wahlSkills[name]!),
    );
  }

  Widget _hinweis(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );

  String get _schluss {
    final s = _s;
    if (s != null && s.werkzeuge.isEmpty) {
      return 'Kein KI-Werkzeug gefunden. Ohne eines kann niemand mit dieser App arbeiten. '
          '„Beenden" schließt die App.';
    }
    if (!_fertig) {
      return _bereit
          ? 'Noch nicht alles erledigt. Mit „Weiter" arbeitet die App mit dem, was eingerichtet ist; '
              'den Rest holen Sie später über die Einstellungen nach.'
          : 'Ohne ein eingerichtetes KI-Werkzeug kann niemand mit dieser App arbeiten. „Beenden" schließt die App.';
    }
    return _installiert
        ? 'Eingerichtet. Im KI-Werkzeug eine neue Sitzung starten, damit die Änderungen wirken.'
        : 'Verbindung und Skills sind aktuell.';
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final List<Widget> knoepfe;
    if (_fertig) {
      knoepfe = [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Weiter'))];
    } else {
      final einrichtbar = s != null && s.einrichtbar;
      knoepfe = [
        TextButton(onPressed: _laeuft ? null : () => Navigator.pop(context, false), child: const Text('Beenden')),
        if (_bereit)
          OutlinedButton(onPressed: _laeuft ? null : () => Navigator.pop(context, true), child: const Text('Weiter')),
        FilledButton(
          onPressed: _laeuft ? null : (einrichtbar ? _installieren : _nochmalPruefen),
          child: Text(!einrichtbar
              ? 'Nochmal prüfen'
              : _ergebnis.isEmpty
                  ? 'Installieren'
                  : 'Nochmal versuchen'),
        ),
      ];
    }
    return AlertDialog(
      title: const Text('KI-Werkzeuge einrichten'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Damit ein KI-Werkzeug mit dieser App arbeiten kann, braucht es die Verbindung zur '
                'App und die Skills in der Version, die zu dieser App gehört. Eingerichtet wird jedes '
                'Werkzeug mit Haken; eines genügt.'),
            const SizedBox(height: 8),
            if (s != null) ...[
              for (final ws in s.werkzeuge) ..._werkzeug(ws),
              if (s.werkzeuge.isEmpty)
                _hinweis('Gesucht wurde nach Claude Code (auch in Claude Desktop), Codex CLI und LM Studio. '
                    'Eines davon installieren und einmal starten, danach „Nochmal prüfen".'),
              // Das Wählbare für sich, damit es nicht wie ein Pflichtteil aussieht.
              if (s.werkzeuge.isNotEmpty && s.skills.any((x) => wahlSkills.containsKey(x.name))) ...[
                const Divider(height: 24),
                Text('Wählbare Skills', style: Theme.of(context).textTheme.titleSmall),
                for (final paket in s.skills)
                  if (wahlSkills.containsKey(paket.name)) _wahlZeile(s, paket),
              ],
            ],
            if (s == null) _hinweis('Die Prüfung ist fehlgeschlagen; Einzelheiten stehen im Protokoll.'),
            if (s != null && !s.python && s.gewaehlt.contains('lernsituation'))
              _hinweis('Python nicht gefunden. Die Selbstprüfung des Skills lernsituation läuft ohne '
                  'Python nicht; alles andere schon.'),
            if (_laeuft) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_schluss, style: Theme.of(context).textTheme.titleSmall),
            ),
          ]),
        ),
      ),
      actions: knoepfe,
    );
  }
}
