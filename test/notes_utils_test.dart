import 'package:flutter_test/flutter_test.dart';
import 'package:bulletin_automatique/services/notes_utils.dart';

void main() {
  test('lecture des notes saisies', () {
    expect(lireNote(''), isNull);
    expect(lireNote('  '), isNull);
    expect(lireNote('12'), 12);
    expect(lireNote('12,5'), 12.5);
    expect(lireNote('12.75'), 12.75);
    expect(lireNote('abc')!.isNaN, isTrue);
  });

  test('contrôle des bornes', () {
    expect(erreurNote('', 20), isNull);
    expect(erreurNote('20', 20), isNull);
    expect(erreurNote('20,5', 20), 'Entre 0 et 20');
    expect(erreurNote('41', 40), 'Entre 0 et 40');
    expect(erreurNote('1..2', 20), 'Nombre invalide');
  });

  test('affichage court', () {
    expect(formatNote(12), '12');
    expect(formatNote(12.5), '12.5');
    expect(formatNote(37 / 3), '12.33');
  });

  test('moyenne de la matière (secondaire et primaire)', () {
    expect(moyenneMatiere(primaire: false, noteClasse: 15, noteComposition: 30), closeTo(15, 1e-9));
    expect(moyenneMatiere(primaire: false, noteClasse: 15, noteComposition: null), isNull);
    expect(moyenneMatiere(primaire: true, noteClasse: null, noteComposition: 7), 7);
  });

  test('statistiques de la classe pour une matière', () {
    final s = StatsMatiere.depuis([15, 8, null, 12, 4], bareme: 20);
    expect(s.effectif, 5);
    expect(s.notes, 4);
    expect(s.moyenne, closeTo(9.75, 1e-9));
    expect(s.max, 15);
    expect(s.min, 4);
    expect(s.sousLaMoyenne, 2);
    final vide = StatsMatiere.depuis([null, null], bareme: 20);
    expect(vide.notes, 0);
    expect(vide.moyenne, isNull);
  });
}
