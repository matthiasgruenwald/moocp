# E23 Kein Moodle-Plugin, kein Web-Service-Token

Seit 0.9.0 (2026-10-02), als eigene ADR nachgetragen. Status: gilt. Ergänzt E1 und E2; die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

moocp spricht Moodle über die Webseiten und Formulare, mit der Sitzung der angemeldeten Lehrkraft, so wie ein Browser. Es setzt nichts voraus, was auf dem Server installiert oder freigeschaltet werden muss: kein Plugin, keine Web-Services, kein Token, kein Eingriff in den Adminbereich (A9).

Gründe:

- Die Zielgruppe sind Lehrkräfte an Schulen, deren Moodle von jemand anderem betrieben wird. Jedes Plugin und jede Web-Service-Freigabe braucht dort eine Administration, die zustimmt, installiert und bei Updates mitzieht. Ohne sie läuft nichts; mit dieser Entscheidung läuft moocp überall, wo man sich anmelden kann.
- Die Rechteprüfung bleibt Moodles eigene: Die App darf genau das, was die angemeldete Lehrkraft darf (E2). Ein Token mit Dienstrechten hätte eigene Rechte, die zu verwalten wären.
- Die Datensperre (A1, E3) lässt sich bei Webseiten und Formularen im Code der App erzwingen, für jede Adresse. Bei einem Web-Service-Dienst läge die Grenze im Dienst auf dem Server.

## Folgen

- Moodles Formulare haben Eigenheiten und ändern sich mit Versionen. Darum liest jeder Schreibvorgang zurück und meldet `verified` (A3), und Felder, Nummern und Möglichkeiten werden zur Laufzeit ermittelt (A9).
- Funktionen, die es nur als Web-Service gibt oder die einen Admin brauchen, fehlen. Sie werden nach A6 gemeldet, nicht umgangen.

## Verworfen

Ein Plugin mit eigenen Web-Services und Token, wie es das Schwesterprojekt Coursepilot nutzt. Es ist der robustere Weg für eine Schule, die ein Plugin installiert: stabile Schnittstellen, kein Formular-Parsing. Es setzt aber Administratorhandeln auf dem Server voraus und bindet moocp an Instanzen, deren Betreiber mitmachen. moocp ist für Lehrkräfte gedacht, die ohne diese Zusage arbeiten wollen. Siehe auch E1 (Verworfen: Web-Service-Token oder eigenes Moodle-Plugin).
