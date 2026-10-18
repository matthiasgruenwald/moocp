import 'dart:io';

import 'macos.dart';
import 'windows.dart';

/// Eine Browserart, mit der die Bildschirmfotos laufen. Die Reihenfolge der
/// Aufzählung ist die Suchreihenfolge.
enum BrowserArt {
  edge('Microsoft Edge'),
  chrome('Google Chrome'),
  chromium('Chromium');

  const BrowserArt(this.anzeige);

  /// Der Name, wie ihn die Lehrkraft in Meldungen liest.
  final String anzeige;
}

/// Was die Bildschirmfotos vom Betriebssystem brauchen. Die Umsetzungen
/// stehen in [windows.dart] und [macos.dart]; der Kern kennt nur diese
/// Schnittstelle (E29).
abstract interface class PlattformBrowser {
  /// Die Browserarten, die es auf diesem System gibt, in Suchreihenfolge.
  List<BrowserArt> get arten;

  /// Pfad des Programms der Art, oder null, wenn sie hier fehlt.
  Future<String?> programm(BrowserArt art);

  /// Ob die Verwaltung des Rechners die Fernsteuerung der Art abgeschaltet
  /// hat (RemoteDebuggingAllowed = 0). Fehlt die Richtlinie, ist sie erlaubt.
  Future<bool> fernsteuerungVerboten(BrowserArt art);

  /// Beendet hart alle Prozesse von [programm], die mit [profil] laufen, und
  /// liefert ihre Zahl (-1, wenn sie sich nicht ermitteln ließ). Andere
  /// Browserprozesse bleiben unberührt.
  Future<int> prozesseBeenden(Directory profil, String programm);
}

/// Die einzige Stelle, die nach dem Betriebssystem fragt.
final PlattformBrowser plattformBrowser = Platform.isMacOS ? MacBrowser() : WindowsBrowser();
