// Debug-Testzugänge: Bindung und Umfang, ohne Zugangsdaten zu lesen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'profil.dart';

class Testzugang {
  const Testzugang({
    required this.kennung,
    required this.datei,
    required this.adresse,
    this.kurse = const {},
    this.bilder = false,
  });
  final String kennung;
  final String datei;
  final String adresse;
  final Set<int> kurse;
  final bool bilder;

  bool passt(Profil profil) =>
      kDebugMode &&
      profil.kennung == kennung &&
      adresseSchluessel(adresse) != null &&
      adresseSchluessel(adresse) == adresseSchluessel(profil.adresse);

  static String? adresseSchluessel(String adresse) {
    final uri = Uri.tryParse(adresse.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: '',
        )
        .toString();
  }

  static Testzugang? fuer(Profil profil) {
    final t = ausUmgebung()[profil.kennung];
    return t != null && t.passt(profil) ? t : null;
  }

  static Map<String, Testzugang> ausUmgebung() {
    if (!kDebugMode) return const {};
    final result = <String, Testzugang>{};
    final roh = Platform.environment['MOOCP_TESTZUGANG_PROFILE'];
    if (roh != null && roh.isNotEmpty) {
      final json = jsonDecode(roh);
      if (json is! Map) {
        throw const FormatException(
          'MOOCP_TESTZUGANG_PROFILE muss ein JSON-Objekt sein.',
        );
      }
      for (final entry in json.entries) {
        final w = entry.value;
        if (entry.key is! String ||
            (entry.key as String).isEmpty ||
            w is! Map ||
            w['file'] is! String ||
            (w['file'] as String).trim().isEmpty ||
            w['address'] is! String ||
            adresseSchluessel(w['address'] as String) == null ||
            (w['courses'] != null &&
                (w['courses'] is! List ||
                    (w['courses'] as List).any((k) => k is! int || k <= 1))) ||
            (w['screenshots'] != null && w['screenshots'] is! bool)) {
          throw const FormatException(
            'MOOCP_TESTZUGANG_PROFILE enthält einen ungültigen Eintrag.',
          );
        }
        final k = entry.key as String;
        result[k] = Testzugang(
          kennung: k,
          datei: w['file'] as String,
          adresse: w['address'] as String,
          kurse: Set.unmodifiable(
            (w['courses'] as List? ?? const []).cast<int>(),
          ),
          bilder: w['screenshots'] == true,
        );
      }
    }
    final datei = Platform.environment['MOOCP_TESTZUGANG'];
    final adresse = Platform.environment['MOOCP_TESTZUGANG_ADRESSE'];
    if (datei != null &&
        datei.isNotEmpty &&
        adresse != null &&
        adresse.isNotEmpty) {
      result.putIfAbsent(
        Profil.standardKennung,
        () => Testzugang(
          kennung: Profil.standardKennung,
          datei: datei,
          adresse: adresse,
        ),
      );
    }
    return result;
  }
}
