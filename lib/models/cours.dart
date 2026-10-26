class Cours {
  final int? id;
  final String nom;
  final int coefficient;
  final int classeId;

  Cours({
    this.id,
    required this.nom,
    required this.coefficient,
    required this.classeId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nom': nom,
      'coefficient': coefficient,
      'classe_id': classeId,
    };
  }

  factory Cours.fromMap(Map<String, dynamic> map) {
    return Cours(
      id: map['id'] as int?,
      nom: map['nom'] as String,
      coefficient: map['coefficient'] as int,
      classeId: map['classe_id'] as int,
    );
  }
}
