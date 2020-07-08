import 'dart:convert';
import 'dart:io';
import 'ausfuehrer.dart';

void main() {
  ueberpruefeAbhaengigkeit(['git']);
  Map<String, Ausfuehrer> auswahlMoeglichkeiten = {
    'Neue Version erstellen': VersionErsteller(),
    'Alte Version auschecken': VersionAuschecker(),
    'Vom Remote Updates beziehen': SelbstAktualisierer(),
    'Updates zum Remote schieben': RemoteAktualisierer()
  };

  int i = 0;
  print("Treffen Sie eine Auswahl");
  auswahlMoeglichkeiten.keys.forEach((auswahl) => print("${++i}: $auswahl"));
  int auswahl = auswaehler(auswahlMoeglichkeiten.length);
  auswahlMoeglichkeiten.values.toList()[auswahl - 1].ausfuehren();
}

int auswaehler(int auswahlAnzahl) {
  int auswahl;
  try {
    auswahl =
        int.parse(stdin.readLineSync(encoding: Encoding.getByName('utf-8')));
  } on FormatException {
    falscheAuswahl();
    return -1;
  }
  if (auswahl > auswahlAnzahl || auswahl < 1) {
    falscheAuswahl();
    return -1;
  }
  return auswahl;
}

void ueberpruefeAbhaengigkeit(List<String> abhaengigkeiten) {
  for (String abhaengigkeit in abhaengigkeiten) {
    if ((Platform.isWindows &&
            Process.runSync('where', ['/q', abhaengigkeit]).exitCode == 1) ||
        ((Platform.isLinux || Platform.isMacOS) &&
            Process.runSync('command', ['-v', abhaengigkeit]).exitCode == 1)) {
      print("$abhaengigkeit ist nicht im Pfad. Abbruch...");
      exit(1);
    }
  }
}

void falscheAuswahl() {
  print("Ungültige Auswahl");
  exit(1);
}

void keinRepo() {
  print(
      "In diesem Ordner existiert kein Versionsverwaltungsordner. Abbruch...");
  exit(1);
}
