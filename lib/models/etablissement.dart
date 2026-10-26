class Etablissement {
  final int? id;
  final String nom;
  final String? adresse;
  final String? telephone;
  final String? logoPath;
  final String anneeScolaire;

  Etablissement({
    this.id,
    required this.nom,
    this.adresse,
    this.telephone,
    this.logoPath,
    required this.anneeScolaire,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nom': nom,
      'adresse': adresse,
      'telephone': telephone,
      'logo_path': logoPath,
      'annee_scolaire': anneeScolaire,
    };
  }

  factory Etablissement.fromMap(Map<String, dynamic> map) {
    return Etablissement(
      id: map['id'] as int?,
      nom: map['nom'] as String,
      adresse: map['adresse'] as String?,
      telephone: map['telephone'] as String?,
      logoPath: map['logo_path'] as String?,
      anneeScolaire: map['annee_scolaire'] as String,
    );
  }
}
