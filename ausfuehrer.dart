import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:git/git.dart';

import 'Word_Versionierung.dart';

abstract class Ausfuehrer {
  String _versionierungsOrdner = 'Versionierung';

  void ausfuehren();
}

class VersionErsteller extends Ausfuehrer {

  @override
  void ausfuehren() async {
    List<File> wordDateien = new List<File>();
    for (FileSystemEntity entity in Directory('./').listSync()) {
      if (entity.path.endsWith('.docx')) {
        File datei = File(entity.path);
        if (datei.existsSync()) {
          wordDateien.add(datei);
        }
      }
    }
    File dokument;
    switch (wordDateien.length) {
      case 0:
        print('Keine Word Dateien zur Versionierung im aktuellen Ordner vorhanden. Abbruch...');
        exit(1);
        return;
      case 1:
        dokument = wordDateien[0];
        print('${dokument.path} wird als neue Version verwendet.');
        break;
      default:
        print('Wähle die Datei aus, die als nächste Version verwendet werden soll:');
        int i = 0;
        wordDateien.forEach((wordDatei) {
          print("${++i}: ${wordDatei.path}");
        });
        dokument = wordDateien[auswaehler(wordDateien.length) - 1];
    }
    print('Gib der neuen Version einen Namen:');
    String titel = stdin.readLineSync(encoding: Encoding.getByName('utf-8'));
    if (titel.length < 1) {
      return falscheAuswahl();
    }
    GitDir git;
    if (await GitDir.isGitDir(_versionierungsOrdner)) {
      git = await GitDir.fromExisting(_versionierungsOrdner);
    } else {
      Directory ordner = Directory(_versionierungsOrdner);
      if (!ordner.existsSync()) {
        ordner.createSync();
      }
      git = await GitDir.init(_versionierungsOrdner);
    }
    final Uint8List bytes = dokument.readAsBytesSync();
    final Archive archiv = ZipDecoder().decodeBytes(bytes);
    for (final ArchiveFile archivEintrag in archiv) {
      final archivEintragName = archivEintrag.name;
      if (archivEintrag.isFile) {
        final daten = archivEintrag.content as List<int>;
        File datei = File("$_versionierungsOrdner/$archivEintragName");
        if (datei.existsSync()) {
          datei.deleteSync();
        }
        datei
          ..createSync(recursive: true)
          ..writeAsBytesSync(daten);
      } else {
        Directory ordner = Directory("$_versionierungsOrdner/$archivEintragName");
        if (ordner.existsSync()) {
          ordner.deleteSync();
        }
        ordner.createSync(recursive: true);
      }
    }
    if (await git.isWorkingTreeClean()) {
      print('Seit der letzten Version hat sich nichts geändert. Abbruch...');
      return;
    }
    await git.runCommand(['add', '-A']);
    await git.runCommand(['commit', '-m', titel]);
  }
}

class VersionAuschecker extends Ausfuehrer {
  @override
  void ausfuehren() async {
    if (!await GitDir.isGitDir(_versionierungsOrdner)) {
      return keinRepo();
    }
    GitDir git = await GitDir.fromExisting(_versionierungsOrdner);
    Map<String, Commit> commits = await git.commits('master');
    print("Wähle die Version, zu der du eine Word Datei haben möchtest!");
    int i = 0;
    commits.values.forEach((commit) {
      print("${++i} ${commit.message}");
    });
    int auswahl = auswaehler(commits.length);
    bool aktuellerVersionsstand = auswahl == commits.length;
    if (!aktuellerVersionsstand) {
      await git.runCommand(['checkout', commits.keys.toList()[auswahl - 1]]);
    }
    ZipFileEncoder kodierer = ZipFileEncoder();
    kodierer.create("${commits.values.toList()[auswahl - 1].message}.docx");
    Directory repo = Directory(_versionierungsOrdner);
    for (FileSystemEntity entity in repo.listSync()) {
      Directory dir = Directory(entity.path);
      if (await dir.exists()) {
        String gitFolder = '.git';
        if (((Platform.isMacOS || Platform.isLinux) &&
                dir.path.split('/').last != gitFolder) ||
            ((Platform.isWindows) &&
                dir.path.split('\\').last != gitFolder)) {
          kodierer.addDirectory(dir);
        }
      } else {
        kodierer.addFile(File(entity.path));
      }
    }
    kodierer.close();
    if (!aktuellerVersionsstand) {
      await git.runCommand(['checkout', commits.keys.toList().last]);
    }
  }
}

abstract class Aktualisierer extends Ausfuehrer {

  String _remote = 'origin';
  String _alterRemote;

  void aktualisieren(bool aktualisiereRemote) async {
    String branch = 'master';
    GitDir git;
    if (await GitDir.isGitDir(_versionierungsOrdner)) {
      try {
        git = await GitDir.fromExisting(_versionierungsOrdner);
      } on ArgumentError {
        print("Einer der übergeordneten Ordner ist ein git Repository. Abbruch...");
        exit(1);
        return;
      }
      ProcessResult remote = await git.runCommand(['remote', 'get-url', _remote], throwOnError: false);
      if (remote.exitCode == 1) {
        await remoteHinzufuegenMitAbfrage(git);
      } else {
        _alterRemote = remote.stdout;
        await remoteHinzufuegen(git, _alterRemote, setzen: true);
      }
    } else {
      Directory versionierungsOrdner = Directory(_versionierungsOrdner);
      if (!versionierungsOrdner.existsSync()) {
        versionierungsOrdner.createSync();
        try {
          git = await GitDir.init(_versionierungsOrdner);
        } on ArgumentError {
          versionierungsOrdner.deleteSync();
          print("Einer der übergeordneten Ordner ist ein git Repository. Abbruch...");
          exit(1);
          return;
        }
        await remoteHinzufuegenMitAbfrage(git);
      } else {
        return keinRepo();
      }
    }
    await git.runCommand(['fetch']);
    String asynchronitaetsArgument;
    String richtung;
    if (aktualisiereRemote) {
      asynchronitaetsArgument = 'HEAD..$_remote/$branch';
      richtung = 'push';
    } else {
      asynchronitaetsArgument = '$_remote/$branch..HEAD';
      richtung = 'pull';
    }
    String asynchronitaet = (await git.runCommand(
        ['log', asynchronitaetsArgument], throwOnError: false)).stdout;
    if (asynchronitaet.length > 0) {
      print("Das lokale Repository und das Remote-Repository haben eine nicht auflösbare Asynchronität. Abbruch...");
      exit(1);
      return;
    }
    try {
      await git.runCommand([richtung, _remote, branch]);
    } on ProcessException {
      // Remote Repository ist wahrscheinlich leer
    }
    if (_alterRemote != null) {
      await git.runCommand(['remote', 'set-url', _remote, _alterRemote]);
    }
  }

  void remoteHinzufuegen(GitDir git, String url, {bool setzen = false}) async {
    RegExpMatch treffer = new RegExp(
      r"^(https?://)(.+:.+@)?(.+)",
      caseSensitive: true,
      multiLine: false,
    ).firstMatch(url);
    if (treffer == null) {
      print("Die Remote-URL ist invalide");
      exit(1);
      return;
    }
    if (treffer.group(2) == null) {
      print("Gib deinen Git-Nutzernamen ein!");
      String nutzername = stdin.readLineSync(encoding: Encoding.getByName('utf-8'));
      print("Gib dein Git-Passwort ein!");
      String passwort = stdin.readLineSync(encoding: Encoding.getByName('utf-8'));
      if ([nutzername.length, passwort.length].contains(0)) {
        return falscheAuswahl();
      }
      url = '${treffer.group(1)}$nutzername:$passwort@${treffer.group(3)}';
    }
    await git.runCommand(['remote', setzen ? 'set-url' : 'add', _remote, url]);
  }

  void remoteHinzufuegenMitAbfrage(GitDir git) async {
    print("Gib die remote URL zum Host ein, auf den du deine Daten hochladen möchtest!");
    _alterRemote = stdin.readLineSync(encoding: Encoding.getByName('utf-8'));
    if (_alterRemote.length < 1) {
      return falscheAuswahl();
    }
    await remoteHinzufuegen(git, _alterRemote);
  }
}

class SelbstAktualisierer extends Aktualisierer {
  @override
  void ausfuehren() async {
    super.aktualisieren(false);
  }
}

class RemoteAktualisierer extends Aktualisierer {
  @override
  void ausfuehren() async {
    super.aktualisieren(true);
  }
}