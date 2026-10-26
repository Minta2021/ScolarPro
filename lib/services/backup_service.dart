import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/db_helper.dart';

/// Sauvegarde et restauration complètes : base de données + logo + photos des élèves, dans un seul .zip.
class BackupService {
  BackupService._();

  static const String _dbEntry = 'bulletins_scolaires.db';
  static const String _filesDir = 'fichiers/';
  static const String _manifestEntry = 'scolarpro_sauvegarde.json';

  /// Construit le contenu d'une sauvegarde (.zip).
  static Future<List<int>> creerSauvegarde() async {
    final db = await DBHelper.database;
    final tmpDir = await getTemporaryDirectory();
    final tmpPath = p.join(tmpDir.path, 'scolarpro_${DateTime.now().millisecondsSinceEpoch}.db');

    List<int> dbBytes;
    try {
      // Copie cohérente de la base sans la fermer
      await db.execute("VACUUM INTO '${tmpPath.replaceAll("'", "''")}'");
      dbBytes = await File(tmpPath).readAsBytes();
    } catch (_) {
      // Repli : on ferme la base le temps de copier le fichier
      final dbPath = await DBHelper.databasePath;
      await DBHelper.close();
      dbBytes = await File(dbPath).readAsBytes();
      await DBHelper.database;
    } finally {
      try {
        final f = File(tmpPath);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }

    final archive = Archive();
    archive.addFile(ArchiveFile(_dbEntry, dbBytes.length, dbBytes));

    // Images utilisées par l'application (logo, photos d'élèves)
    final chemins = <String>{};
    for (final r in await db.query('etablissement', columns: ['logo_path'])) {
      final v = r['logo_path'] as String?;
      if (v != null && v.isNotEmpty) chemins.add(v);
    }
    for (final r in await db.query('eleves', columns: ['photo_path'], where: 'photo_path IS NOT NULL')) {
      final v = r['photo_path'] as String?;
      if (v != null && v.isNotEmpty) chemins.add(v);
    }

    final fichiers = <String, String>{}; // chemin d'origine -> nom dans l'archive
    final nomsUtilises = <String>{};
    for (final chemin in chemins) {
      final file = File(chemin);
      if (!file.existsSync()) continue;
      var nom = p.basename(chemin);
      var i = 1;
      while (nomsUtilises.contains(nom)) {
        nom = '${p.basenameWithoutExtension(chemin)}_$i${p.extension(chemin)}';
        i++;
      }
      nomsUtilises.add(nom);
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile('$_filesDir$nom', bytes.length, bytes));
      fichiers[chemin] = '$_filesDir$nom';
    }

    final manifest = utf8.encode(jsonEncode({
      'application': 'ScolarPro',
      'version_base': DBHelper.dbVersion,
      'date': DateTime.now().toIso8601String(),
      'fichiers': fichiers,
    }));
    archive.addFile(ArchiveFile(_manifestEntry, manifest.length, manifest));

    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw Exception("Impossible de créer l'archive de sauvegarde.");
    return zip;
  }

  /// Remplace toutes les données actuelles par celles de la sauvegarde.
  /// Une copie de la base actuelle est conservée dans le dossier de l'application avant le remplacement.
  static Future<void> restaurer(List<int> zipBytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw Exception("Ce fichier n'est pas une archive .zip valide.");
    }
    final dbFile = archive.findFile(_dbEntry);
    if (dbFile == null) {
      throw Exception("Ce fichier n'est pas une sauvegarde ScolarPro (base de données introuvable).");
    }
    final dbBytes = List<int>.from(dbFile.content as List<int>);
    const entete = 'SQLite format 3';
    if (dbBytes.length < 16 || String.fromCharCodes(dbBytes.sublist(0, entete.length)) != entete) {
      throw Exception("La base de données contenue dans la sauvegarde est invalide.");
    }

    Map<String, dynamic> fichiers = {};
    final manifestFile = archive.findFile(_manifestEntry);
    if (manifestFile != null) {
      try {
        final json = jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
        fichiers = (json['fichiers'] as Map<String, dynamic>?) ?? {};
      } catch (_) {}
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final support = await getApplicationSupportDirectory();
    final dossierImages = Directory(p.join(support.path, 'restauration_$ts'));
    await dossierImages.create(recursive: true);

    // Extraction des images
    final nouveauxChemins = <String, String>{};
    for (final entry in fichiers.entries) {
      final f = archive.findFile(entry.value as String);
      if (f == null) continue;
      final dest = p.join(dossierImages.path, p.basename(entry.value as String));
      await File(dest).writeAsBytes(f.content as List<int>, flush: true);
      nouveauxChemins[entry.key] = dest;
    }

    // Copie de sécurité de la base actuelle, puis remplacement
    final dbPath = await DBHelper.databasePath;
    await DBHelper.close();
    final actuelle = File(dbPath);
    if (actuelle.existsSync()) {
      await actuelle.copy(p.join(support.path, 'avant_restauration_$ts.db'));
    }
    for (final suffixe in ['-journal', '-wal', '-shm']) {
      final f = File('$dbPath$suffixe');
      if (f.existsSync()) await f.delete();
    }
    await File(dbPath).writeAsBytes(dbBytes, flush: true);

    // Réouverture (met à jour la structure si la sauvegarde vient d'une version plus ancienne)
    final db = await DBHelper.database;
    for (final entry in nouveauxChemins.entries) {
      await db.update('etablissement', {'logo_path': entry.value}, where: 'logo_path = ?', whereArgs: [entry.key]);
      await db.update('eleves', {'photo_path': entry.value}, where: 'photo_path = ?', whereArgs: [entry.key]);
    }
  }
}
