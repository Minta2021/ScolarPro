class Classe {
  static const String modePrimaire = 'primaire';
  static const String modeSecondaire = 'secondaire';

  /// Mode par défaut selon le niveau saisi : 1ère à 6ème année = primaire,
  /// tout le reste (7ème à 12ème, Terminale...) = secondaire.
  static String modePourNiveau(String niveau) {
    final n = niveau.toLowerCase();
    if (n.contains('primaire')) return modePrimaire;
    final match = RegExp(r'\d+').firstMatch(n);
    if (match != null) {
      final annee = int.parse(match.group(0)!);
      return annee >= 1 && annee <= 6 ? modePrimaire : modeSecondaire;
    }
    if (n.contains('terminale') || n.contains('lycée') || n.contains('lycee')) {
      return modeSecondaire;
    }
    return modeSecondaire;
  }

  /// Niveau proposé pour une classe créée automatiquement (import Excel) à partir de son nom.
  static String niveauPourNom(String nom) {
    if (modePourNiveau(nom) == modePrimaire) return 'Primaire';
    final n = nom.toLowerCase();
    final match = RegExp(r'\d+').firstMatch(n);
    if (match != null) {
      final annee = int.parse(match.group(0)!);
      if (annee >= 10) return 'Lycée';
      return 'Collège';
    }
    if (n.contains('terminale') || n.contains('lycée') || n.contains('lycee') ||
        n.contains('seconde') || n.contains('première') || n.contains('premiere')) {
      return 'Lycée';
    }
    return 'Collège';
  }

  final int? id;
  final String nom;
  final String niveau;
  final int? anneeScolaireId;
  final int? nextClassId;
  final String modeCalcul;
  /// Frais d'inscription (FCFA) exigés pour un élève de cette classe.
  final double fraisInscription;
  /// Frais de scolarité annuels (FCFA) exigés pour un élève de cette classe.
  final double fraisScolarite;
  final int? elevesCount;
  final int? coursCount;

  Classe({
    this.id,
    required this.nom,
    required this.niveau,
    this.anneeScolaireId,
    this.nextClassId,
    this.modeCalcul = modeSecondaire,
    this.fraisInscription = 0,
    this.fraisScolarite = 0,
    this.elevesCount,
    this.coursCount,
  });

  bool get isPrimaire => modeCalcul == modePrimaire;

  /// Vrai si au moins un des deux frais a été défini pour la classe.
  bool get fraisDefinis => fraisInscription > 0 || fraisScolarite > 0;

  /// Barème de la moyenne (et de la note de composition au primaire).
  int get bareme => isPrimaire ? 10 : 20;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nom': nom,
      'niveau': niveau,
      if (anneeScolaireId != null) 'annee_scolaire_id': anneeScolaireId,
      'next_class_id': nextClassId,
      'mode_calcul': modeCalcul,
      'frais_inscription': fraisInscription,
      'frais_scolarite': fraisScolarite,
    };
  }

  factory Classe.fromMap(Map<String, dynamic> map) {
    return Classe(
      id: map['id'] as int?,
      nom: map['nom'] as String,
      niveau: map['niveau'] as String,
      anneeScolaireId: map['annee_scolaire_id'] as int?,
      nextClassId: map['next_class_id'] as int?,
      modeCalcul: (map['mode_calcul'] as String?) ?? modeSecondaire,
      fraisInscription: (map['frais_inscription'] as num?)?.toDouble() ?? 0,
      fraisScolarite: (map['frais_scolarite'] as num?)?.toDouble() ?? 0,
      elevesCount: map['eleves_count'] as int?,
      coursCount: map['cours_count'] as int?,
    );
  }
}
