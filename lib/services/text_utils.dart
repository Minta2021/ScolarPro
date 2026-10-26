/// Petites fonctions de comparaison de textes (noms d'élèves, noms de classes, en-têtes Excel).
library;

const Map<String, String> _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ç': 'c', 'ñ': 'n', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
};

/// Minuscules sans accents.
String sansAccents(String s) {
  final buffer = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    buffer.write(_accents[ch] ?? ch);
  }
  return buffer.toString();
}

/// Minuscules, sans accents, uniquement lettres et chiffres : "Prénom(s)" → "prenoms".
String normaliser(String s) => sansAccents(s).replaceAll(RegExp(r'[^a-z0-9]'), '');

final RegExp _ordinal = RegExp(r'(\d+)\s*(iemes?|emes?|ere|er|re|e|em)(?![a-z])');

/// Clé de comparaison des noms de classe : "7ème A", "7e A" et "7EME-A" donnent tous "7a".
String cleClasse(String nom) {
  final t = sansAccents(nom).replaceAllMapped(_ordinal, (m) => m.group(1)!);
  return t.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Clé de comparaison d'un élève (nom + prénom, sans accents ni espaces).
String cleEleve(String nom, String prenom) => '${normaliser(nom)}|${normaliser(prenom)}';

const Map<String, String> _accentsMajMin = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A', 'Ã': 'A',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i', 'Î': 'I', 'Ï': 'I', 'Í': 'I', 'Ì': 'I',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', 'Ô': 'O', 'Ö': 'O', 'Ó': 'O', 'Ò': 'O', 'Õ': 'O',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ú': 'U',
  'ç': 'c', 'Ç': 'C', 'ñ': 'n', 'Ñ': 'N', 'ÿ': 'y', 'Ÿ': 'Y',
  'œ': 'oe', 'Œ': 'OE', 'æ': 'ae', 'Æ': 'AE', '’': "'", '«': '"', '»': '"', '—': '-', '–': '-',
};

/// Retire les accents en conservant les majuscules : "Élève TRAORÉ" → "Eleve TRAORE".
/// Utilisé pour les QR codes, lisibles ainsi par tous les lecteurs.
String retirerAccents(String s) {
  final buffer = StringBuffer();
  for (final ch in s.split('')) {
    buffer.write(_accentsMajMin[ch] ?? ch);
  }
  return buffer.toString();
}
