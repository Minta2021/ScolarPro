import 'package:flutter_test/flutter_test.dart';
import 'package:bulletin_automatique/models/note.dart';
import 'package:bulletin_automatique/providers/app_state_provider.dart';

void main() {
  group('Note.moyenneCours', () {
    Note note(double? classe, double? compo) => Note(
          eleveId: 1,
          coursId: 1,
          trimestre: 1,
          noteClasse: classe,
          noteComposition: compo,
        );

    test('classe /20 + composition /40, divisé par 3', () {
      // Équivaut à (classe + compo/20 × 2) / 3
      expect(note(15, 30).moyenneCours, closeTo(15, 1e-9));
      expect(note(12, 36).moyenneCours, closeTo(16, 1e-9));
      expect(note(20, 40).moyenneCours, closeTo(20, 1e-9));
      expect(note(0, 0).moyenneCours, 0);
    });

    test('retourne null si une note manque', () {
      expect(note(null, 30).moyenneCours, isNull);
      expect(note(15, null).moyenneCours, isNull);
    });
  });

  group('getMention', () {
    test('seuils des mentions', () {
      expect(AppStateProvider.getMention(9.99), 'Insuffisant');
      expect(AppStateProvider.getMention(10), 'Passable');
      expect(AppStateProvider.getMention(12), 'Assez Bien');
      expect(AppStateProvider.getMention(14), 'Bien');
      expect(AppStateProvider.getMention(16), 'Très Bien');
      expect(AppStateProvider.getMention(18), 'Excellent');
    });
  });
}
