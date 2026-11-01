/// Outils pour la saisie des notes (sans dépendance à l'interface : testables).
library;

/// Lit une note saisie : "12", "12,5" ou "12.5". Vide → null.
/// Retourne [double.nan] si le texte n'est pas un nombre.
double? lireNote(String texte) {
  final t = texte.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t) ?? double.nan;
}

/// Message d'erreur pour une note saisie, ou null si elle est vide ou valide.
String? erreurNote(String texte, double max) {
  final n = lireNote(texte);
  if (n == null) return null;
  if (n.isNaN) return "Nombre invalide";
  if (n < 0 || n > max) return "Entre 0 et ${max.toStringAsFixed(0)}";
  return null;
}

/// Affichage court d'une note : 12 → "12", 12.5 → "12.5", 12.333 → "12.33".
String formatNote(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  final s = v.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

/// Moyenne d'un élève dans une matière.
/// Secondaire : (note de classe /20 + composition /40) / 3. Primaire : la composition (/10).
double? moyenneMatiere({required bool primaire, double? noteClasse, double? noteComposition}) {
  if (primaire) return noteComposition;
  if (noteClasse == null || noteComposition == null) return null;
  return (noteClasse + noteComposition) / 3;
}

/// Statistiques d'une matière pour la classe.
class StatsMatiere {
  final int notes; // élèves ayant une moyenne
  final int effectif;
  final double? moyenne;
  final double? max;
  final double? min;
  final int sousLaMoyenne;

  const StatsMatiere({
    required this.notes,
    required this.effectif,
    this.moyenne,
    this.max,
    this.min,
    this.sousLaMoyenne = 0,
  });

  factory StatsMatiere.depuis(List<double?> moyennes, {required int bareme}) {
    final valeurs = moyennes.whereType<double>().where((v) => !v.isNaN).toList();
    if (valeurs.isEmpty) return StatsMatiere(notes: 0, effectif: moyennes.length);
    final somme = valeurs.fold<double>(0, (a, b) => a + b);
    return StatsMatiere(
      notes: valeurs.length,
      effectif: moyennes.length,
      moyenne: somme / valeurs.length,
      max: valeurs.reduce((a, b) => a > b ? a : b),
      min: valeurs.reduce((a, b) => a < b ? a : b),
      sousLaMoyenne: valeurs.where((v) => v < bareme / 2).length,
    );
  }
}
