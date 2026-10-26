import 'dart:convert';
import 'package:excel/excel.dart' as ex;
import 'package:intl/intl.dart';
import '../models/eleve.dart';
import 'text_utils.dart';

// ════════════════════════════════════════════════════════════════════
// Modèle de données de l'import
// ════════════════════════════════════════════════════════════════════

/// Les informations que l'on peut lire dans une fiche élèves.
enum ImportField { nom, prenom, nomPrenom, matricule, dateNaissance, classe, telephoneParent }

extension ImportFieldLabel on ImportField {
  String get libelle {
    switch (this) {
      case ImportField.nom:
        return 'Nom';
      case ImportField.prenom:
        return 'Prénom';
      case ImportField.nomPrenom:
        return 'Nom complet (nom + prénom dans la même colonne)';
      case ImportField.matricule:
        return 'Matricule';
      case ImportField.dateNaissance:
        return 'Date de naissance';
      case ImportField.classe:
        return 'Classe';
      case ImportField.telephoneParent:
        return 'Téléphone du parent';
    }
  }
}

/// Ordre des mots dans une colonne « nom complet ».
enum OrdreNomComplet {
  /// Le mot écrit en MAJUSCULES est le nom ; sinon le premier mot est le nom.
  auto,
  nomPuisPrenom,
  prenomPuisNom,
}

/// Une cellule lue dans le fichier.
class ImportCell {
  /// Texte affiché de la cellule.
  final String? texte;

  /// Date au format jj/mm/aaaa si la cellule peut être lue comme une date.
  final String? date;

  const ImportCell(this.texte, [this.date]);

  static const ImportCell vide = ImportCell(null);
}

/// Une feuille (ou un fichier CSV) sous forme de tableau.
class ImportSheet {
  final String nom;
  final List<List<ImportCell>> lignes;

  ImportSheet(this.nom, this.lignes);

  int get nbColonnes => lignes.fold(0, (m, l) => l.length > m ? l.length : m);

  ImportCell cellule(int ligne, int colonne) {
    if (ligne < 0 || ligne >= lignes.length) return ImportCell.vide;
    final l = lignes[ligne];
    if (colonne < 0 || colonne >= l.length) return ImportCell.vide;
    return l[colonne];
  }

  /// Vrai si la feuille contient au moins une cellule non vide.
  bool get nonVide => lignes.any((l) => l.any((c) => (c.texte ?? '').trim().isNotEmpty));
}

class ImportWorkbook {
  final List<ImportSheet> feuilles;
  final String? erreur;

  const ImportWorkbook({this.feuilles = const [], this.erreur});
}

/// Association « information → numéro de colonne ».
class ImportMapping {
  final Map<ImportField, int> colonnes;

  ImportMapping([Map<ImportField, int>? colonnes]) : colonnes = colonnes ?? {};

  int? operator [](ImportField f) => colonnes[f];

  bool get aDesNoms =>
      colonnes.containsKey(ImportField.nomPrenom) ||
      (colonnes.containsKey(ImportField.nom) && colonnes.containsKey(ImportField.prenom));

  ImportMapping copie() => ImportMapping(Map.of(colonnes));
}

/// Une ligne lue depuis la fiche Excel.
class ImportedEleveRow {
  final int ligne; // numéro de ligne dans Excel (1-based)
  final String feuille;
  final String nom;
  final String prenom;
  final String? matricule;
  final String? dateNaissance;
  final String? telephoneParent;
  final String? classe; // texte de la colonne « Classe » (ou nom de la feuille)
  final String? probleme; // null si la ligne peut être importée

  const ImportedEleveRow({
    required this.ligne,
    this.feuille = '',
    required this.nom,
    required this.prenom,
    this.matricule,
    this.dateNaissance,
    this.telephoneParent,
    this.classe,
    this.probleme,
  });

  bool get valide => probleme == null;

  ImportedEleveRow withProbleme(String probleme) => ImportedEleveRow(
        ligne: ligne,
        feuille: feuille,
        nom: nom,
        prenom: prenom,
        matricule: matricule,
        dateNaissance: dateNaissance,
        telephoneParent: telephoneParent,
        classe: classe,
        probleme: probleme,
      );

  Eleve toEleve(int classeId) => Eleve(
        nom: nom,
        prenom: prenom,
        classeId: classeId,
        matricule: matricule,
        dateNaissance: dateNaissance,
        telephoneParent: telephoneParent,
      );
}

class ExcelImportResult {
  final List<ImportedEleveRow> rows;
  final String? erreur; // erreur bloquante (fichier illisible, colonnes absentes…)
  final String? feuille;

  const ExcelImportResult({this.rows = const [], this.erreur, this.feuille});

  List<ImportedEleveRow> get valides => rows.where((r) => r.valide).toList();
  List<ImportedEleveRow> get ignores => rows.where((r) => !r.valide).toList();
}

// ════════════════════════════════════════════════════════════════════
// Service
// ════════════════════════════════════════════════════════════════════

class ExcelImportService {
  static const List<String> templateHeaders = [
    'Nom',
    'Prénom',
    'Matricule',
    'Date de naissance',
    'Classe',
    'Téléphone parent',
  ];

  /// Nombre de lignes examinées pour trouver la ligne d'en-tête.
  static const int lignesEnteteMax = 15;

  /// Génère une fiche modèle vierge (.xlsx) à remplir.
  static List<int>? buildTemplate() {
    final excel = ex.Excel.createExcel();
    excel.rename('Sheet1', 'Eleves');
    final sheet = excel['Eleves'];
    sheet.appendRow(templateHeaders.map((h) => ex.TextCellValue(h)).toList());
    for (var i = 0; i < templateHeaders.length; i++) {
      sheet.setColumnWidth(i, 22);
    }
    return excel.encode();
  }

  /// Nom de colonne façon Excel : 0 → A, 25 → Z, 26 → AA.
  static String lettreColonne(int index) {
    var n = index + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  // ── Lecture du fichier ────────────────────────────────────────────

  /// Lit un classeur .xlsx ou un fichier .csv / .txt.
  static ImportWorkbook lireFichier(List<int> bytes, {String nomFichier = ''}) {
    final ext = nomFichier.toLowerCase();
    final estZip = bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B; // « PK »
    final estOle = bytes.length >= 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0;

    if (estOle || ext.endsWith('.xls')) {
      return const ImportWorkbook(
        erreur: "Ce fichier est au format Excel 97-2003 (.xls), qui n'est pas pris en charge.\n"
            "Ouvrez-le dans Excel puis faites « Fichier > Enregistrer sous > Classeur Excel (.xlsx) », "
            "et importez le nouveau fichier.",
      );
    }
    if (!estZip && (ext.endsWith('.csv') || ext.endsWith('.txt') || !ext.endsWith('.xlsx'))) {
      return _lireCsv(bytes, nomFichier);
    }
    return _lireXlsx(bytes);
  }

  static ImportWorkbook _lireXlsx(List<int> bytes) {
    final ex.Excel excel;
    try {
      excel = ex.Excel.decodeBytes(bytes);
    } catch (_) {
      return const ImportWorkbook(
        erreur: "Impossible de lire ce fichier. Vérifiez qu'il s'agit bien d'un classeur Excel (.xlsx) "
            "et qu'il n'est pas protégé par un mot de passe.",
      );
    }
    final feuilles = <ImportSheet>[];
    for (final entry in excel.tables.entries) {
      final lignes = entry.value.rows
          .map((row) => row.map((cell) => _lireCellule(cell?.value)).toList())
          .toList();
      final sheet = ImportSheet(entry.key, lignes);
      if (sheet.nonVide) feuilles.add(sheet);
    }
    if (feuilles.isEmpty) {
      return const ImportWorkbook(erreur: "Le classeur est vide : aucune feuille ne contient de données.");
    }
    return ImportWorkbook(feuilles: feuilles);
  }

  static ImportCell _lireCellule(ex.CellValue? value) {
    if (value == null) return ImportCell.vide;
    return ImportCell(_cellText(value), _dateText(value));
  }

  static ImportWorkbook _lireCsv(List<int> bytes, String nomFichier) {
    String contenu;
    try {
      contenu = utf8.decode(bytes);
    } catch (_) {
      contenu = latin1.decode(bytes); // fichiers CSV enregistrés par Excel sous Windows
    }
    if (contenu.startsWith('﻿')) contenu = contenu.substring(1);
    final lignesBrutes = parseCsv(contenu);
    final lignes = lignesBrutes
        .map((l) => l.map((v) {
              final t = v.trim();
              if (t.isEmpty) return ImportCell.vide;
              return ImportCell(t, _dateDepuisTexte(t));
            }).toList())
        .toList();
    final nom = nomFichier.isEmpty ? 'CSV' : nomFichier.split(RegExp(r'[\\/]')).last;
    final sheet = ImportSheet(nom, lignes);
    if (!sheet.nonVide) return const ImportWorkbook(erreur: "Le fichier est vide.");
    return ImportWorkbook(feuilles: [sheet]);
  }

  /// Découpe un texte CSV (séparateur « ; », « , » ou tabulation détecté automatiquement,
  /// guillemets et retours à la ligne dans les cellules gérés).
  static List<List<String>> parseCsv(String contenu) {
    final premiereLigne = contenu.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    int compter(String c) => premiereLigne.split(c).length - 1;
    var sep = ';';
    var meilleur = compter(';');
    for (final c in [',', '\t']) {
      final n = compter(c);
      if (n > meilleur) {
        meilleur = n;
        sep = c;
      }
    }

    final lignes = <List<String>>[];
    var ligne = <String>[];
    final cellule = StringBuffer();
    var entreGuillemets = false;
    var i = 0;
    while (i < contenu.length) {
      final ch = contenu[i];
      if (entreGuillemets) {
        if (ch == '"') {
          if (i + 1 < contenu.length && contenu[i + 1] == '"') {
            cellule.write('"');
            i++;
          } else {
            entreGuillemets = false;
          }
        } else {
          cellule.write(ch);
        }
      } else if (ch == '"') {
        entreGuillemets = true;
      } else if (ch == sep) {
        ligne.add(cellule.toString());
        cellule.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < contenu.length && contenu[i + 1] == '\n') i++;
        ligne.add(cellule.toString());
        cellule.clear();
        lignes.add(ligne);
        ligne = <String>[];
      } else {
        cellule.write(ch);
      }
      i++;
    }
    if (cellule.isNotEmpty || ligne.isNotEmpty) {
      ligne.add(cellule.toString());
      lignes.add(ligne);
    }
    return lignes;
  }

  // ── Détection automatique ─────────────────────────────────────────

  static ImportField? _champPourEntete(String entete) {
    final h = normaliser(entete);
    if (h.isEmpty) return null;
    const nomPrenom = {
      'nomprenom', 'nomprenoms', 'nometprenom', 'nometprenoms', 'nomsetprenoms', 'nomsprenoms',
      'nomcomplet', 'prenometnom', 'prenomsetnom', 'prenomnom', 'prenomsnom', 'eleve', 'eleves',
      'nomdeleleve', 'nomprenomdeleleve', 'nomcompletdeleleve', 'identite', 'fullname',
    };
    if (nomPrenom.contains(h)) return ImportField.nomPrenom;
    if (const {'nom', 'noms', 'nomdefamille', 'nomfamille', 'lastname', 'patronyme'}.contains(h)) {
      return ImportField.nom;
    }
    // Colonnes concernant les parents (« Prénom du père », « Nom de la mère »...) : sauf téléphone, on les ignore
    final concerneParent = h.contains('pere') || h.contains('mere') || h.contains('tuteur') || h.contains('parent');
    if (h.startsWith('prenom') && !concerneParent) return ImportField.prenom;
    if (h == 'firstname') return ImportField.prenom;
    if (h.contains('matricule') || h == 'mat' || h == 'numero' || h == 'nummatricule' || h == 'ine') {
      return ImportField.matricule;
    }
    if ((h.contains('naiss') && !h.contains('lieu')) ||
        const {'ddn', 'nele', 'nee', 'neele', 'neel', 'birthdate', 'datedenais'}.contains(h)) {
      return ImportField.dateNaissance;
    }
    if (h.startsWith('classe') || h == 'salle' || h == 'division' || h == 'section' || h == 'class') {
      return ImportField.classe;
    }
    if (h.contains('tel') ||
        h.contains('phone') ||
        h.contains('contact') ||
        h.contains('portable') ||
        h.contains('cellulaire') ||
        h.contains('gsm')) {
      return ImportField.telephoneParent;
    }
    return null;
  }

  /// Associe automatiquement les colonnes d'une ligne d'en-tête.
  static ImportMapping detecterColonnes(List<ImportCell> entete) {
    final mapping = ImportMapping();
    for (var c = 0; c < entete.length; c++) {
      final champ = _champPourEntete(entete[c].texte ?? '');
      if (champ != null) mapping.colonnes.putIfAbsent(champ, () => c);
    }
    // Une seule colonne « Nom » sans colonne « Prénom » : elle contient sans doute le nom complet
    if (mapping.colonnes.containsKey(ImportField.nom) &&
        !mapping.colonnes.containsKey(ImportField.prenom) &&
        !mapping.colonnes.containsKey(ImportField.nomPrenom)) {
      mapping.colonnes[ImportField.nomPrenom] = mapping.colonnes.remove(ImportField.nom)!;
    }
    return mapping;
  }

  /// Cherche la ligne d'en-tête (index 0-based) parmi les premières lignes de la feuille.
  static int? detecterLigneEntete(ImportSheet sheet) {
    for (var r = 0; r < sheet.lignes.length && r < lignesEnteteMax; r++) {
      final mapping = detecterColonnes(sheet.lignes[r]);
      if (mapping.aDesNoms) return r;
    }
    return null;
  }

  // ── Extraction des élèves ─────────────────────────────────────────

  /// Sépare un nom complet en (nom, prénom).
  static (String, String?) separerNomComplet(String complet, OrdreNomComplet ordre) {
    final mots = complet.split(' ').where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return ('', null);
    if (mots.length == 1) return (mots.first, null);

    if (ordre == OrdreNomComplet.auto) {
      bool enMajuscules(String m) {
        final lettres = m.replaceAll(RegExp(r"[^A-Za-zÀ-ÖØ-öø-ÿ]"), '');
        return lettres.length >= 2 && lettres == lettres.toUpperCase() && lettres != lettres.toLowerCase();
      }

      final majuscules = mots.where(enMajuscules).toList();
      if (majuscules.isNotEmpty && majuscules.length < mots.length) {
        final autres = mots.where((m) => !enMajuscules(m)).toList();
        return (majuscules.join(' '), autres.join(' '));
      }
      return (mots.first, mots.sublist(1).join(' '));
    }
    if (ordre == OrdreNomComplet.prenomPuisNom) {
      return (mots.last, mots.sublist(0, mots.length - 1).join(' '));
    }
    return (mots.first, mots.sublist(1).join(' '));
  }

  /// Transforme les lignes d'une feuille en élèves, à partir de la ligne qui suit l'en-tête.
  /// [ligneEntete] = null : la feuille n'a pas d'en-tête, toutes les lignes sont des élèves.
  /// [classeFeuille] : classe à utiliser quand il n'y a pas de colonne « Classe » (ex. nom de la feuille).
  static List<ImportedEleveRow> extraireLignes(
    ImportSheet sheet, {
    required int? ligneEntete,
    required ImportMapping mapping,
    OrdreNomComplet ordre = OrdreNomComplet.auto,
    String? classeFeuille,
  }) {
    String? valeur(int r, ImportField champ) {
      final col = mapping[champ];
      if (col == null) return null;
      final cell = sheet.cellule(r, col);
      final texte = champ == ImportField.dateNaissance ? (cell.date ?? cell.texte) : cell.texte;
      if (texte == null) return null;
      final propre = texte.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (propre.isEmpty || propre.toUpperCase() == 'N/A' || propre == '-') return null;
      return propre;
    }

    final result = <ImportedEleveRow>[];
    final debut = ligneEntete == null ? 0 : ligneEntete + 1;
    for (var r = debut; r < sheet.lignes.length; r++) {
      String? nom = valeur(r, ImportField.nom);
      String? prenom = valeur(r, ImportField.prenom);
      final nomPrenom = valeur(r, ImportField.nomPrenom);
      final matricule = valeur(r, ImportField.matricule);
      final date = valeur(r, ImportField.dateNaissance);
      final telephone = valeur(r, ImportField.telephoneParent);
      final classe = valeur(r, ImportField.classe) ?? classeFeuille;

      if (nom == null && prenom == null && nomPrenom == null && matricule == null && date == null) {
        continue; // ligne vide
      }

      // Colonne unique « Nom & Prénom »
      if (nom == null && prenom == null && nomPrenom != null) {
        final (n, p) = separerNomComplet(nomPrenom, ordre);
        nom = n;
        prenom = p;
      }

      String? probleme;
      if (nom == null && prenom == null) {
        probleme = 'Nom et prénom manquants';
      } else if (nom == null) {
        probleme = 'Nom manquant';
      } else if (prenom == null) {
        probleme = 'Prénom manquant';
      }

      result.add(ImportedEleveRow(
        ligne: r + 1,
        feuille: sheet.nom,
        nom: (nom ?? '').toUpperCase(),
        prenom: prenom ?? '',
        matricule: matricule,
        dateNaissance: date,
        telephoneParent: telephone,
        classe: classe,
        probleme: probleme,
      ));
    }
    return result;
  }

  /// Marque les doublons et les élèves déjà inscrits.
  /// [cible] donne la clé de la classe de destination d'une ligne.
  /// [nomsExistants] : clé de classe → élèves déjà inscrits (clé [cleEleve]).
  /// [matriculesExistants] : matricules déjà utilisés (en minuscules).
  static List<ImportedEleveRow> marquerDoublons(
    List<ImportedEleveRow> rows, {
    required String Function(ImportedEleveRow row) cible,
    Map<String, Set<String>> nomsExistants = const {},
    Set<String> matriculesExistants = const {},
    String messageMatricule = 'Matricule déjà utilisé',
    String messageNom = 'Élève déjà inscrit dans la classe',
  }) {
    final seenNames = <String>{};
    final seenMatricules = <String>{};

    return rows.map((row) {
      if (!row.valide) return row;
      final classeCle = cible(row);
      final key = '$classeCle#${cleEleve(row.nom, row.prenom)}';
      final mat = row.matricule?.trim().toLowerCase();
      if (mat != null && matriculesExistants.contains(mat)) {
        return row.withProbleme(messageMatricule);
      }
      if (nomsExistants[classeCle]?.contains(cleEleve(row.nom, row.prenom)) ?? false) {
        return row.withProbleme(messageNom);
      }
      if ((mat != null && !seenMatricules.add(mat)) || !seenNames.add(key)) {
        return row.withProbleme('Doublon dans le fichier');
      }
      return row;
    }).toList();
  }

  // ── Import simple vers une classe (utilisé par les tests et les anciens écrans) ──

  /// Lit une fiche Excel et la compare aux élèves déjà inscrits dans la classe.
  static ExcelImportResult parse(List<int> bytes, {List<Eleve> existants = const [], String nomFichier = 'fiche.xlsx'}) {
    final workbook = lireFichier(bytes, nomFichier: nomFichier);
    if (workbook.erreur != null) return ExcelImportResult(erreur: workbook.erreur);

    for (final sheet in workbook.feuilles) {
      final entete = detecterLigneEntete(sheet);
      if (entete == null) continue;
      final mapping = detecterColonnes(sheet.lignes[entete]);
      final rows = extraireLignes(sheet, ligneEntete: entete, mapping: mapping);
      return ExcelImportResult(
        rows: marquerDoublons(
          rows,
          cible: (_) => 'classe',
          nomsExistants: {'classe': existants.map((e) => cleEleve(e.nom, e.prenom)).toSet()},
          matriculesExistants: existants
              .where((e) => e.matricule != null)
              .map((e) => e.matricule!.trim().toLowerCase())
              .toSet(),
          messageMatricule: 'Matricule déjà utilisé dans la classe',
        ),
        feuille: sheet.nom,
      );
    }

    return const ExcelImportResult(
      erreur: "Aucune ligne d'en-tête reconnue. La fiche doit contenir les colonnes « Nom » et « Prénom » "
          "(ou « Nom & Prénom »), et éventuellement « Matricule », « Date de naissance », « Classe » "
          "et « Téléphone parent ».",
    );
  }

  // ── Conversion des cellules ───────────────────────────────────────

  static String? _cellText(ex.CellValue? value) {
    if (value == null) return null;
    if (value is ex.DoubleCellValue && value.value == value.value.roundToDouble()) {
      return value.value.toInt().toString();
    }
    if (value is ex.DateCellValue || value is ex.DateTimeCellValue) return _dateText(value);
    return value.toString();
  }

  static final DateFormat _outFormat = DateFormat('dd/MM/yyyy');

  static String? _dateText(ex.CellValue? value) {
    if (value == null) return null;
    if (value is ex.DateCellValue) return _outFormat.format(DateTime(value.year, value.month, value.day));
    if (value is ex.DateTimeCellValue) return _outFormat.format(DateTime(value.year, value.month, value.day));

    // Numéro de série Excel (date non formatée)
    num? serial;
    if (value is ex.IntCellValue) serial = value.value;
    if (value is ex.DoubleCellValue) serial = value.value;
    if (serial != null) {
      if (serial > 0 && serial < 80000) {
        return _outFormat.format(DateTime(1899, 12, 30).add(Duration(days: serial.floor())));
      }
      return serial.toString();
    }

    return _dateDepuisTexte(value.toString().trim()) ?? value.toString().trim();
  }

  /// Essaie de lire une date écrite en texte (05/03/2012, 5-3-2012, 2012-03-05...).
  static String? _dateDepuisTexte(String text) {
    final premier = text.split(' ').first;
    for (final pattern in const ['d/M/yyyy', 'd-M-yyyy', 'd.M.yyyy', 'yyyy-M-d', 'yyyy/M/d']) {
      try {
        final date = DateFormat(pattern).parseStrict(premier);
        return _outFormat.format(date);
      } catch (_) {}
    }
    return null;
  }
}
