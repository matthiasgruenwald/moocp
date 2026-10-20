part of 'mcp_dienst.dart';

String? _cmidnummer(Formular form) {
  final wert = wertIn(form.felder, 'cmidnumber')?.trim();
  return wert == null || wert.isEmpty ? null : wert;
}

extension _Uebertragung on McpDienst {
  Future<String> _nachTestkopie(
    Future<String> lauf,
    Vorgaenge vorgaenge,
    String? Function() nummer,
  ) async {
    final text = await lauf;
    final eigen = await _testbetrieb.kopienErfassen(
      profil,
      testzugang ?? Testzugang.fuer(profil),
      vorgaenge,
      nummer(),
    );
    return eigen
        ? '$text\nDebug-Testbetrieb: Belegte eigene ZZ-Kopien für Folgeaktionen erfasst.'
        : text;
  }

  Future<String> _nachTestsicherung(
    Future<String> lauf,
    Vorgaenge vorgaenge,
    String? Function() nummer,
    Map<String, dynamic> args,
  ) async {
    final text = await lauf;
    final id = nummer();
    final v = id == null ? null : await vorgaenge.finde(id);
    if (v != null) {
      await _testbetrieb.sicherungMerken(
        profil,
        testzugang ?? Testzugang.fuer(profil),
        vorgaenge,
        v,
        args,
      );
    }
    return text;
  }

  /// Übertragung in einem Auftrag (Issue #10). Die Entscheidungen stehen in
  /// uebertragung_lauf.dart; hier nur die Verdrahtung mit Moodle und Freigabe.
  /// Reihenfolge: prüfen, Wiederholungsschutz, eine Freigabe mit der
  /// Zusammenfassung, sichern (nur ohne datei), dann je Ziel wiederherstellen.
  Future<String> _uebertragen(
    Vorgaenge vorgaenge,
    Map<String, dynamic> a, {
    required void Function(String werkzeug, String? id) beiVorgang,
  }) async {
    final sichtbarkeit = WiederherstellungsSichtbarkeit.aus(a['sichtbarkeit'] as String?);
    final auftragsProfil = profil.kennung;
    final auftragsInstanz = moodle.basis;
    bool bindungPasst() =>
        profil.kennung == auftragsProfil &&
        moodle.angemeldet &&
        moodle.basis == auftragsInstanz;
    final ziele = <ZielAngabe>[];
    for (final x in (a['ziele'] as List?) ?? const []) {
      final m = McpDienst._karte(x);
      ziele.add(
        ZielAngabe(
          kurs: _zahl(m, 'kurs'),
          name: _text(m, 'name'),
          weg: m['weg'] as String?,
          loeschend: m['loeschend'] == true,
        ),
      );
    }
    final angegeben = a['datei'] as String?;
    final quellkurs = angegeben == null ? _zahlOder(a, 'kurs') : null;
    if (angegeben == null &&
        (quellkurs == null || a['name_des_kurses'] == null)) {
      return 'Ohne datei braucht es kurs (Quellkurs) und name_des_kurses. Nichts geschehen.';
    }

    final planung = pruefeZiele(ziele, quellkurs: quellkurs);
    if (planung case PlanungRueckfrage(:final text)) return text;
    final geprueft = (planung as PlanungOk).ziele;

    final protokoll = await Uebertragungsprotokoll.laden(
      uebertragungsprotokollPfad ??
          p.join(einstellungenOrdner, 'uebertragungen.json'),
    );
    final rueckfragen = <String>[];
    for (final z in geprueft) {
      final r = wiederholungsRueckfrage(
        protokoll.eintraege,
        profil: profil.kennung,
        kurs: z.kurs,
        datei: angegeben,
        quellkurs: quellkurs,
      );
      if (r != null) rueckfragen.add('Kurs ${z.kurs} („${z.name}"): $r');
    }
    if (rueckfragen.isNotEmpty) return rueckfragen.join('\n\n');

    // Lernlandkarten und Verweisziele erfassen, bevor etwas kopiert wird.
    // Nur lesend; ohne Quellkurs (mit datei) gibt es nichts zu erfassen.
    Future<List<KartenQuelle>> quelleErfassen() async => quellkurs == null
        ? const <KartenQuelle>[]
        : await kartenErfassen(
            moodle,
            arbeitsordner: arbeitsordner,
            kurs: quellkurs,
            aktivitaeten: [
              for (final x in (a['aktivitaeten'] as List?) ?? const [])
                _zahl(McpDienst._karte(x), 'cmid'),
            ],
            abschnitte: [
              for (final x in (a['abschnitte'] as List?) ?? const [])
                _zahl(McpDienst._karte(x), 'id'),
            ],
            ganzerKurs: a['ganzer_kurs'] == true,
          );
    final karten = await quelleErfassen();
    Future<bool> quelleUnveraendert() async {
      if (!bindungPasst()) return false;
      final frisch = await quelleErfassen();
      return jsonEncode([
            for (final k in karten) [k.cmid, k.name, k.stand, k.formularstand],
          ]) ==
          jsonEncode([
            for (final k in frisch) [k.cmid, k.name, k.stand, k.formularstand],
          ]);
    }

    final kartenZeilen = [
      for (final k in karten) ...[
        'Lernlandkarte „${k.name}" (cmid ${k.cmid}): ${k.orte.length} verknüpfte '
            '${k.orte.length == 1 ? 'Ort' : 'Orte'}. Nach dem Kopieren verknüpft die App sie in jedem Zielkurs '
            'neu auf die dort kopierten Aktivitäten (je Karte eine weitere Freigabe); '
            'ihre Sichtbarkeit folgt der gewählten Wiederherstellung.',
        for (final o in k.orte)
          if (!o.mitkopiert)
            '  Ort ${o.ort} zeigt auf „${o.zielName ?? 'cmid ${o.quellZiel}'}", das nicht mitkopiert wird: bleibt ungelöst, '
                'es wird nichts zusätzlich kopiert.',
      ],
    ];

    // Die Zusammenfassung vor dem ersten Schreibschritt (Issue #5, uebertragungsZusammenfassung).
    final zielZeilen = [
      for (final z in geprueft)
        '„${z.name}" (Kurs ${z.kurs}): ${z.weg.nennung}',
    ];
    final List<String> punkte;
    if (quellkurs != null) {
      final anzahlAkt = (a['aktivitaeten'] as List?)?.length ?? 0;
      final anzahlAbs = (a['abschnitte'] as List?)?.length ?? 0;
      punkte = uebertragungsZusammenfassung(
        Plan(
          quelle: Endpunkt(profil, quellkurs),
          ziele: [for (final z in geprueft) Endpunkt(profil, z.kurs)],
        ),
        kursnamen: {
          Endpunkt(profil, quellkurs): _text(a, 'name_des_kurses'),
          for (final z in geprueft) Endpunkt(profil, z.kurs): z.name,
        },
        inhalt: anzahlAkt == 0 && anzahlAbs == 0
            ? 'ganzer Kurs'
            : '$anzahlAkt Aktivitäten, $anzahlAbs Abschnitte',
        wiederherstellung: geprueft
            .map((z) => '„${z.name}": ${z.weg.nennung}')
            .join('; '),
      ).split('\n');
    } else {
      punkte = [
        'Profil: ${profil.name}',
        'Quelle: Sicherungsdatei $angegeben (vorhanden, wird nicht neu gesichert)',
        'Zielkurse (${geprueft.length}):',
        for (final z in zielZeilen) '  - $z',
      ];
    }
    final ja = await freigaben.anfragen(
      FreigabeAnfrage(
        titel:
            'Übertragung in ${geprueft.length} ${geprueft.length == 1 ? 'Kurs' : 'Kurse'} starten?',
        punkte: [
          ...punkte,
          sichtbarkeit.freigabe,
          ...kartenZeilen,
          'Je Ziel ein eigener Vorgang, nacheinander. Ein Fehler stoppt die anderen Ziele nicht; eine Ablehnung schon.',
          'Eine Einfüge-Wiederherstellung kann Inhalte doppelt anlegen. Ein Aktualisieren ist nicht zugesagt.',
        ],
        vergleich: const [],
        knopf: 'Übertragen',
        ohneEntscheidung: 'wird nichts übertragen',
      ),
    );
    if (!ja) {
      return 'Nicht übertragen: in der App abgelehnt oder nicht innerhalb von '
          '${freigaben.frist.inMinutes} Minuten freigegeben. Nichts geändert.';
    }

    if (karten.isNotEmpty && !await quelleUnveraendert()) {
      return 'Die Quellauswahl wurde seit dem Erfassen geändert. Nichts übertragen; neu lesen und planen.';
    }

    // Ohne datei zuerst auf dieser Instanz sichern. Die Datei gilt nur, wenn der Vorgang fertig ist.
    final String datei;
    String? sicherungNummer;
    if (angegeben != null) {
      datei = angegeben;
    } else {
      String? sicherungVid;
      beiVorgang('sicherung_status', null);
      final sicherungText = await auswahlSichern(
        moodle,
        freigaben,
        vorgaenge,
        kurs: quellkurs!,
        name: _text(a, 'name_des_kurses'),
        aktivitaeten: [
          for (final x in (a['aktivitaeten'] as List?) ?? const [])
            (
              cmid: _zahl(McpDienst._karte(x), 'cmid'),
              name: _text(McpDienst._karte(x), 'name'),
            ),
        ],
        abschnitte: [
          for (final x in (a['abschnitte'] as List?) ?? const [])
            (
              id: _zahl(McpDienst._karte(x), 'id'),
              name: _text(McpDienst._karte(x), 'name'),
            ),
        ],
        ganzerKurs: a['ganzer_kurs'] == true,
        zielOrdner: a['ziel_ordner'] as String?,
        beiVorgang: (id) {
          sicherungVid = id;
          beiVorgang('sicherung_status', id);
        },
      );
      final id = sicherungVid;
      if (id == null) return sicherungText;
      final sv = await vorgaenge.finde(id);
      if (sv == null || sv.stand != SicherungStand.fertig || sv.datei.isEmpty) {
        return 'Die Sicherung ist nicht fertig (Nummer $id). Nichts übertragen.\n$sicherungText';
      }
      datei = sv.datei;
      sicherungNummer = id;
      await _testbetrieb.sicherungMerken(
        profil,
        testzugang ?? Testzugang.fuer(profil),
        vorgaenge,
        sv,
        a,
      );
    }

    if (karten.isNotEmpty && !await quelleUnveraendert()) {
      return 'Die Quellauswahl wurde seit dem Erfassen geändert. Die Sicherung wurde erstellt, '
          'aber nichts übertragen; neu lesen und planen.';
    }
    var archivHatKarten = false;

    // Ein Ziel: eigener Vorgang, Stand aus dem Vorgang. Ohne Vorgangsnummer hat die
    // App abgelehnt (wiederherstellen legt den Vorgang erst nach der Freigabe an).
    Future<ZielErgebnis> lauf(PlanZiel z) async {
      if (!bindungPasst()) {
        throw MoodleFehler(
          'Profil oder Instanz der Übertragung wurde gewechselt. Nichts weiter gestartet.',
        );
      }
      beiVorgang('wiederherstellung_status', null);
      String? vid;
      String text = '';
      try {
        text = await wiederherstellen(
          moodle,
          freigaben,
          vorgaenge,
          datei: datei,
          instanz: profil.name,
          profilKennung: profil.kennung,
          weg: z.weg.nennung,
          kurs: z.kurs,
          name: z.name,
          loeschend: z.weg.loescht,
          sichtbarkeit: sichtbarkeit,
          beiVorgang: (id) {
            vid = id;
            beiVorgang('wiederherstellung_status', id);
          },
        );
      } on MoodleFehler catch (e) {
        if (vid == null) {
          return ZielErgebnis(ZielStand.fehlgeschlagen, text: e.meldung);
        }
        text = e.meldung;
      }
      final id = vid;
      if (id == null) return ZielErgebnis(ZielStand.abgelehnt, text: text);
      final v = await vorgaenge.finde(id);
      archivHatKarten |=
          v?.wiederherstellungAktivitaeten?.any(
            (x) => x.modul == 'learningmap',
          ) ??
          false;
      return ZielErgebnis(
        zielStandAus(v?.wiederherstellung),
        vorgang: id,
        text: text,
      );
    }

    // Nach dem Kopieren eines Ziels: seine Karten auf die dort belegten Kopien verknüpfen.
    Future<KartenErgebnis?> kartenLauf(PlanZiel z, ZielErgebnis restore) async {
      final id = restore.vorgang;
      final v = id == null ? null : await vorgaenge.finde(id);
      if (v == null ||
          v.kurs != z.kurs ||
          v.wiederherstellungAktivitaeten == null ||
          v.vorherCmids == null) {
        return const KartenErgebnis(
          KartenStand.offen,
          'Der Kopiervorgang dieses Ziels ist nicht belegt (Nummer, Kurs oder Archivliste fehlen). Die Karten bleiben unverknüpft.',
        );
      }
      void pruefeKartenBindung() {
        if (!bindungPasst()) {
          throw MoodleFehler(
            'Profil oder Instanz der Übertragung wurde gewechselt. Nichts weiter verknüpft.',
          );
        }
        vorgaenge.pruefeBindung(v);
      }

      pruefeKartenBindung();
      final jetzt = await kursLesen(moodle, z.kurs);
      final vorher = v.vorherCmids!.toSet();
      final quellenTitel = {
        for (final k in karten) 'learningmap\u0000${k.name}',
        for (final k in karten)
          for (final o in k.orte)
            if (o.mitkopiert && o.zielModul != null && o.zielName != null)
              '${o.zielModul}\u0000${o.zielName}',
      };
      final kandidaten = [
        for (final x in jetzt.nachCmid.values)
          if (!vorher.contains(x.cmid) &&
              quellenTitel.contains('${x.modul}\u0000${x.name}'))
            x,
      ];
      final belege = <int, KartenBeleg>{};
      Future<void> belegLesen(KursAktivitaet kandidat) async {
        try {
          final form = await formularHolen(
            moodle,
            Formularziel.aktivitaet(kandidat.cmid).adresse,
          );
          final stand = formularInhaltsstand(
            await formularLesen(
              moodle,
              Formularziel.aktivitaet(kandidat.cmid),
              arbeitsordner,
            ),
          );
          belege[kandidat.cmid] = KartenBeleg(
            idnummer: _cmidnummer(form),
            formularstand: stand,
            kartendaten: kandidat.modul == 'learningmap'
                ? lernlandkarteLesen(form.form)
                : null,
          );
        } on MoodleFehler {
          belege[kandidat.cmid] = const KartenBeleg(
            idnummer: null,
            formularstand: null,
          );
        }
      }

      for (final kandidat in kandidaten) {
        await belegLesen(kandidat);
      }
      // Ein Aktivität kann während der Formularlesungen parallel auftauchen.
      // Neue passende Kandidaten gehören zur Mehrdeutigkeitsprüfung dazu.
      pruefeKartenBindung();
      final frisch = await kursLesen(moodle, z.kurs);
      final frischeKandidaten = [
        for (final x in frisch.nachCmid.values)
          if (!vorher.contains(x.cmid) &&
              quellenTitel.contains('${x.modul}\u0000${x.name}'))
            x,
      ];
      for (final kandidat in frischeKandidaten) {
        if (!belege.containsKey(kandidat.cmid)) await belegLesen(kandidat);
      }
      final zuordnungen = kartenZuordnen(
        karten,
        vorher: vorher,
        aktuell: [
          for (final x in frisch.nachCmid.values)
            (cmid: x.cmid, modul: x.modul, titel: x.name),
        ],
        belege: belege,
      );
      final ergebnisse = <KartenErgebnis>[];
      for (var i = 0; i < zuordnungen.length; i++) {
        final zu = zuordnungen[i];
        final ergebnis = await kartenVerknuepfen(
          moodle,
          freigaben,
          arbeitsordner: arbeitsordner,
          kurs: z.kurs,
          zuordnung: zu,
          sichtbarkeit: sichtbarkeit,
          pruefeBindung: pruefeKartenBindung,
        );
        ergebnisse.add(ergebnis);
        if (ergebnis.freigabeAbgelehnt) {
          for (final nichtBegonnen in zuordnungen.skip(i + 1)) {
            ergebnisse.add(
              KartenErgebnis(
                KartenStand.offen,
                'Lernlandkarte „${nichtBegonnen.quelle.name}“ nicht begonnen: '
                'Die Freigabe der vorherigen Karte wurde abgelehnt.',
              ),
            );
          }
          break;
        }
      }
      final stand = ergebnisse.any((e) => e.stand == KartenStand.unklar)
          ? KartenStand.unklar
          : ergebnisse.any((e) => e.stand == KartenStand.offen)
          ? KartenStand.offen
          : KartenStand.verknuepft;
      return KartenErgebnis(
        stand,
        ergebnisse.map((e) => e.text).join(' '),
        freigabeAbgelehnt: ergebnisse.any((e) => e.freigabeAbgelehnt),
      );
    }

    final berichte = await uebertragungAusfuehren(
      geprueft,
      datei: datei,
      profil: profil.kennung,
      quellkurs: quellkurs,
      protokoll: protokoll,
      lauf: lauf,
      kartenLauf: karten.isEmpty ? null : kartenLauf,
    );
    for (final bericht in berichte) {
      await _testbetrieb.kopienErfassen(
        profil,
        testzugang ?? Testzugang.fuer(profil),
        vorgaenge,
        bericht.vorgang,
      );
    }
    var kopf = sicherungNummer == null
        ? ''
        : 'Quelle gesichert: Nummer $sicherungNummer, Datei $datei.\n';
    if (angegeben != null && archivHatKarten) {
      kopf +=
          'Hinweis: Das Archiv enthält Lernlandkarten. Mit datei werden sie nicht neu verknüpft '
          '(der Quellkurs ist nicht erfasst). Sichtbarkeit und Verweise in jedem Ziel prüfen. '
          'Für die Verteilung samt Karte ohne datei übertragen (kurs, aktivitaeten, abschnitte).\n';
    }
    return '$kopf${uebertragungsBericht(berichte)}';
  }
}
