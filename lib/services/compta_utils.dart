/// Outils de calcul de la comptabilité (sans accès à la base : testables facilement).
library;

/// Statut d'un élève pour un type de frais.
enum StatutPaiement {
  /// Aucun montant n'a été défini pour la classe.
  nonDefini,

  /// Remise totale : rien à payer.
  exonere,

  /// Tout est payé.
  solde,

  /// Une partie seulement est payée.
  partiel,

  /// Aucun versement.
  nonPaye,
}

extension StatutPaiementLabel on StatutPaiement {
  String get libelle {
    switch (this) {
      case StatutPaiement.nonDefini:
        return 'Frais non définis';
      case StatutPaiement.exonere:
        return 'Exonéré';
      case StatutPaiement.solde:
        return 'Soldé';
      case StatutPaiement.partiel:
        return 'Partiel';
      case StatutPaiement.nonPaye:
        return 'Non payé';
    }
  }

  /// Élève en règle pour ces frais (tout payé ou exonéré).
  bool get enRegle => this == StatutPaiement.solde || this == StatutPaiement.exonere;
}

/// Calcule le statut à partir du montant brut des frais, du montant dû (après remise) et du montant payé.
StatutPaiement calculerStatut({required double fraisBrut, required double du, required double paye}) {
  if (fraisBrut <= 0) return StatutPaiement.nonDefini;
  if (du <= 0) return StatutPaiement.exonere;
  if (paye >= du - 0.5) return StatutPaiement.solde;
  if (paye > 0) return StatutPaiement.partiel;
  return StatutPaiement.nonPaye;
}

/// Situation financière d'un élève pour l'année.
class SituationEleve {
  final int eleveId;
  final String nom;
  final String prenom;
  final String? matricule;
  final String? telephoneParent;
  final int classeId;
  final String classeNom;
  final double fraisInscription;
  final double fraisScolarite;
  final double remiseScolarite;
  final double payeInscription;
  final double payeScolarite;

  const SituationEleve({
    required this.eleveId,
    required this.nom,
    required this.prenom,
    this.matricule,
    this.telephoneParent,
    required this.classeId,
    required this.classeNom,
    required this.fraisInscription,
    required this.fraisScolarite,
    required this.remiseScolarite,
    required this.payeInscription,
    required this.payeScolarite,
  });

  factory SituationEleve.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return SituationEleve(
      eleveId: m['eleve_id'] as int,
      nom: m['nom'] as String,
      prenom: m['prenom'] as String,
      matricule: m['matricule'] as String?,
      telephoneParent: m['telephone_parent'] as String?,
      classeId: m['classe_id'] as int,
      classeNom: m['classe_nom'] as String,
      fraisInscription: d('frais_inscription'),
      fraisScolarite: d('frais_scolarite'),
      remiseScolarite: d('remise_scolarite'),
      payeInscription: d('paye_inscription'),
      payeScolarite: d('paye_scolarite'),
    );
  }

  String get nomComplet => '$prenom $nom';

  double get duInscription => fraisInscription;
  double get duScolarite => (fraisScolarite - remiseScolarite).clamp(0, double.infinity).toDouble();

  double get resteInscription => (duInscription - payeInscription).clamp(0, double.infinity).toDouble();
  double get resteScolarite => (duScolarite - payeScolarite).clamp(0, double.infinity).toDouble();
  double get resteTotal => resteInscription + resteScolarite;
  double get payeTotal => payeInscription + payeScolarite;
  double get duTotal => duInscription + duScolarite;

  StatutPaiement get statutInscription =>
      calculerStatut(fraisBrut: fraisInscription, du: duInscription, paye: payeInscription);
  StatutPaiement get statutScolarite =>
      calculerStatut(fraisBrut: fraisScolarite, du: duScolarite, paye: payeScolarite);

  /// Situation globale (inscription + scolarité confondues).
  StatutPaiement get statutGlobal =>
      calculerStatut(fraisBrut: fraisInscription + fraisScolarite, du: duTotal, paye: payeTotal);

  double dejaPaye(String type) => type == 'inscription' ? payeInscription : payeScolarite;
  double du(String type) => type == 'inscription' ? duInscription : duScolarite;
  double reste(String type) => type == 'inscription' ? resteInscription : resteScolarite;
  StatutPaiement statut(String type) => type == 'inscription' ? statutInscription : statutScolarite;
}

/// Compteurs pour un type de frais.
class ResumeFrais {
  int concernes = 0; // élèves dont la classe a des frais définis
  int enRegle = 0; // soldé ou exonéré
  int exoneres = 0;
  int partiels = 0;
  int nonPayes = 0;
  int nonDefinis = 0; // élèves dont la classe n'a pas de frais
  double attendu = 0;
  double encaisse = 0;
  double reste = 0;

  double get tauxRecouvrement => attendu <= 0 ? 0 : (encaisse / attendu * 100).clamp(0, 100).toDouble();

  void ajouter(StatutPaiement statut, double du, double paye, double reste) {
    if (statut == StatutPaiement.nonDefini) {
      nonDefinis++;
      encaisse += paye;
      return;
    }
    concernes++;
    attendu += du;
    encaisse += paye;
    this.reste += reste;
    switch (statut) {
      case StatutPaiement.solde:
        enRegle++;
        break;
      case StatutPaiement.exonere:
        enRegle++;
        exoneres++;
        break;
      case StatutPaiement.partiel:
        partiels++;
        break;
      case StatutPaiement.nonPaye:
        nonPayes++;
        break;
      case StatutPaiement.nonDefini:
        break;
    }
  }
}

/// Résumé global (ou d'une classe) de la comptabilité.
class ResumeCompta {
  final int effectif;
  final ResumeFrais inscription;
  final ResumeFrais scolarite;

  ResumeCompta._(this.effectif, this.inscription, this.scolarite);

  factory ResumeCompta.depuis(Iterable<SituationEleve> situations) {
    final insc = ResumeFrais();
    final scol = ResumeFrais();
    var n = 0;
    for (final s in situations) {
      n++;
      insc.ajouter(s.statutInscription, s.duInscription, s.payeInscription, s.resteInscription);
      scol.ajouter(s.statutScolarite, s.duScolarite, s.payeScolarite, s.resteScolarite);
    }
    return ResumeCompta._(n, insc, scol);
  }

  double get totalEncaisse => inscription.encaisse + scolarite.encaisse;
  double get totalAttendu => inscription.attendu + scolarite.attendu;
  double get totalReste => inscription.reste + scolarite.reste;
  double get tauxRecouvrement =>
      totalAttendu <= 0 ? 0 : (totalEncaisse / totalAttendu * 100).clamp(0, 100).toDouble();
}

// ════════════════════════════════════════════════════════════════════
// Formatage des montants
// ════════════════════════════════════════════════════════════════════

/// 1250000 → "1 250 000" (espaces simples : compatibles avec Excel et les PDF).
String formatMontant(num montant) {
  final arrondi = montant.round();
  final negatif = arrondi < 0;
  final chiffres = arrondi.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(chiffres[i]);
  }
  return '${negatif ? '-' : ''}$buffer';
}

/// 1250000 → "1 250 000 FCFA"
String formatFcfa(num montant) => '${formatMontant(montant)} FCFA';

/// Lit un montant saisi par l'utilisateur ("25 000", "25000", "25.000", "25 000 FCFA").
double? parseMontant(String texte) {
  var t = texte.toUpperCase().replaceAll('FCFA', '').replaceAll('F', '').trim();
  t = t.replaceAll(RegExp(r'[\s  ]'), '');
  if (t.isEmpty) return null;
  // Les points/virgules suivis d'exactement 3 chiffres sont des séparateurs de milliers
  if (RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(t)) {
    t = t.replaceAll(RegExp(r'[.,]'), '');
  }
  t = t.replaceAll(',', '.');
  return double.tryParse(t);
}

// ════════════════════════════════════════════════════════════════════
// Montant en lettres (pour les reçus)
// ════════════════════════════════════════════════════════════════════

const List<String> _unites = [
  'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf',
  'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize',
];

const Map<int, String> _dizaines = {
  2: 'vingt',
  3: 'trente',
  4: 'quarante',
  5: 'cinquante',
  6: 'soixante',
};

String _moinsDeCent(int n, {bool pluriel = true}) {
  if (n < 17) return _unites[n];
  if (n < 20) return 'dix-${_unites[n - 10]}';
  final d = n ~/ 10;
  final u = n % 10;
  if (d <= 6) {
    final base = _dizaines[d]!;
    if (u == 0) return base;
    if (u == 1) return '$base et un';
    return '$base-${_unites[u]}';
  }
  if (d == 7) {
    if (u == 1) return 'soixante et onze';
    return 'soixante-${_moinsDeCent(10 + u)}';
  }
  if (d == 8) {
    if (u == 0) return pluriel ? 'quatre-vingts' : 'quatre-vingt';
    return 'quatre-vingt-${_unites[u]}';
  }
  return 'quatre-vingt-${_moinsDeCent(10 + u)}';
}

String _moinsDeMille(int n, {bool pluriel = true}) {
  final c = n ~/ 100;
  final r = n % 100;
  if (c == 0) return _moinsDeCent(r, pluriel: pluriel);
  final tete = c == 1 ? 'cent' : '${_unites[c]} cent';
  if (r == 0) return (c > 1 && pluriel) ? '${tete}s' : tete;
  return '$tete ${_moinsDeCent(r, pluriel: pluriel)}';
}

/// Écrit un nombre entier en toutes lettres (orthographe traditionnelle) : 25000 → "vingt-cinq mille".
String nombreEnLettres(int nombre) {
  if (nombre == 0) return 'zéro';
  if (nombre < 0) return 'moins ${nombreEnLettres(-nombre)}';
  var n = nombre;
  final parties = <String>[];

  final milliards = n ~/ 1000000000;
  n %= 1000000000;
  if (milliards > 0) {
    parties.add('${_moinsDeMille(milliards)} ${milliards > 1 ? 'milliards' : 'milliard'}');
  }

  final millions = n ~/ 1000000;
  n %= 1000000;
  if (millions > 0) {
    parties.add('${_moinsDeMille(millions)} ${millions > 1 ? 'millions' : 'million'}');
  }

  final milliers = n ~/ 1000;
  n %= 1000;
  if (milliers > 0) {
    parties.add(milliers == 1 ? 'mille' : '${_moinsDeMille(milliers, pluriel: false)} mille');
  }

  if (n > 0) parties.add(_moinsDeMille(n));
  return parties.join(' ');
}

/// 25000 → "Vingt-cinq mille francs CFA"
String montantEnLettres(num montant) {
  final texte = nombreEnLettres(montant.round());
  return '${texte[0].toUpperCase()}${texte.substring(1)} francs CFA';
}
