class Eleve {
  final int? id;
  final String nom;
  final String prenom;
  final int classeId;
  final String? matricule;
  final String? dateNaissance;
  final String? photoPath;
  /// Téléphone du parent / tuteur (utile pour les relances de paiement).
  final String? telephoneParent;
  /// Réduction accordée sur les frais de scolarité (FCFA) : fratrie, enfant du personnel...
  final double remiseScolarite;
  final int? notesCount;

  Eleve({
    this.id,
    required this.nom,
    required this.prenom,
    required this.classeId,
    this.matricule,
    this.dateNaissance,
    this.photoPath,
    this.telephoneParent,
    this.remiseScolarite = 0,
    this.notesCount,
  });

  String get nomComplet => '$prenom $nom';

  Eleve copyWith({
    String? nom,
    String? prenom,
    int? classeId,
    String? matricule,
    String? dateNaissance,
    String? photoPath,
    String? telephoneParent,
    double? remiseScolarite,
  }) {
    return Eleve(
      id: id,
      nom: nom ?? this.nom,
      prenom: prenom ?? this.prenom,
      classeId: classeId ?? this.classeId,
      matricule: matricule ?? this.matricule,
      dateNaissance: dateNaissance ?? this.dateNaissance,
      photoPath: photoPath ?? this.photoPath,
      telephoneParent: telephoneParent ?? this.telephoneParent,
      remiseScolarite: remiseScolarite ?? this.remiseScolarite,
      notesCount: notesCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nom': nom,
      'prenom': prenom,
      'classe_id': classeId,
      'matricule': matricule,
      'date_naissance': dateNaissance,
      'photo_path': photoPath,
      'telephone_parent': telephoneParent,
      'remise_scolarite': remiseScolarite,
    };
  }

  factory Eleve.fromMap(Map<String, dynamic> map) {
    return Eleve(
      id: map['id'] as int?,
      nom: map['nom'] as String,
      prenom: map['prenom'] as String,
      classeId: map['classe_id'] as int,
      matricule: map['matricule'] as String?,
      dateNaissance: map['date_naissance'] as String?,
      photoPath: map['photo_path'] as String?,
      telephoneParent: map['telephone_parent'] as String?,
      remiseScolarite: (map['remise_scolarite'] as num?)?.toDouble() ?? 0,
      notesCount: map['notes_count'] as int?,
    );
  }
}
