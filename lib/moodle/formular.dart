// Moodle-Bearbeitungsformulare lesen und ausfüllen.
//
// Moodle baut jedes Formular aus Zeilen: links die Beschriftung, rechts ein
// oder mehrere Steuerelemente. Ein Datum etwa sind fünf Auswahllisten (Tag,
// Monat, Jahr, Stunde, Minute) und ein Haken „Aktivieren". Hier wird daraus
// je Zeile ein Schlüssel, die Beschriftung und ein lesbarer Wert
// („2026-09-30 23:59", „aus", „Texteingabe online: nein · Dateiabgabe: ja")
// -- und umgekehrt setzt einstellungenSetzen solche Werte ins Formular.
//
// Editorfelder und Dateibereiche stehen nicht hier; die liest
// aktivitaet_lesen vollständig in eigene Dateien.
//
// Abgeschickt wird wie von einem Browser (formularFelder): Felder in
// Dokumentreihenfolge, Kontrollkästchen nur angehakt, das letzte
// gleichnamige Feld gewinnt (so wertet PHP aus).

import 'package:html/dom.dart' as dom;

import 'moodle_zugang.dart';

// ---------------------------------------------------------------------------
// Felder wie ein Browser
// ---------------------------------------------------------------------------

/// Alle Felder eines Formulars in Dokumentreihenfolge, so wie ein Browser sie
/// senden würde: ohne Knöpfe, ohne deaktivierte Felder, Kontrollkästchen und
/// Optionsfelder nur, wenn angehakt. Die Reihenfolge zählt: Moodle setzt vor
/// jedes Kontrollkästchen ein verstecktes Feld gleichen Namens mit 0, und PHP
/// nimmt den letzten Wert.
Felder formularFelder(dom.Element form) {
  final aus = <MapEntry<String, String>>[];
  void besuche(dom.Element e) {
    final name = e.attributes['name'];
    if (name != null && name.isNotEmpty && !e.attributes.containsKey('disabled')) {
      switch (e.localName) {
        case 'input':
          final typ = (e.attributes['type'] ?? 'text').toLowerCase();
          if (const {'submit', 'button', 'image', 'reset', 'file'}.contains(typ)) break;
          final ankreuzbar = typ == 'checkbox' || typ == 'radio';
          if (ankreuzbar && !e.attributes.containsKey('checked')) break;
          aus.add(MapEntry(name, e.attributes['value'] ?? (ankreuzbar ? 'on' : '')));
        case 'textarea':
          aus.add(MapEntry(name, e.text));
        case 'select':
          final optionen = e.querySelectorAll('option');
          final gewaehlt = optionen.where((o) => o.attributes.containsKey('selected')).toList();
          String wert(dom.Element o) => o.attributes['value'] ?? o.text;
          if (e.attributes.containsKey('multiple')) {
            for (final o in gewaehlt) {
              aus.add(MapEntry(name, wert(o)));
            }
          } else if (optionen.isNotEmpty) {
            aus.add(MapEntry(name, wert(gewaehlt.isNotEmpty ? gewaehlt.last : optionen.first)));
          }
      }
    }
    for (final k in e.children) {
      besuche(k);
    }
  }

  besuche(form);
  return aus;
}

/// Setzt den Wert eines Feldes (das letzte gleichnamige gewinnt, wie in PHP).
void setze(Felder f, String name, String wert) {
  for (var i = f.length - 1; i >= 0; i--) {
    if (f[i].key == name) {
      f[i] = MapEntry(name, wert);
      return;
    }
  }
  f.add(MapEntry(name, wert));
}

// ---------------------------------------------------------------------------
// Zeilen des Formulars
// ---------------------------------------------------------------------------

class Einstellung {
  Einstellung(this.schluessel, this.label, this.wert, {this.verborgen = false, this.optionen, this.auswahlwert});

  /// Name der Zeile im Formular, etwa duedate, submissionplugins, visible.
  final String schluessel;
  final String label;
  final String wert;

  /// Zeile ist im Formular ausgeblendet (d-none), etwa Voraussetzungen als JSON.
  final bool verborgen;
  final List<Map<String, Object>>? optionen;
  final String? auswahlwert;

  Map<String, Object?> toJson() =>
      {'schluessel': schluessel, 'label': label, 'wert': wert, if (verborgen) 'verborgen': true,
        if (optionen != null) 'optionen': optionen, if (auswahlwert != null) 'auswahlwert': auswahlwert};
}

class _Zeile {
  _Zeile(this.schluessel, this.label, this.typ, this.steuer, this.verborgen);
  final String schluessel;
  final String label;
  final String typ;
  final List<dom.Element> steuer;
  final bool verborgen;

  bool get istDatum => typ == 'date_time_selector' || typ == 'date_selector';
}

String _text(dom.Element? e) => (e?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

bool _hat(dom.Element e, String klasse) => e.classes.contains(klasse);

List<_Zeile> _zeilen(dom.Element form) {
  final aus = <_Zeile>[];
  final gesehen = <String>{};
  for (final zeile in form.querySelectorAll('div.fitem')) {
    if (!_hat(zeile, 'row')) continue;
    final element = zeile.children.where((c) => _hat(c, 'felement') || _hat(c, 'checkbox')).firstOrNull;
    if (element == null) continue;
    final typ = element.attributes['data-fieldtype'] ?? (_hat(element, 'checkbox') ? 'checkbox' : '');
    if (const {'editor', 'filemanager', 'submit', 'button', 'static', 'hidden'}.contains(typ)) continue;
    if (element.querySelector('textarea[name\$="[text]"]') != null) continue;

    final steuer = [
      for (final e in element.querySelectorAll('input, select, textarea'))
        if (e.attributes['name'] != null &&
            !const {'hidden', 'submit', 'button', 'image', 'reset', 'file'}
                .contains((e.attributes['type'] ?? '').toLowerCase()))
          e
    ];
    if (steuer.isEmpty) continue;
    // Moodle kann jede Option als eigene fitem-Zeile rendern; der Name bindet die Gruppe.
    if (steuer.every(_istRadio) && steuer.map((s) => s.attributes['name']).toSet().length == 1) {
      final name = steuer.first.attributes['name']!;
      if (!gesehen.add(name)) continue;
      final gruppe = _radios(form, name);
      dom.Element? eltern = zeile.parent;
      while (eltern != null && eltern.localName != 'fieldset') {
        eltern = eltern.parent;
      }
      final label = _text(eltern?.querySelector('legend'));
      aus.add(_Zeile(name, label.isEmpty ? name : label, 'radio', gruppe, _hat(zeile, 'd-none')));
      continue;
    }
    final schluessel = zeile.attributes['data-groupname'] ??
        (zeile.id.isNotEmpty
            ? zeile.id.replaceFirst(RegExp(r'^(fitem_fgroup_id_|fitem_id_|fgroup_id_)'), '')
            : steuer.first.attributes['name']!);
    if (!gesehen.add(schluessel)) continue;
    var label = _text(zeile.children.where((c) => _hat(c, 'col-form-label')).firstOrNull);
    if (label.isEmpty && steuer.length == 1) label = beschriftung(steuer.single, form);
    aus.add(_Zeile(schluessel, label, typ, steuer, _hat(zeile, 'd-none')));
  }
  return aus;
}

/// Beschriftung eines einzelnen Steuerelements: label for=id oder das
/// umschließende label.
String beschriftung(dom.Element e, dom.Element form) {
  final id = e.id;
  if (id.isNotEmpty) {
    final l = form.querySelectorAll('label').where((l) => l.attributes['for'] == id).firstOrNull;
    if (l != null && _text(l).isNotEmpty) return _text(l);
  }
  dom.Element? x = e.parent;
  while (x != null && x.localName != 'label' && !_hat(x, 'felement')) {
    x = x.parent;
  }
  return x?.localName == 'label' ? _text(x) : '';
}

/// Lesbarer Wert eines einzelnen Steuerelements: Text der gewählten Option,
/// „ja"/„nein" bei Kontrollkästchen, sonst der Wert.
String steuerWert(dom.Element e) {
  switch (e.localName) {
    case 'select':
      final gewaehlt = e.querySelectorAll('option').where((o) => o.attributes.containsKey('selected')).toList();
      if (e.attributes.containsKey('multiple')) {
        return gewaehlt.isEmpty ? '–' : gewaehlt.map(_text).join(', ');
      }
      final o = gewaehlt.isNotEmpty ? gewaehlt.last : e.querySelector('option');
      return o == null ? '–' : _text(o);
    case 'textarea':
      final t = e.text.trim();
      return t.isEmpty ? '–' : t;
    default:
      final typ = (e.attributes['type'] ?? 'text').toLowerCase();
      if (typ == 'checkbox' || typ == 'radio') {
        return e.attributes.containsKey('checked') ? 'ja' : 'nein';
      }
      final v = e.attributes['value'] ?? '';
      return v.isEmpty ? '–' : v;
  }
}

dom.Element? _datumsteil(List<dom.Element> steuer, String n) =>
    steuer.where((e) => (e.attributes['name'] ?? '').endsWith('[$n]')).firstOrNull;

String _datum(List<dom.Element> steuer) {
  String? teil(String n) {
    final s = _datumsteil(steuer, n);
    if (s == null) return null;
    if (s.localName == 'input') return s.attributes.containsKey('checked') ? '1' : '0';
    final o = s.querySelectorAll('option').where((o) => o.attributes.containsKey('selected')).firstOrNull ??
        s.querySelector('option');
    return o?.attributes['value'];
  }

  if (teil('enabled') == '0') return 'aus';
  String zwei(String? s) => (s ?? '0').padLeft(2, '0');
  final d = '${teil('year')}-${zwei(teil('month'))}-${zwei(teil('day'))}';
  final h = teil('hour');
  return h == null ? d : '$d ${zwei(h)}:${zwei(teil('minute'))}';
}

String _zeilenwert(_Zeile z, dom.Element form) {
  if (z.istDatum) return _datum(z.steuer);
  if (z.typ == 'radio') {
    final s = z.steuer.where((s) => s.attributes.containsKey('checked')).firstOrNull;
    return s == null ? '–' : _radioLabel(s, form);
  }
  if (z.schluessel == 'availabilityconditionsjson') {
    final j = z.steuer.single.text.trim();
    return j.isEmpty || RegExp(r'"c"\s*:\s*\[\s*\]').hasMatch(j) ? 'keine' : j;
  }
  if (z.steuer.length == 1) return steuerWert(z.steuer.single);
  return [
    for (final s in z.steuer)
      if (beschriftung(s, form).isNotEmpty) '${beschriftung(s, form)}: ${steuerWert(s)}' else steuerWert(s)
  ].join(' · ');
}

/// Die Zeilen eines Formulars (div.row.fitem), ohne Editoren, Dateibereiche,
/// Knöpfe und reine Anzeigen.
List<Einstellung> einstellungenLesen(dom.Element form) => [
      for (final z in _zeilen(form))
        Einstellung(z.schluessel, z.label, _zeilenwert(z, form), verborgen: z.verborgen,
          auswahlwert: z.typ != 'radio' ? null : z.steuer.where((s) => s.attributes.containsKey('checked'))
              .map((s) => s.attributes['value'] ?? 'on').firstOrNull,
          optionen: z.typ != 'radio' ? null : [for (final s in z.steuer) {
            'wert': s.attributes['value'] ?? 'on', 'label': _radioLabel(s, form),
            if (s.attributes.containsKey('disabled')) 'deaktiviert': true,
          }])
    ];

// ---------------------------------------------------------------------------
// Einstellungen setzen
// ---------------------------------------------------------------------------

/// Eine gesetzte Einstellung: was vorher dastand, was jetzt, und woran die
/// Rückleseprobe erkennt, dass es angekommen ist.
class Gesetzt {
  Gesetzt(this.schluessel, this.label, this.vorher, this.nachher, this.erwartet, {this.auswahlwert});
  final String schluessel;
  final String label;
  final String vorher;
  final String nachher;

  /// Teiltexte, die der zurückgelesene Wert enthalten muss.
  final List<String> erwartet;
  final String? auswahlwert;

  /// So steht es in der Freigabe: ein leerer Wert als „(leer)", sonst sähe
  /// die Lehrkraft hinter dem Pfeil nichts und wüsste nicht, ob etwas fehlt.
  @override
  String toString() => '$label: ${_zeige(vorher)} → ${_zeige(nachher)}';

  static String _zeige(String w) => w.trim().isEmpty ? '(leer)' : w;
}

bool _gleich(String a, String b) =>
    a.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase() == b.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

bool _istRadio(dom.Element e) => e.localName == 'input' && (e.attributes['type'] ?? '').toLowerCase() == 'radio';

List<dom.Element> _radios(dom.Element form, String name) =>
    form.querySelectorAll('input').where((e) => _istRadio(e) && e.attributes['name'] == name).toList();

String _radioLabel(dom.Element e, dom.Element form) {
  final label = beschriftung(e, form);
  return label.isEmpty ? e.attributes['value'] ?? 'on' : label;
}

bool? _jaNein(Object? w) {
  if (w is bool) return w;
  final s = '$w'.trim().toLowerCase();
  if (const {'ja', 'true', '1', 'an', 'yes'}.contains(s)) return true;
  if (const {'nein', 'false', '0', 'aus', 'no'}.contains(s)) return false;
  return null;
}

/// Setzt ein einzelnes Steuerelement in [f]; gibt den neuen lesbaren Wert
/// zurück (wie [steuerWert]). Auswahl: Text oder value einer Option;
/// Kontrollkästchen: ja oder nein.
String steuerSetzen(dom.Element form, Felder f, dom.Element e, Object? wert, String wo) {
  final name = e.attributes['name']!;
  switch (e.localName) {
    case 'select':
      if (e.attributes.containsKey('multiple')) {
        throw MoodleFehler('$wo: Mehrfachauswahl wird nicht unterstützt.');
      }
      final optionen = e.querySelectorAll('option');
      final s = '$wert';
      final o = optionen.where((o) => _gleich(_text(o), s)).firstOrNull ??
          optionen.where((o) => o.attributes['value'] == s).firstOrNull;
      if (o == null) {
        final moeglich = optionen.map(_text).take(20).join(' | ');
        throw MoodleFehler('$wo: „$s" ist keine der Möglichkeiten: $moeglich');
      }
      setze(f, name, o.attributes['value'] ?? _text(o));
      return _text(o);
    case 'textarea':
      setze(f, name, '$wert');
      return '$wert';
    default:
      final typ = (e.attributes['type'] ?? 'text').toLowerCase();
      if (typ == 'radio') {
        final optionen = _radios(form, name);
        final treffer = optionen.where((o) => (o.attributes['value'] ?? 'on') == '$wert' ||
            _gleich(_radioLabel(o, form), '$wert')).toList();
        if (treffer.length != 1 || treffer.single.attributes.containsKey('disabled')) {
          throw MoodleFehler('$wo: „$wert“ ist keine eindeutige, aktivierte Auswahl. Möglichkeiten: '
              '${optionen.where((o) => !o.attributes.containsKey('disabled')).map((o) => _radioLabel(o, form)).join(' | ')}');
        }
        f.removeWhere((x) => x.key == name);
        f.add(MapEntry(name, treffer.single.attributes['value'] ?? 'on'));
        return _radioLabel(treffer.single, form);
      }
      if (typ == 'checkbox') {
        final an = _jaNein(wert);
        if (an == null) throw MoodleFehler('$wo: ja oder nein erwartet, nicht „$wert".');
        final verdeckt = form
            .querySelectorAll('input')
            .where((x) => x.attributes['name'] == name && (x.attributes['type'] ?? '') == 'hidden')
            .firstOrNull;
        if (an) {
          setze(f, name, e.attributes['value'] ?? '1');
        } else if (verdeckt != null) {
          setze(f, name, verdeckt.attributes['value'] ?? '0');
        } else {
          f.removeWhere((x) => x.key == name);
        }
        return an ? 'ja' : 'nein';
      }
      setze(f, name, '$wert');
      return '$wert';
  }
}

/// Setzt ein Datum: „aus" oder „JJJJ-MM-TT SS:MM" (ohne Uhrzeit: 00:00).
String _setzeDatum(Felder f, _Zeile z, Object? wert) {
  final s = '$wert'.trim();
  final aktiv = _datumsteil(z.steuer, 'enabled');
  if (s.toLowerCase() == 'aus') {
    if (aktiv == null) throw MoodleFehler('${z.label}: lässt sich nicht abschalten.');
    f.removeWhere((x) => x.key == aktiv.attributes['name']);
    return 'aus';
  }
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?$').firstMatch(s);
  if (m == null) throw MoodleFehler('${z.label}: „$s" ist kein Datum der Form JJJJ-MM-TT SS:MM oder „aus".');
  final teile = {
    'year': int.parse(m.group(1)!),
    'month': int.parse(m.group(2)!),
    'day': int.parse(m.group(3)!),
    'hour': int.parse(m.group(4) ?? '0'),
    'minute': int.parse(m.group(5) ?? '0'),
  };
  for (final t in teile.entries) {
    final sel = _datumsteil(z.steuer, t.key);
    if (sel == null) continue;
    final ok = sel.querySelectorAll('option').any((o) => o.attributes['value'] == '${t.value}');
    if (!ok) throw MoodleFehler('${z.label}: ${t.key} ${t.value} ist nicht wählbar.');
    setze(f, sel.attributes['name']!, '${t.value}');
  }
  if (aktiv != null) setze(f, aktiv.attributes['name']!, aktiv.attributes['value'] ?? '1');
  String zwei(int n) => '$n'.padLeft(2, '0');
  final d = '${teile['year']}-${zwei(teile['month']!)}-${zwei(teile['day']!)}';
  return _datumsteil(z.steuer, 'hour') == null ? d : '$d ${zwei(teile['hour']!)}:${zwei(teile['minute']!)}';
}

/// Setzt Einstellungen nach Schlüssel (wie in einstellungen.json):
///   Zeile mit einem Steuerelement: Wert als Text („Nein", „20", „ja");
///   Datum: „JJJJ-MM-TT SS:MM" oder „aus";
///   Zeile mit mehreren Steuerelementen: {Beschriftung: Wert, …}.
/// Wirft MoodleFehler bei Unbekanntem -- dann wird gar nichts geschrieben.
List<Gesetzt> einstellungenSetzen(dom.Element form, Felder f, Map<String, Object?> aenderungen) {
  final zeilen = {for (final z in _zeilen(form)) z.schluessel: z};
  final aus = <Gesetzt>[];
  for (final a in aenderungen.entries) {
    final z = zeilen[a.key];
    if (z == null) {
      throw MoodleFehler('Einstellung „${a.key}" gibt es in diesem Formular nicht. '
          'Schlüssel stehen in einstellungen.json.');
    }
    final vorher = _zeilenwert(z, form);
    if (z.istDatum) {
      final n = _setzeDatum(f, z, a.value);
      aus.add(Gesetzt(z.schluessel, z.label, vorher, n, [n]));
    } else if (z.steuer.length == 1 || z.typ == 'radio') {
      final n = steuerSetzen(form, f, z.steuer.first, a.value, z.label);
      aus.add(Gesetzt(z.schluessel, z.label, vorher, n, [n],
          auswahlwert: z.typ == 'radio' ? f.lastWhere((e) => e.key == z.schluessel).value : null));
    } else {
      final werte = a.value;
      if (werte is! Map) {
        final moeglich = z.steuer.map((s) => beschriftung(s, form)).where((s) => s.isNotEmpty).join(', ');
        throw MoodleFehler('${z.label}: mehrere Angaben -- als {Beschriftung: Wert} übergeben ($moeglich).');
      }
      final teile = <String>[];
      for (final w in werte.entries) {
        final s = z.steuer.where((s) => _gleich(beschriftung(s, form), '${w.key}')).firstOrNull;
        if (s == null) {
          final moeglich = z.steuer.map((s) => beschriftung(s, form)).where((s) => s.isNotEmpty).join(', ');
          throw MoodleFehler('${z.label}: „${w.key}" gibt es nicht ($moeglich).');
        }
        teile.add('${beschriftung(s, form)}: ${steuerSetzen(form, f, s, w.value, '${z.label}/${w.key}')}');
      }
      aus.add(Gesetzt(z.schluessel, z.label, vorher, teile.join(' · '), teile));
    }
  }
  return aus;
}

/// Welche Einstellungen die Übersicht zeigt; der Rest steht in
/// einstellungen.json.
const Map<String, List<String>> wichtigeEinstellungen = {
  'assign': [
    'allowsubmissionsfromdate',
    'duedate',
    'cutoffdate',
    'gradingduedate',
    'submissionplugins',
    'assignsubmission_file_maxfiles',
    'grade',
    'teamsubmission',
  ],
};

const List<String> immerZeigen = ['visible', 'availabilityconditionsjson'];
