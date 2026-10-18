// Der Dialog „Einstellungen": was sich dauerhaft einstellen lässt, ohne
// Anmeldedaten -- die stehen auf der Hauptseite.
//
// Zwei Abschnitte: die Update-Prüfung (update/update.dart) und der Weg zum
// Dialog „KI-Werkzeuge einrichten". Der Zugangsschlüssel steht hier bewusst
// nicht: Eingetragen wird er nur von der App selbst (E13), und jede Anzeige
// wäre ein weiterer Weg, ihn aus Versehen weiterzugeben. Wer ihn braucht,
// findet ihn in der README.

import 'dart:io';

import 'package:flutter/material.dart';

import 'einstellungen.dart';
import 'protokoll.dart';
import 'update/update.dart';
import 'update/update_dialoge.dart';

enum EinstellungenErgebnis {
  /// Nichts weiter zu tun.
  fertig,

  /// Die Lehrkraft will zu „KI-Werkzeuge einrichten"; der Aufrufer öffnet ihn,
  /// damit nicht zwei Dialoge übereinanderliegen.
  einrichten,

  /// Ein Update wird installiert: Die App muss sich jetzt beenden.
  beenden,
}

class EinstellungenDialog extends StatefulWidget {
  const EinstellungenDialog({
    required this.einstellungen,
    required this.protokoll,
    required this.eigene,
    required this.updateMoeglich,
    required this.sitzungLaeuft,
    super.key,
  });

  final Einstellungen einstellungen;
  final Protokoll protokoll;

  /// Die laufende Version, etwa „0.9.4".
  final String eigene;

  /// Ob sich diese App überhaupt selbst aktualisieren kann (update.dart).
  final bool updateMoeglich;

  /// Ob der MCP-Server läuft; dann hängt womöglich eine Sitzung eines KI-Werkzeugs
  /// daran, die ein Update verlöre.
  final bool sitzungLaeuft;

  @override
  State<EinstellungenDialog> createState() => _EinstellungenDialogState();
}

class _EinstellungenDialogState extends State<EinstellungenDialog> {
  bool _sucht = false;

  Future<void> _umschalten(bool an) async {
    setState(() => widget.einstellungen.updatePruefen = an);
    try {
      await widget.einstellungen.speichern();
    } catch (e) {
      widget.protokoll.eintrag(Art.fehler, 'Einstellungen nicht gespeichert (${e.runtimeType})');
    }
    widget.protokoll.eintrag(
        Art.info,
        an
            ? 'Update-Prüfung eingeschaltet: einmal täglich bei GitHub'
            : 'Update-Prüfung ausgeschaltet: keine Anfrage an GitHub');
  }

  Future<void> _suchen() async {
    setState(() => _sucht = true);
    final beenden = await updateSchritt(
      context,
      einstellungen: widget.einstellungen,
      protokoll: widget.protokoll,
      eigene: widget.eigene,
      manuell: true,
      sitzungLaeuft: widget.sitzungLaeuft,
    );
    if (!mounted) return;
    setState(() => _sucht = false);
    if (beenden) Navigator.pop(context, EinstellungenErgebnis.beenden);
  }

  @override
  Widget build(BuildContext context) {
    final klein = Theme.of(context).textTheme.bodySmall;
    final e = widget.einstellungen;
    final an = e.updatePruefen == true;
    return AlertDialog(
      title: const Text('Einstellungen'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Updates', style: Theme.of(context).textTheme.titleSmall),
            if (!widget.updateMoeglich)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    Platform.isWindows
                        ? 'Diese Version kann sich nicht selbst aktualisieren: Sie läuft nicht aus '
                            'dem Installationsverzeichnis, oder die Prüfung ist über die Kommandozeile '
                            'abgeschaltet ($keinUpdateSchalter).'
                        : 'Diese Version aktualisiert sich nicht selbst. Auf dem Mac prüft moocp nicht '
                            'bei GitHub und lädt nichts herunter; eine neue Version kommt von Hand.',
                    style: klein),
              )
            else ...[
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: an,
                onChanged: _sucht ? null : (v) => _umschalten(v ?? false),
                title: const Text('Einmal täglich bei GitHub nach einer neuen Version sehen'),
                subtitle: Text(
                    'GitHub erfährt dabei Ihre IP-Adresse und den Zeitpunkt. Nichts aus '
                    'Moodle wird übertragen.',
                    style: klein),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    e.updateZuletzt == null
                        ? 'Noch nicht gesucht. Sie verwenden moocp ${widget.eigene}.'
                        : 'Zuletzt gesucht am ${e.updateZuletzt}. Sie verwenden moocp ${widget.eigene}.',
                    style: klein),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed: _sucht ? null : _suchen,
                  child: Text(_sucht ? 'Sucht …' : 'Jetzt nach Updates suchen'),
                ),
              ),
            ],
            const Divider(height: 32),
            Text('KI-Werkzeuge', style: Theme.of(context).textTheme.titleSmall),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Claude Code, Codex CLI und LM Studio brauchen die Verbindung zu dieser App und '
                  'die Skills in der Version, die zu ihr gehört. Dort wählen Sie auch, welche '
                  'davon eingerichtet werden.',
                  style: klein),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _sucht ? null : () => Navigator.pop(context, EinstellungenErgebnis.einrichten),
                child: const Text('Verbindung und Skills prüfen'),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _sucht ? null : () => Navigator.pop(context, EinstellungenErgebnis.fertig),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
