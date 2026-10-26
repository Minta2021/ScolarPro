import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/etablissement.dart';
import '../models/classe.dart';
import '../models/cours.dart';
import '../models/eleve.dart';
import '../models/note.dart';
import '../models/annee_scolaire.dart';
import '../services/text_utils.dart';

/// Un élève prêt à être importé (assistant d'import Excel).
class EleveAImporter {
  final String nom;
  final String prenom;
  final String? matricule;
  final String? dateNaissance;
  final String? telephoneParent;

  /// Classe existante de destination...
  final int? classeId;

  /// ...ou nom d'une classe à créer automatiquement.
  final String? nouvelleClasse;

  const EleveAImporter({
    required this.nom,
    required this.prenom,
    this.matricule,
    this.dateNaissance,
    this.telephoneParent,
    this.classeId,
    this.nouvelleClasse,
  });
}

class ImportResultat {
  final int importes;
  final List<String> classesCreees;
  const ImportResultat(this.importes, this.classesCreees);
}

/// Bilan d'un passage de classe.
class PromotionResultat {
  int classesCreees = 0;
  int classesReutilisees = 0;
  int admis = 0;
  int redoublants = 0;
  int sortants = 0;
  int exclus = 0;
  int dejaPresents = 0;
}

class AppStateProvider extends ChangeNotifier {
  Etablissement? _etablissement;
  List<Classe> _classes = [];
  List<AnneeScolaire> _anneesScolaires = [];
  AnneeScolaire? _activeAnneeScolaire;
  AnneeScolaire? _selectedAnneeScolaire;
  
  // Cache for loaded details to avoid redundant database calls
  final Map<int, List<Cours>> _classCourses = {};
  final Map<int, List<Eleve>> _classEleves = {};
  
  // Cache for average calculations to avoid redundant DB queries
  final Map<String, double?> _moyenneCache = {};

  /// Vide le cache des moyennes : à appeler après toute modification qui peut changer
  /// une moyenne ou un rang (notes, matières, coefficients, mode de calcul, élèves...).
  void _invalidateMoyennes() => _moyenneCache.clear();

  Etablissement? get etablissement => _etablissement;
  List<Classe> get classes => _classes;
  List<AnneeScolaire> get anneesScolaires => _anneesScolaires;
  AnneeScolaire? get activeAnneeScolaire => _activeAnneeScolaire;
  AnneeScolaire? get selectedAnneeScolaire => _selectedAnneeScolaire;
  
  bool get isCurrentYearActive => true; // Always allow editing across all years
  bool get isSelectedYearActive => _selectedAnneeScolaire != null && _selectedAnneeScolaire!.active;

  // Load initial data from DB
  Future<void> init() async {
    await loadEtablissement();
    await loadAnneesScolaires();
    await loadClasses();
  }

  /// Recharge toutes les données (après une restauration de sauvegarde).
  Future<void> reloadAll() async {
    _classCourses.clear();
    _classEleves.clear();
    _invalidateMoyennes();
    _selectedAnneeScolaire = null;
    await init();
  }

  // ==========================================
  // MENTION UTILITY
  // ==========================================
  static String getMention(double moyenne, {int bareme = 20}) {
    moyenne = moyenne * 20 / bareme; // ramené sur 20 pour appliquer les seuils
    if (moyenne < 10.0) return "Insuffisant";
    if (moyenne < 12.0) return "Passable";
    if (moyenne < 14.0) return "Assez Bien";
    if (moyenne < 16.0) return "Bien";
    if (moyenne < 18.0) return "Très Bien";
    return "Excellent";
  }

  // ==========================================
  // ANNEE SCOLAIRE METHODS
  // ==========================================
  Future<void> loadAnneesScolaires() async {
    final db = await DBHelper.database;
    
    // Ensure table has at least one default year
    List<Map<String, dynamic>> maps = await db.query('annees_scolaires', orderBy: 'libelle DESC');
    if (maps.isEmpty) {
      String defaultAnnee = _etablissement?.anneeScolaire ?? "${DateTime.now().year}-${DateTime.now().year + 1}";
      await db.insert('annees_scolaires', {
        'libelle': defaultAnnee,
        'active': 1,
      });
      maps = await db.query('annees_scolaires', orderBy: 'libelle DESC');
    }

    _anneesScolaires = maps.map((m) => AnneeScolaire.fromMap(m)).toList();
    
    // Find active one
    _activeAnneeScolaire = _anneesScolaires.firstWhere(
      (y) => y.active,
      orElse: () => _anneesScolaires.first,
    );

    // Default selected year for viewing to active if not set or invalid
    if (_selectedAnneeScolaire == null || !_anneesScolaires.any((y) => y.id == _selectedAnneeScolaire!.id)) {
      _selectedAnneeScolaire = _activeAnneeScolaire;
    } else {
      // Refresh current instance
      _selectedAnneeScolaire = _anneesScolaires.firstWhere((y) => y.id == _selectedAnneeScolaire!.id);
    }
    
    notifyListeners();
  }

  Future<void> selectAnneeScolaire(AnneeScolaire year) async {
    _selectedAnneeScolaire = year;
    notifyListeners();
    await loadClasses();
  }

  Future<void> addAnneeScolaire(String libelle, {bool makeActive = false}) async {
    final db = await DBHelper.database;
    
    if (makeActive) {
      await db.update('annees_scolaires', {'active': 0});
    }

    await db.insert('annees_scolaires', {
      'libelle': libelle.trim(),
      'active': makeActive ? 1 : 0,
    });

    await loadAnneesScolaires();
    if (makeActive) {
      _selectedAnneeScolaire = _activeAnneeScolaire;
      await loadClasses();
    }
  }

  Future<void> setActiveAnneeScolaire(int yearId) async {
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      await txn.update('annees_scolaires', {'active': 0});
      await txn.update(
        'annees_scolaires',
        {'active': 1},
        where: 'id = ?',
        whereArgs: [yearId],
      );
    });

    await loadAnneesScolaires();
    
    // Also update main etablissement active year string if matches
    if (_etablissement != null && _activeAnneeScolaire != null) {
      await db.update(
        'etablissement',
        {'annee_scolaire': _activeAnneeScolaire!.libelle},
        where: 'id = ?',
        whereArgs: [_etablissement!.id],
      );
      _etablissement = Etablissement(
        id: _etablissement!.id,
        nom: _etablissement!.nom,
        adresse: _etablissement!.adresse,
        telephone: _etablissement!.telephone,
        logoPath: _etablissement!.logoPath,
        anneeScolaire: _activeAnneeScolaire!.libelle,
      );
    }

    _selectedAnneeScolaire = _activeAnneeScolaire;
    await loadClasses();
    notifyListeners();
  }

  Future<void> deleteAnneeScolaire(int yearId) async {
    final db = await DBHelper.database;
    final yearToDelete = _anneesScolaires.firstWhere((y) => y.id == yearId);
    
    if (yearToDelete.active) {
      throw Exception("Impossible de supprimer l'année scolaire active.");
    }

    await db.delete(
      'annees_scolaires',
      where: 'id = ?',
      whereArgs: [yearId],
    );

    _invalidateMoyennes();
    await loadAnneesScolaires();
    await loadClasses();
  }

  // ==========================================
  // ETABLISSEMENT METHODS
  // ==========================================
  Future<void> loadEtablissement() async {
    final db = await DBHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('etablissement', limit: 1);
    if (maps.isNotEmpty) {
      _etablissement = Etablissement.fromMap(maps.first);
    } else {
      _etablissement = null;
    }
    notifyListeners();
  }

  Future<void> saveEtablissement(Etablissement etab) async {
    final db = await DBHelper.database;
    if (_etablissement == null) {
      final id = await db.insert('etablissement', etab.toMap());
      _etablissement = Etablissement(
        id: id,
        nom: etab.nom,
        adresse: etab.adresse,
        telephone: etab.telephone,
        logoPath: etab.logoPath,
        anneeScolaire: etab.anneeScolaire,
      );
    } else {
      await db.update(
        'etablissement',
        etab.toMap(),
        where: 'id = ?',
        whereArgs: [_etablissement!.id],
      );
      _etablissement = etab;
    }
    
    // Sync current active year if the user edited it inside etablissement
    final dbActiveYears = await db.query('annees_scolaires', where: 'libelle = ?', whereArgs: [etab.anneeScolaire]);
    if (dbActiveYears.isEmpty) {
      // Create new year
      await addAnneeScolaire(etab.anneeScolaire, makeActive: true);
    } else {
      final activeYearId = dbActiveYears.first['id'] as int;
      final isActive = dbActiveYears.first['active'] as int == 1;
      if (!isActive) {
        await setActiveAnneeScolaire(activeYearId);
      }
    }
    
    notifyListeners();
  }

  // ==========================================
  // CLASSE METHODS
  // ==========================================
  Future<void> loadClasses() async {
    if (_selectedAnneeScolaire == null) {
      _classes = [];
      notifyListeners();
      return;
    }
    final db = await DBHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, 
        (SELECT COUNT(*) FROM eleves e WHERE e.classe_id = c.id) as eleves_count,
        (SELECT COUNT(*) FROM cours co WHERE co.classe_id = c.id) as cours_count
      FROM classes c
      WHERE c.annee_scolaire_id = ?
      ORDER BY c.nom ASC
    ''', [_selectedAnneeScolaire!.id]);
    _classes = maps.map((m) => Classe.fromMap(m)).toList();
    notifyListeners();
  }

  Classe? getClasse(int classId) {
    for (final c in _classes) {
      if (c.id == classId) return c;
    }
    return null;
  }

  bool isClassePrimaire(int classId) => getClasse(classId)?.isPrimaire ?? false;

  int getBareme(int classId) => getClasse(classId)?.bareme ?? 20;

  List<Cours> getCourses(int classId) {
    return _classCourses[classId] ?? [];
  }

  List<Eleve> getEleves(int classId) {
    return _classEleves[classId] ?? [];
  }

  Future<void> loadClassDetails(int classId, {int? trimestre}) async {
    final db = await DBHelper.database;
    
    // Load courses
    final List<Map<String, dynamic>> courseMaps = await db.query(
      'cours',
      where: 'classe_id = ?',
      whereArgs: [classId],
      orderBy: 'nom ASC',
    );
    _classCourses[classId] = courseMaps.map((m) => Cours.fromMap(m)).toList();

    // Load eleves with optional note count for a specific trimestre
    List<Map<String, dynamic>> eleveMaps;
    if (trimestre != null) {
      eleveMaps = await db.rawQuery('''
        SELECT e.*,
          (SELECT COUNT(*) FROM notes n 
           WHERE n.eleve_id = e.id 
             AND n.trimestre = ? 
             AND (n.note_classe IS NOT NULL OR ? = 1)
             AND n.note_composition IS NOT NULL) as notes_count
        FROM eleves e
        WHERE e.classe_id = ?
        ORDER BY e.nom ASC, e.prenom ASC
      ''', [trimestre, isClassePrimaire(classId) ? 1 : 0, classId]);
    } else {
      eleveMaps = await db.query(
        'eleves',
        where: 'classe_id = ?',
        whereArgs: [classId],
        orderBy: 'nom ASC, prenom ASC',
      );
    }
    _classEleves[classId] = eleveMaps.map((m) => Eleve.fromMap(m)).toList();

    notifyListeners();
  }

  Future<void> saveClasse(Classe classe, List<Cours> coursList) async {
    final db = await DBHelper.database;
    
    await db.transaction((txn) async {
      int classId;
      if (classe.id == null) {
        // Insert new class
        final rawMap = classe.toMap();
        rawMap['annee_scolaire_id'] = _selectedAnneeScolaire?.id;
        classId = await txn.insert('classes', rawMap);
      } else {
        // Update existing class
        classId = classe.id!;
        await txn.update(
          'classes',
          classe.toMap(),
          where: 'id = ?',
          whereArgs: [classId],
        );
      }

      // Sync courses:
      // Get current courses in database
      final List<Map<String, dynamic>> existingCourseMaps = await txn.query(
        'cours',
        where: 'classe_id = ?',
        whereArgs: [classId],
      );
      final existingCourses = existingCourseMaps.map((m) => Cours.fromMap(m)).toList();

      // Determine which to insert, update, or delete
      final List<int> keptIds = [];
      for (var cours in coursList) {
        final Map<String, dynamic> cMap = {
          'nom': cours.nom,
          'coefficient': cours.coefficient,
          'classe_id': classId,
        };
        
        if (cours.id == null) {
          // New course
          await txn.insert('cours', cMap);
        } else {
          // Existing course - update
          keptIds.add(cours.id!);
          await txn.update(
            'cours',
            cMap,
            where: 'id = ?',
            whereArgs: [cours.id],
          );
        }
      }

      // Delete courses that are no longer kept (Cascade will delete their notes automatically)
      for (var existing in existingCourses) {
        if (!keptIds.contains(existing.id)) {
          await txn.delete(
            'cours',
            where: 'id = ?',
            whereArgs: [existing.id],
          );
        }
      }
    });

    // Coefficients, matières ou mode de calcul ont pu changer : les moyennes doivent être recalculées
    _invalidateMoyennes();
    await loadClasses();
    if (classe.id != null) {
      await loadClassDetails(classe.id!);
    }
  }

  Future<void> deleteClasse(int classId) async {
    final db = await DBHelper.database;
    await db.delete(
      'classes',
      where: 'id = ?',
      whereArgs: [classId],
    );
    _classCourses.remove(classId);
    _classEleves.remove(classId);
    _invalidateMoyennes();
    await loadClasses();
  }

  // ==========================================
  // ELEVE METHODS
  // ==========================================
  Future<void> addEleve(Eleve eleve) async {
    final db = await DBHelper.database;
    await db.insert('eleves', eleve.toMap());
    _invalidateMoyennes();
    await loadClasses(); // Refresh class eleves counts in provider
    await loadClassDetails(eleve.classeId);
  }

  /// Inserts several students at once (Excel import) in a single transaction
  Future<void> addEleves(int classId, List<Eleve> eleves) async {
    if (eleves.isEmpty) return;
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final eleve in eleves) {
        batch.insert('eleves', eleve.toMap());
      }
      await batch.commit(noResult: true);
    });
    _invalidateMoyennes();
    await loadClasses(); // Refresh class eleves counts in provider
    await loadClassDetails(classId);
  }

  /// Import groupé depuis l'assistant Excel : crée les classes manquantes puis insère les élèves,
  /// le tout dans une seule transaction (rien n'est importé en cas d'erreur).
  Future<ImportResultat> importerEleves(List<EleveAImporter> eleves) async {
    if (eleves.isEmpty) return const ImportResultat(0, []);
    final annee = _selectedAnneeScolaire;
    if (annee == null) throw Exception("Aucune année scolaire sélectionnée.");
    final db = await DBHelper.database;
    final classesCreees = <String>[];
    var importes = 0;

    await db.transaction((txn) async {
      // Classes existantes de l'année, indexées par nom normalisé
      final existantes = await txn.query('classes', where: 'annee_scolaire_id = ?', whereArgs: [annee.id]);
      final Map<String, int> parCle = {
        for (final r in existantes) cleClasse(r['nom'] as String): r['id'] as int,
      };

      final batch = txn.batch();
      for (final e in eleves) {
        int? classeId = e.classeId;
        if (classeId == null && e.nouvelleClasse != null && e.nouvelleClasse!.trim().isNotEmpty) {
          final nom = e.nouvelleClasse!.trim();
          final cle = cleClasse(nom);
          classeId = parCle[cle];
          if (classeId == null) {
            classeId = await txn.insert('classes', {
              'nom': nom,
              'niveau': Classe.niveauPourNom(nom),
              'annee_scolaire_id': annee.id,
              'mode_calcul': Classe.modePourNiveau(nom),
            });
            parCle[cle] = classeId;
            classesCreees.add(nom);
          }
        }
        if (classeId == null) continue;
        batch.insert('eleves', {
          'nom': e.nom,
          'prenom': e.prenom,
          'classe_id': classeId,
          'matricule': e.matricule,
          'date_naissance': e.dateNaissance,
          'telephone_parent': e.telephoneParent,
        });
        importes++;
      }
      await batch.commit(noResult: true);
    });

    _invalidateMoyennes();
    _classEleves.clear();
    await loadClasses();
    return ImportResultat(importes, classesCreees);
  }

  /// Tous les élèves de l'année sélectionnée (toutes classes confondues).
  Future<List<Eleve>> getElevesAnnee() async {
    if (_selectedAnneeScolaire == null) return [];
    final db = await DBHelper.database;
    final rows = await db.rawQuery('''
      SELECT e.* FROM eleves e
      INNER JOIN classes c ON c.id = e.classe_id
      WHERE c.annee_scolaire_id = ?
    ''', [_selectedAnneeScolaire!.id]);
    return rows.map((m) => Eleve.fromMap(m)).toList();
  }

  Future<void> updateEleve(Eleve eleve, {int? currentTrimestre}) async {
    final db = await DBHelper.database;
    await db.update(
      'eleves',
      eleve.toMap(),
      where: 'id = ?',
      whereArgs: [eleve.id],
    );
    await loadClassDetails(eleve.classeId, trimestre: currentTrimestre);
  }

  Future<void> deleteEleve(int eleveId, int classId) async {
    final db = await DBHelper.database;
    await db.delete(
      'eleves',
      where: 'id = ?',
      whereArgs: [eleveId],
    );
    _invalidateMoyennes(); // le rang des autres élèves change
    await loadClasses(); // Refresh class eleves counts in provider
    await loadClassDetails(classId);
  }

  // ==========================================
  // NOTE METHODS & CALCULATIONS
  // ==========================================
  Future<List<Note>> getNotesForEleve(int eleveId, int trimestre) async {
    final db = await DBHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'eleve_id = ? AND trimestre = ?',
      whereArgs: [eleveId, trimestre],
    );
    return maps.map((m) => Note.fromMap(m)).toList();
  }

  Future<void> saveNotes(int eleveId, int classId, int trimestre, List<Note> notesList) async {
    final db = await DBHelper.database;
    
    await db.transaction((txn) async {
      for (var note in notesList) {
        final Map<String, dynamic> noteMap = {
          'eleve_id': eleveId,
          'cours_id': note.coursId,
          'trimestre': trimestre,
          'note_classe': note.noteClasse,
          'note_composition': note.noteComposition,
        };

        // Check if note already exists
        final List<Map<String, dynamic>> existing = await txn.query(
          'notes',
          where: 'eleve_id = ? AND cours_id = ? AND trimestre = ?',
          whereArgs: [eleveId, note.coursId, trimestre],
        );

        if (existing.isNotEmpty) {
          await txn.update(
            'notes',
            noteMap,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        } else {
          await txn.insert('notes', noteMap);
        }
      }
    });

    // Invalidate moyenne cache for this student/class
    _moyenneCache.removeWhere((key, _) => key.startsWith('${eleveId}_${classId}_'));

    await loadClassDetails(classId);
  }

  /// Calculates the general average of a student for a specific trimestre
  Future<double?> calculateMoyenneGenerale(int eleveId, int classId, int trimestre) async {
    // Check cache first
    final cacheKey = '${eleveId}_${classId}_$trimestre';
    if (_moyenneCache.containsKey(cacheKey)) {
      return _moyenneCache[cacheKey];
    }

    final db = await DBHelper.database;

    // Get courses for the class
    final List<Map<String, dynamic>> courseMaps = await db.query(
      'cours',
      where: 'classe_id = ?',
      whereArgs: [classId],
    );
    final courses = courseMaps.map((m) => Cours.fromMap(m)).toList();
    if (courses.isEmpty) {
      _moyenneCache[cacheKey] = null;
      return null;
    }

    // Get notes for the student in this trimestre
    final List<Map<String, dynamic>> noteMaps = await db.query(
      'notes',
      where: 'eleve_id = ? AND trimestre = ?',
      whereArgs: [eleveId, trimestre],
    );
    final notes = noteMaps.map((m) => Note.fromMap(m)).toList();

    // Primaire : somme des notes de composition / nombre de matières, sans coefficient.
    // Secondaire : Σ(moyenne du cours × coefficient) / Σ(coefficients).
    final primaire = isClassePrimaire(classId);

    double totalWeightedPoints = 0;
    int totalCoefficients = 0;
    int notesCount = 0;

    for (var cours in courses) {
      // Find note for this course
      final noteOpt = notes.where((n) => n.coursId == cours.id).toList();
      if (noteOpt.isNotEmpty) {
        final note = noteOpt.first;
        final moyenneCours = note.moyenneCoursPour(primaire);
        if (moyenneCours != null) {
          final poids = primaire ? 1 : cours.coefficient;
          totalWeightedPoints += moyenneCours * poids;
          totalCoefficients += poids;
          notesCount++;
        }
      }
    }

    // If no notes are available, or coefficients sum to 0, return null
    if (notesCount == 0 || totalCoefficients == 0) {
      _moyenneCache[cacheKey] = null;
      return null;
    }

    final result = totalWeightedPoints / totalCoefficients;
    _moyenneCache[cacheKey] = result;
    return result;
  }

  /// Calculates rankings for all students in a class for a specific trimestre
  /// Returns a map of: eleveId -> Rank String (e.g. "1er", "2e ex", "3e")
  Future<Map<int, String>> calculateRanks(int classId, int trimestre) async {
    final db = await DBHelper.database;

    // Get all students in the class
    final List<Map<String, dynamic>> eleveMaps = await db.query(
      'eleves',
      where: 'classe_id = ?',
      whereArgs: [classId],
    );
    final eleves = eleveMaps.map((m) => Eleve.fromMap(m)).toList();
    if (eleves.isEmpty) return {};

    // Calculate general average for each student
    final List<MapEntry<Eleve, double>> studentAverages = [];
    for (var eleve in eleves) {
      final avg = await calculateMoyenneGenerale(eleve.id!, classId, trimestre);
      if (avg != null) {
        studentAverages.add(MapEntry(eleve, avg));
      }
    }

    if (studentAverages.isEmpty) return {};

    // Sort averages descending
    studentAverages.sort((a, b) => b.value.compareTo(a.value));

    final Map<int, String> ranks = {};
    
    // Assign ranks, handling ties (ex aequo)
    int currentRank = 1;
    for (int i = 0; i < studentAverages.length; i++) {
      final currentAvg = studentAverages[i].value;
      
      // Look around to see if there are other students with the same average
      final sameAvgCount = studentAverages.where((e) => (e.value - currentAvg).abs() < 0.0001).length;
      
      String rankStr;
      if (sameAvgCount > 1) {
        rankStr = currentRank == 1 ? '1er ex' : '${currentRank}e ex';
      } else {
        rankStr = currentRank == 1 ? '1er' : '${currentRank}e';
      }

      ranks[studentAverages[i].key.id!] = rankStr;

      // Update currentRank:
      // If we have ties, the next rank should skip.
      // E.g., if index 0 and 1 have the same average, they are "1er ex"
      // and index 2 will be rank 3.
      if (i + 1 < studentAverages.length && (studentAverages[i + 1].value - currentAvg).abs() >= 0.0001) {
        currentRank = i + 2;
      }
    }

    return ranks;
  }

  Future<double?> calculateMoyenneAnnuelle(int eleveId, int classId) async {
    final t1 = await calculateMoyenneGenerale(eleveId, classId, 1);
    final t2 = await calculateMoyenneGenerale(eleveId, classId, 2);
    final t3 = await calculateMoyenneGenerale(eleveId, classId, 3);

    double sum = 0;
    int count = 0;
    if (t1 != null) {
      sum += t1;
      count++;
    }
    if (t2 != null) {
      sum += t2;
      count++;
    }
    if (t3 != null) {
      sum += t3;
      count++;
    }

    if (count == 0) return null;
    return sum / count;
  }

  /// Classe qui accueille les élèves admis d'une classe donnée (null = élèves sortants / fin de cycle).
  bool classeASuivante(int classId) => getClasse(classId)?.nextClassId != null;

  Future<PromotionResultat> executePromotion(String newYearLibelle, Map<int, String> promotionDecisions) async {
    if (_activeAnneeScolaire == null) {
      throw Exception("Aucune année scolaire active à promouvoir.");
    }
    final libelle = newYearLibelle.trim();
    final sourceYearId = _activeAnneeScolaire!.id;
    final resultat = PromotionResultat();
    final db = await DBHelper.database;

    await db.transaction((txn) async {
      // 1. Create or retrieve target school year
      int newYearId;
      final List<Map<String, dynamic>> existingYears = await txn.query(
        'annees_scolaires',
        where: 'libelle = ?',
        whereArgs: [libelle],
      );

      if (existingYears.isNotEmpty) {
        newYearId = existingYears.first['id'] as int;
      } else {
        newYearId = await txn.insert('annees_scolaires', {
          'libelle': libelle,
          'active': 0,
        });
      }
      if (newYearId == sourceYearId) {
        throw Exception("L'année cible doit être différente de l'année en cours.");
      }

      // Deactivate all, and set the new one as active
      await txn.update('annees_scolaires', {'active': 0});
      await txn.update(
        'annees_scolaires',
        {'active': 1},
        where: 'id = ?',
        whereArgs: [newYearId],
      );

      // 2. Fetch all classes of current active year
      final List<Map<String, dynamic>> sourceClasses = await txn.query(
        'classes',
        where: 'annee_scolaire_id = ?',
        whereArgs: [sourceYearId],
      );

      // Classes déjà présentes dans l'année cible (si elle a été préparée à l'avance) :
      // elles sont réutilisées au lieu d'être recréées en double.
      final List<Map<String, dynamic>> targetClasses = await txn.query(
        'classes',
        where: 'annee_scolaire_id = ?',
        whereArgs: [newYearId],
      );
      final Map<String, int> targetByKey = {
        for (final r in targetClasses) cleClasse(r['nom'] as String): r['id'] as int,
      };
      final Set<int> preExistingTargetIds = targetClasses.map((r) => r['id'] as int).toSet();

      final Map<int, int> classMapping = {}; // oldClassId -> newClassId

      for (var row in sourceClasses) {
        final int oldClassId = row['id'] as int;
        final String nom = row['nom'] as String;
        final key = cleClasse(nom);

        int newClassId;
        bool copyCourses;
        if (targetByKey.containsKey(key)) {
          newClassId = targetByKey[key]!;
          resultat.classesReutilisees++;
          // On ne copie les matières que si la classe cible n'en a encore aucune
          final countRows = await txn.rawQuery('SELECT COUNT(*) AS n FROM cours WHERE classe_id = ?', [newClassId]);
          copyCourses = ((countRows.first['n'] as int?) ?? 0) == 0;
          // Reprend les frais si la classe cible n'en a pas encore
          final target = targetClasses.firstWhere((r) => r['id'] == newClassId);
          final fraisCibleInsc = (target['frais_inscription'] as num?)?.toDouble() ?? 0;
          final fraisCibleScol = (target['frais_scolarite'] as num?)?.toDouble() ?? 0;
          if (fraisCibleInsc <= 0 && fraisCibleScol <= 0) {
            await txn.update(
              'classes',
              {
                'frais_inscription': row['frais_inscription'] ?? 0,
                'frais_scolarite': row['frais_scolarite'] ?? 0,
              },
              where: 'id = ?',
              whereArgs: [newClassId],
            );
          }
        } else {
          newClassId = await txn.insert('classes', {
            'nom': nom,
            'niveau': row['niveau'] as String,
            'mode_calcul': row['mode_calcul'] ?? 'secondaire',
            'frais_inscription': row['frais_inscription'] ?? 0,
            'frais_scolarite': row['frais_scolarite'] ?? 0,
            'annee_scolaire_id': newYearId,
            'next_class_id': null,
          });
          targetByKey[key] = newClassId;
          resultat.classesCreees++;
          copyCourses = true;
        }
        classMapping[oldClassId] = newClassId;

        if (copyCourses) {
          final List<Map<String, dynamic>> sourceCourses = await txn.query(
            'cours',
            where: 'classe_id = ?',
            whereArgs: [oldClassId],
          );
          for (var course in sourceCourses) {
            await txn.insert('cours', {
              'nom': course['nom'],
              'coefficient': course['coefficient'],
              'classe_id': newClassId,
            });
          }
        }
      }

      // Update next_class_id on duplicated classes (sans écraser un lien déjà défini dans l'année cible)
      for (var row in sourceClasses) {
        final int oldClassId = row['id'] as int;
        final int? oldNextClassId = row['next_class_id'] as int?;
        final int newClassId = classMapping[oldClassId]!;

        if (oldNextClassId != null && classMapping.containsKey(oldNextClassId)) {
          if (preExistingTargetIds.contains(newClassId)) {
            final current = targetClasses.firstWhere((r) => r['id'] == newClassId)['next_class_id'];
            if (current != null) continue;
          }
          await txn.update(
            'classes',
            {'next_class_id': classMapping[oldNextClassId]!},
            where: 'id = ?',
            whereArgs: [newClassId],
          );
        }
      }

      // Élèves déjà présents dans les classes cibles (évite les doublons si on relance l'opération)
      final Map<int, Set<String>> presents = {};
      final Map<int, Set<String>> matriculesPresents = {};
      if (preExistingTargetIds.isNotEmpty) {
        final List<Map<String, dynamic>> deja = await txn.rawQuery('''
          SELECT e.nom, e.prenom, e.matricule, e.classe_id FROM eleves e
          INNER JOIN classes c ON e.classe_id = c.id
          WHERE c.annee_scolaire_id = ?
        ''', [newYearId]);
        for (final r in deja) {
          final cid = r['classe_id'] as int;
          presents.putIfAbsent(cid, () => {}).add(cleEleve(r['nom'] as String, r['prenom'] as String));
          final mat = (r['matricule'] as String?)?.trim().toLowerCase();
          if (mat != null && mat.isNotEmpty) matriculesPresents.putIfAbsent(cid, () => {}).add(mat);
        }
      }

      // 3. Promote / Redouble students
      final List<Map<String, dynamic>> sourceEleves = await txn.rawQuery('''
        SELECT e.* FROM eleves e
        INNER JOIN classes c ON e.classe_id = c.id
        WHERE c.annee_scolaire_id = ?
      ''', [sourceYearId]);

      final Map<int, int?> nextOfOldClass = {
        for (final r in sourceClasses) r['id'] as int: r['next_class_id'] as int?,
      };

      for (var row in sourceEleves) {
        final int eleveId = row['id'] as int;
        final String nom = row['nom'] as String;
        final String prenom = row['prenom'] as String;
        final String? matricule = row['matricule'] as String?;
        final int oldClassId = row['classe_id'] as int;

        final String decision = promotionDecisions[eleveId] ?? "Redouble";

        int? targetNewClassId;
        if (decision == "Admis") {
          final int? oldNextClassId = nextOfOldClass[oldClassId];
          if (oldNextClassId != null && classMapping.containsKey(oldNextClassId)) {
            targetNewClassId = classMapping[oldNextClassId];
          } else {
            // Classe de fin de cycle : l'élève quitte l'établissement (diplômé / sortant)
            resultat.sortants++;
            continue;
          }
        } else if (decision == "Redouble") {
          targetNewClassId = classMapping[oldClassId];
        } else {
          resultat.exclus++;
          continue;
        }
        if (targetNewClassId == null) continue;

        final cle = cleEleve(nom, prenom);
        final mat = matricule?.trim().toLowerCase();
        final dejaLa = (presents[targetNewClassId]?.contains(cle) ?? false) ||
            (mat != null && mat.isNotEmpty && (matriculesPresents[targetNewClassId]?.contains(mat) ?? false));
        if (dejaLa) {
          resultat.dejaPresents++;
          continue;
        }

        await txn.insert('eleves', {
          'nom': nom,
          'prenom': prenom,
          'matricule': matricule,
          'date_naissance': row['date_naissance'],
          'photo_path': row['photo_path'],
          'telephone_parent': row['telephone_parent'],
          'remise_scolarite': row['remise_scolarite'] ?? 0,
          'classe_id': targetNewClassId,
        });
        presents.putIfAbsent(targetNewClassId, () => {}).add(cle);
        if (decision == "Admis") {
          resultat.admis++;
        } else {
          resultat.redoublants++;
        }
      }

      // 4. Update etablissement active year string
      if (_etablissement != null) {
        await txn.update(
          'etablissement',
          {'annee_scolaire': libelle},
          where: 'id = ?',
          whereArgs: [_etablissement!.id],
        );
      }
    });

    // 5. Reload provider state
    _invalidateMoyennes();
    _classCourses.clear();
    _classEleves.clear();
    await loadEtablissement();
    await loadAnneesScolaires();
    _selectedAnneeScolaire = _activeAnneeScolaire;
    await loadClasses();
    notifyListeners();
    return resultat;
  }
}
