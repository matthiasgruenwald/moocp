part of 'mcp_dienst.dart';

extension _Uebertragung on McpDienst {
  /// Übertragung in einem Auftrag (Issue #10). Die Entscheidungen stehen in
  /// uebertragung_lauf.dart; hier nur die Verdrahtung mit Moodle und Freigabe.
  /// Reihenfolge: prüfen, Wiederholungsschutz, eine Freigabe mit der
  /// Zusammenfassung, sichern (nur ohne datei), dann je Ziel wiederherstellen.
  Future<String> _uebertragen(
    Vorgaenge vorgaenge,
    Map<String, dynamic> a, {
    required void Function(String werkzeug, String? id) beiVorgang,
  }) async {
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
            (cmid: _zahl(McpDienst._karte(x), 'cmid'), name: _text(McpDienst._karte(x), 'name')),
        ],
        abschnitte: [
          for (final x in (a['abschnitte'] as List?) ?? const [])
            (id: _zahl(McpDienst._karte(x), 'id'), name: _text(McpDienst._karte(x), 'name')),
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
    }

    // Ein Ziel: eigener Vorgang, Stand aus dem Vorgang. Ohne Vorgangsnummer hat die
    // App abgelehnt (wiederherstellen legt den Vorgang erst nach der Freigabe an).
    Future<ZielErgebnis> lauf(PlanZiel z) async {
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
      return ZielErgebnis(
        zielStandAus(v?.wiederherstellung),
        vorgang: id,
        text: text,
      );
    }

    final berichte = await uebertragungAusfuehren(
      geprueft,
      datei: datei,
      profil: profil.kennung,
      quellkurs: quellkurs,
      protokoll: protokoll,
      lauf: lauf,
    );
    final kopf = sicherungNummer == null
        ? ''
        : 'Quelle gesichert: Nummer $sicherungNummer, Datei $datei.\n';
    return '$kopf${uebertragungsBericht(berichte)}';
  }

}
