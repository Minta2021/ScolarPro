class AnneeScolaire {
  final int? id;
  final String libelle;
  final bool active;

  AnneeScolaire({
    this.id,
    required this.libelle,
    required this.active,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'libelle': libelle,
      'active': active ? 1 : 0,
    };
  }

  factory AnneeScolaire.fromMap(Map<String, dynamic> map) {
    return AnneeScolaire(
      id: map['id'] as int?,
      libelle: map['libelle'] as String,
      active: (map['active'] as int) == 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnneeScolaire &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          libelle == other.libelle &&
          active == other.active;

  @override
  int get hashCode => id.hashCode ^ libelle.hashCode ^ active.hashCode;
}
