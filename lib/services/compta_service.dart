import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/paiement.dart';
import 'compta_utils.dart';

/// Accès à la base pour le module Comptabilité.
class ComptaService {
  ComptaService._();

  static final DateFormat isoDate = DateFormat('yyyy-MM-dd');

  static const String _situationSql = '''
    SELECT e.id AS eleve_id, e.nom, e.prenom, e.matricule, e.telephone_parent, e.remise_scolarite,
           e.classe_id, c.nom AS classe_nom, c.frais_inscription, c.frais_scolarite,
           COALESCE((SELECT SUM(p.montant) FROM paiements p WHERE p.eleve_id = e.id AND p.type = 'inscription'), 0) AS paye_inscription,
           COALESCE((SELECT SUM(p.montant) FROM paiements p WHERE p.eleve_id = e.id AND p.type = 'scolarite'), 0) AS paye_scolarite
    FROM eleves e
    INNER JOIN classes c ON c.id = e.classe_id
  ''';

  /// Situation de tous les élèves d'une année (ou d'une seule classe).
  static Future<List<SituationEleve>> situations(int anneeId, {int? classeId}) async {
    final db = await DBHelper.database;
    final where = StringBuffer('WHERE c.annee_scolaire_id = ?');
    final args = <Object>[anneeId];
    if (classeId != null) {
      where.write(' AND c.id = ?');
      args.add(classeId);
    }
    final rows = await db.rawQuery('$_situationSql $where ORDER BY c.nom ASC, e.nom ASC, e.prenom ASC', args);
    return rows.map(SituationEleve.fromMap).toList();
  }

  /// Situation d'un seul élève.
  static Future<SituationEleve?> situationEleve(int eleveId) async {
    final db = await DBHelper.database;
    final rows = await db.rawQuery('$_situationSql WHERE e.id = ?', [eleveId]);
    if (rows.isEmpty) return null;
    return SituationEleve.fromMap(rows.first);
  }

  /// Historique des paiements d'un élève (du plus récent au plus ancien).
  static Future<List<Paiement>> paiementsEleve(int eleveId) async {
    final db = await DBHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.*, e.nom AS eleve_nom, e.prenom AS eleve_prenom, e.matricule AS eleve_matricule,
             c.nom AS classe_nom, c.id AS classe_id
      FROM paiements p
      INNER JOIN eleves e ON e.id = p.eleve_id
      INNER JOIN classes c ON c.id = e.classe_id
      WHERE p.eleve_id = ?
      ORDER BY p.date_paiement DESC, p.id DESC
    ''', [eleveId]);
    return rows.map(Paiement.fromMap).toList();
  }

  /// Journal des encaissements d'une année, avec filtres optionnels.
  static Future<List<Paiement>> journal(
    int anneeId, {
    int? classeId,
    String? type,
    DateTime? du,
    DateTime? au,
  }) async {
    final db = await DBHelper.database;
    final where = StringBuffer('WHERE c.annee_scolaire_id = ?');
    final args = <Object>[anneeId];
    if (classeId != null) {
      where.write(' AND c.id = ?');
      args.add(classeId);
    }
    if (type != null) {
      where.write(' AND p.type = ?');
      args.add(type);
    }
    if (du != null) {
      where.write(' AND p.date_paiement >= ?');
      args.add(isoDate.format(du));
    }
    if (au != null) {
      where.write(' AND p.date_paiement <= ?');
      args.add(isoDate.format(au));
    }
    final rows = await db.rawQuery('''
      SELECT p.*, e.nom AS eleve_nom, e.prenom AS eleve_prenom, e.matricule AS eleve_matricule,
             c.nom AS classe_nom, c.id AS classe_id
      FROM paiements p
      INNER JOIN eleves e ON e.id = p.eleve_id
      INNER JOIN classes c ON c.id = e.classe_id
      $where
      ORDER BY p.date_paiement DESC, p.id DESC
    ''', args);
    return rows.map(Paiement.fromMap).toList();
  }

  static const String _paiementJoinSql = '''
      SELECT p.*, e.nom AS eleve_nom, e.prenom AS eleve_prenom, e.matricule AS eleve_matricule,
             c.nom AS classe_nom, c.id AS classe_id
      FROM paiements p
      INNER JOIN eleves e ON e.id = p.eleve_id
      INNER JOIN classes c ON c.id = e.classe_id
  ''';

  /// Enregistre un paiement et lui attribue un numéro de reçu unique (REC-000001...).
  static Future<Paiement> enregistrerPaiement(Paiement paiement) async {
    final lignes = await enregistrerPaiements([paiement]);
    return lignes.first;
  }

  /// Enregistre plusieurs paiements versés en même temps (ex. inscription + scolarité) :
  /// ils partagent le même numéro de reçu et sont imprimés sur le même reçu.
  static Future<List<Paiement>> enregistrerPaiements(List<Paiement> paiements) async {
    if (paiements.isEmpty) return [];
    final db = await DBHelper.database;
    final ids = <int>[];
    late String numero;
    await db.transaction((txn) async {
      final maintenant = DateTime.now().toIso8601String();
      for (final paiement in paiements) {
        final map = paiement.toMap()
          ..remove('id')
          ..['created_at'] = maintenant;
        ids.add(await txn.insert('paiements', map));
      }
      numero = 'REC-${ids.first.toString().padLeft(6, '0')}';
      for (final id in ids) {
        await txn.update('paiements', {'numero_recu': numero}, where: 'id = ?', whereArgs: [id]);
      }
    });
    return paiementsDuRecu(numero);
  }

  /// Toutes les lignes d'un même reçu.
  static Future<List<Paiement>> paiementsDuRecu(String numeroRecu) async {
    final db = await DBHelper.database;
    final rows = await db.rawQuery('$_paiementJoinSql WHERE p.numero_recu = ? ORDER BY p.id ASC', [numeroRecu]);
    return rows.map(Paiement.fromMap).toList();
  }

  static Future<void> supprimerPaiement(int paiementId) async {
    final db = await DBHelper.database;
    await db.delete('paiements', where: 'id = ?', whereArgs: [paiementId]);
  }

  /// Met à jour la remise sur la scolarité d'un élève.
  static Future<void> majRemise(int eleveId, double remise) async {
    final db = await DBHelper.database;
    await db.update('eleves', {'remise_scolarite': remise < 0 ? 0 : remise}, where: 'id = ?', whereArgs: [eleveId]);
  }

  /// Met à jour le téléphone du parent d'un élève.
  static Future<void> majTelephoneParent(int eleveId, String? telephone) async {
    final db = await DBHelper.database;
    final t = telephone?.trim();
    await db.update('eleves', {'telephone_parent': (t == null || t.isEmpty) ? null : t},
        where: 'id = ?', whereArgs: [eleveId]);
  }

  /// Met à jour les frais d'une classe.
  static Future<void> majFraisClasse(int classeId, double inscription, double scolarite) async {
    final db = await DBHelper.database;
    await db.update(
      'classes',
      {
        'frais_inscription': inscription < 0 ? 0 : inscription,
        'frais_scolarite': scolarite < 0 ? 0 : scolarite,
      },
      where: 'id = ?',
      whereArgs: [classeId],
    );
  }
}
