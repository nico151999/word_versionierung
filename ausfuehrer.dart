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
    await runGit(['add', '-A'], processWorkingDir: git.path);
    await runGit(['commit', '-m', titel], processWorkingDir: git.path);
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
      await runGit(['checkout', commits.keys.toList()[auswahl - 1]],
          processWorkingDir: git.path);
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
      await runGit(['checkout', commits.keys.toList().last],
          processWorkingDir: git.path);
    }
  }
}