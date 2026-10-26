import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DBHelper {
  static const String dbFileName = 'bulletins_scolaires.db';
  static const int dbVersion = 7;

  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  /// Chemin complet du fichier de base de données (dossier Documents de l'utilisateur).
  static Future<String> get databasePath async {
    final directory = await getApplicationDocumentsDirectory();
    return join(directory.path, dbFileName);
  }

  /// Ferme la base (nécessaire avant de remplacer le fichier lors d'une restauration).
  static Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  static Future<Database> _initDB() async {
    // Initialize FFI for Windows / Desktop platforms
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await databasePath;

    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 1. Etablissement Table
    await db.execute('''
      CREATE TABLE etablissement (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        adresse TEXT,
        telephone TEXT,
        logo_path TEXT,
        annee_scolaire TEXT NOT NULL
      )
    ''');

    // 2. Annees Scolaires Table
    await db.execute('''
      CREATE TABLE annees_scolaires (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        libelle TEXT NOT NULL UNIQUE,
        active INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 3. Classes Table
    await db.execute('''
      CREATE TABLE classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        niveau TEXT NOT NULL,
        annee_scolaire_id INTEGER NOT NULL,
        next_class_id INTEGER,
        mode_calcul TEXT NOT NULL DEFAULT 'secondaire',
        frais_inscription REAL NOT NULL DEFAULT 0,
        frais_scolarite REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (annee_scolaire_id) REFERENCES annees_scolaires (id) ON DELETE CASCADE,
        FOREIGN KEY (next_class_id) REFERENCES classes (id) ON DELETE SET NULL
      )
    ''');

    // 4. Cours Table
    await db.execute('''
      CREATE TABLE cours (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        coefficient INTEGER NOT NULL,
        classe_id INTEGER NOT NULL,
        FOREIGN KEY (classe_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // 5. Eleves Table
    await db.execute('''
      CREATE TABLE eleves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        prenom TEXT NOT NULL,
        classe_id INTEGER NOT NULL,
        matricule TEXT,
        date_naissance TEXT,
        photo_path TEXT,
        telephone_parent TEXT,
        remise_scolarite REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (classe_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // 6. Notes Table
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        eleve_id INTEGER NOT NULL,
        cours_id INTEGER NOT NULL,
        trimestre INTEGER NOT NULL,
        note_classe REAL,
        note_composition REAL,
        FOREIGN KEY (eleve_id) REFERENCES eleves (id) ON DELETE CASCADE,
        FOREIGN KEY (cours_id) REFERENCES cours (id) ON DELETE CASCADE,
        UNIQUE(eleve_id, cours_id, trimestre)
      )
    ''');

    // 7. Paiements (comptabilité)
    await _createPaiementsTable(db);

    // Index de performance (créés aussi lors d'une nouvelle installation)
    await _createIndexes(db);
  }

  static Future<void> _createPaiementsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS paiements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        eleve_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        montant REAL NOT NULL,
        date_paiement TEXT NOT NULL,
        mode TEXT,
        numero_recu TEXT,
        observation TEXT,
        created_at TEXT,
        FOREIGN KEY (eleve_id) REFERENCES eleves (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_paiements_eleve ON paiements(eleve_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_paiements_date ON paiements(date_paiement)');
  }

  static Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_eleve_trimestre ON notes(eleve_id, trimestre)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_eleves_classe ON eleves(classe_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cours_classe ON cours(classe_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_classes_annee ON classes(annee_scolaire_id)');
  }

  /// Mise à jour de la structure de la base.
  /// Chaque étape vérifie ce qui existe déjà : la base reste utilisable même si une ancienne version
  /// du logiciel l'a ouverte entre-temps (ce qui fait reculer son numéro de version).
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS annees_scolaires (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          libelle TEXT NOT NULL UNIQUE,
          active INTEGER NOT NULL DEFAULT 0
        )
      ''');

      if (!await _columnExists(db, 'classes', 'annee_scolaire_id')) {
        await db.execute(
            'ALTER TABLE classes ADD COLUMN annee_scolaire_id INTEGER REFERENCES annees_scolaires(id) ON DELETE CASCADE');
      }

      // Année par défaut, seulement si aucune année n'existe encore
      final annees = await db.query('annees_scolaires', limit: 1);
      if (annees.isEmpty) {
        final List<Map<String, dynamic>> etabs = await db.query('etablissement', limit: 1);
        String defaultAnnee = "${DateTime.now().year}-${DateTime.now().year + 1}";
        if (etabs.isNotEmpty && etabs.first['annee_scolaire'] != null) {
          defaultAnnee = etabs.first['annee_scolaire'] as String;
        }
        final int defaultYearId = await db.insert('annees_scolaires', {
          'libelle': defaultAnnee,
          'active': 1,
        });
        await db.update('classes', {'annee_scolaire_id': defaultYearId}, where: 'annee_scolaire_id IS NULL');
      }
    }

    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'classes', 'next_class_id', 'INTEGER REFERENCES classes(id) ON DELETE SET NULL');
    }

    if (oldVersion < 4) {
      await _addColumnIfMissing(db, 'eleves', 'photo_path', 'TEXT');
    }

    if (oldVersion < 5) {
      // Performance indexes
      await _createIndexes(db);
    }

    if (oldVersion < 6) {
      // Mode de calcul par classe : 'primaire' ou 'secondaire' (par défaut)
      await _addColumnIfMissing(db, 'classes', 'mode_calcul', "TEXT NOT NULL DEFAULT 'secondaire'");
    }

    if (oldVersion < 7) {
      // Comptabilité : frais par classe, remise et contact parent par élève, paiements
      await _addColumnIfMissing(db, 'classes', 'frais_inscription', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'classes', 'frais_scolarite', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'eleves', 'telephone_parent', 'TEXT');
      await _addColumnIfMissing(db, 'eleves', 'remise_scolarite', 'REAL NOT NULL DEFAULT 0');
      await _createPaiementsTable(db);
      await _createIndexes(db);
    }
  }

  static Future<bool> _columnExists(Database db, String table, String column) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.any((c) => (c['name'] as String?)?.toLowerCase() == column.toLowerCase());
  }

  static Future<void> _addColumnIfMissing(Database db, String table, String column, String definition) async {
    if (!await _columnExists(db, table, column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
