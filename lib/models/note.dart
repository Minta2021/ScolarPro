class Note {
  final int? id;
  final int eleveId;
  final int coursId;
  final int trimestre; // 1, 2, 3
  final double? noteClasse;
  final double? noteComposition;

  Note({
    this.id,
    required this.eleveId,
    required this.coursId,
    required this.trimestre,
    this.noteClasse,
    this.noteComposition,
  });

  double? get moyenneCours {
    if (noteClasse == null || noteComposition == null) return null;
    return (noteClasse! + noteComposition!) / 3;
  }

  /// Moyenne du cours selon le mode de la classe.
  /// Primaire : la note de composition seule (sur 10). Secondaire : (classe + compo) / 3.
  double? moyenneCoursPour(bool primaire) {
    if (primaire) return noteComposition;
    return moyenneCours;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'eleve_id': eleveId,
      'cours_id': coursId,
      'trimestre': trimestre,
      'note_classe': noteClasse,
      'note_composition': noteComposition,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      eleveId: map['eleve_id'] as int,
      coursId: map['cours_id'] as int,
      trimestre: map['trimestre'] as int,
      noteClasse: map['note_classe'] != null ? (map['note_classe'] as num).toDouble() : null,
      noteComposition: map['note_composition'] != null ? (map['note_composition'] as num).toDouble() : null,
    );
  }
}
