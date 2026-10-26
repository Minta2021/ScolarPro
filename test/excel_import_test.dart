import 'package:excel/excel.dart' as ex;
import 'package:flutter_test/flutter_test.dart';
import 'package:bulletin_automatique/models/eleve.dart';
import 'package:bulletin_automatique/services/excel_import_service.dart';

List<int> _xlsx(List<List<ex.CellValue?>> rows) {
  final excel = ex.Excel.createExcel();
  final sheet = excel['Sheet1'];
  for (final row in rows) {
    sheet.appendRow(row);
  }
  return excel.encode()!;
}

ex.TextCellValue t(String s) => ex.TextCellValue(s);

void main() {
  mainImportEcole();

  test('le modèle vierge est reconnu et ne contient aucun élève', () {
    final result = ExcelImportService.parse(ExcelImportService.buildTemplate()!);
    expect(result.erreur, isNull);
    expect(result.rows, isEmpty);
  });

  test('colonnes séparées, dans le désordre, avec titre au-dessus et dates', () {
    final bytes = _xlsx([
      [t('Liste des élèves 6e A')],
      [t('N° Matricule'), t('PRÉNOMS'), t('Nom'), t('Date de Naissance')],
      [t('M001'), t('Awa'), t('Traoré'), ex.DateCellValue(year: 2012, month: 3, day: 5)],
      [ex.IntCellValue(1002), t('Moussa'), t('Keita'), t('7/11/2011')],
      [null, null, null, null],
      [t('M003'), t('Fatoumata'), t('Diallo'), null],
    ]);
    final result = ExcelImportService.parse(bytes);

    expect(result.erreur, isNull);
    expect(result.valides.length, 3);
    final awa = result.rows[0];
    expect(awa.nom, 'TRAORÉ');
    expect(awa.prenom, 'Awa');
    expect(awa.matricule, 'M001');
    expect(awa.dateNaissance, '05/03/2012');
    expect(awa.ligne, 3);
    expect(result.rows[1].matricule, '1002');
    expect(result.rows[1].dateNaissance, '07/11/2011');
    expect(result.rows[2].dateNaissance, isNull);
  });

  test('colonne unique « Nom & Prénom » (format de l\'export)', () {
    final bytes = _xlsx([
      [t('Nom & Prénom'), t('Matricule'), t('Date de Naissance')],
      [t('COULIBALY Aminata Sira'), t('N/A'), t('N/A')],
    ]);
    final row = ExcelImportService.parse(bytes).rows.single;
    expect(row.nom, 'COULIBALY');
    expect(row.prenom, 'Aminata Sira');
    expect(row.matricule, isNull);
    expect(row.dateNaissance, isNull);
    expect(row.valide, isTrue);
  });

  test('lignes incomplètes, doublons et élèves déjà inscrits sont ignorés', () {
    final bytes = _xlsx([
      [t('Nom'), t('Prénom'), t('Matricule')],
      [t('Sangaré'), null, null],
      [t('Diarra'), t('Ibrahim'), t('M10')],
      [t('diarra'), t('ibrahim'), null],
      [t('Cissé'), t('Oumar'), t('m20')],
      [t('Touré'), t('Sali'), null],
    ]);
    final existants = [
      Eleve(id: 1, nom: 'TOURE', prenom: 'Sali', classeId: 1),
      Eleve(id: 2, nom: 'BAH', prenom: 'Ali', classeId: 1, matricule: 'M20'),
    ];
    final rows = ExcelImportService.parse(bytes, existants: existants).rows;

    expect(rows[0].probleme, 'Prénom manquant');
    expect(rows[1].valide, isTrue);
    expect(rows[2].probleme, 'Doublon dans le fichier');
    expect(rows[3].probleme, 'Matricule déjà utilisé dans la classe');
    expect(rows[4].probleme, 'Élève déjà inscrit dans la classe');
  });

  test('fichier sans en-tête reconnu ou illisible', () {
    final noHeader = _xlsx([
      [t('Moussa'), t('Keita')],
    ]);
    expect(ExcelImportService.parse(noHeader).erreur, isNotNull);
    expect(ExcelImportService.parse([1, 2, 3, 4]).erreur, isNotNull);
  });
}

void mainImportEcole() {
  group('Import de toute l\'école', () {
    test('colonne Classe, téléphone parent, colonnes à ignorer', () {
      final bytes = _xlsx([
        [t('N°'), t('Prénoms'), t('Nom'), t('Lieu de naissance'), t('Né(e) le'), t('Classe'), t('Prénom du père'), t('Contact parent')],
        [ex.IntCellValue(1), t('Awa'), t('Traoré'), t('Bandiagara'), t('05/03/2012'), t('7ème A'), t('Moussa'), ex.IntCellValue(76123456)],
        [ex.IntCellValue(2), t('Ali'), t('Bah'), t('Mopti'), t('2011-11-07'), t('8e B'), t('Sékou'), null],
      ]);
      final wb = ExcelImportService.lireFichier(bytes, nomFichier: 'liste.xlsx');
      expect(wb.erreur, isNull);
      final sheet = wb.feuilles.single;
      final entete = ExcelImportService.detecterLigneEntete(sheet);
      expect(entete, 0);
      final mapping = ExcelImportService.detecterColonnes(sheet.lignes[entete!]);
      expect(mapping[ImportField.prenom], 1);
      expect(mapping[ImportField.nom], 2);
      expect(mapping[ImportField.dateNaissance], 4);
      expect(mapping[ImportField.classe], 5);
      expect(mapping[ImportField.telephoneParent], 7);
      final rows = ExcelImportService.extraireLignes(sheet, ligneEntete: entete, mapping: mapping);
      expect(rows.length, 2);
      expect(rows[0].classe, '7ème A');
      expect(rows[0].dateNaissance, '05/03/2012');
      expect(rows[0].telephoneParent, '76123456');
      expect(rows[1].dateNaissance, '07/11/2011');
      expect(rows[1].classe, '8e B');
    });

    test('fichier CSV (séparateur ;) avec guillemets et accents Windows', () {
      const csv = 'Nom;Prénom;Classe\r\n"DIALLO";"Fatoumata";"6ème A"\r\nKEITA;"Moussa ""Junior""";6ème A\r\n';
      final wb = ExcelImportService.lireFichier(csv.codeUnits, nomFichier: 'eleves.csv'); // latin1
      expect(wb.erreur, isNull);
      final sheet = wb.feuilles.single;
      final entete = ExcelImportService.detecterLigneEntete(sheet)!;
      final rows = ExcelImportService.extraireLignes(
        sheet,
        ligneEntete: entete,
        mapping: ExcelImportService.detecterColonnes(sheet.lignes[entete]),
      );
      expect(rows.length, 2);
      expect(rows[0].prenom, 'Fatoumata');
      expect(rows[0].classe, '6ème A');
      expect(rows[1].prenom, 'Moussa "Junior"');
    });

    test('nom complet : le mot en MAJUSCULES est le nom', () {
      expect(ExcelImportService.separerNomComplet('Aminata Sira COULIBALY', OrdreNomComplet.auto),
          ('COULIBALY', 'Aminata Sira'));
      expect(ExcelImportService.separerNomComplet('Coulibaly Aminata', OrdreNomComplet.auto), ('Coulibaly', 'Aminata'));
      expect(ExcelImportService.separerNomComplet('Aminata Coulibaly', OrdreNomComplet.prenomPuisNom),
          ('Coulibaly', 'Aminata'));
    });

    test('une seule colonne « Nom » = nom complet', () {
      final mapping = ExcelImportService.detecterColonnes([const ImportCell('Nom'), const ImportCell('Classe')]);
      expect(mapping[ImportField.nomPrenom], 0);
      expect(mapping[ImportField.nom], isNull);
    });

    test('ancien format .xls refusé avec un message clair', () {
      final wb = ExcelImportService.lireFichier([0xD0, 0xCF, 0x11, 0xE0, 0, 0], nomFichier: 'liste.xls');
      expect(wb.erreur, contains('.xlsx'));
    });

    test('plusieurs feuilles : une feuille par classe', () {
      final excel = ex.Excel.createExcel();
      excel.rename('Sheet1', '7ème A');
      excel['7ème A'].appendRow([t('Nom'), t('Prénom')]);
      excel['7ème A'].appendRow([t('Cissé'), t('Oumar')]);
      excel['8ème B'].appendRow([t('Nom'), t('Prénom')]);
      excel['8ème B'].appendRow([t('Sow'), t('Aïcha')]);
      final wb = ExcelImportService.lireFichier(excel.encode()!, nomFichier: 'ecole.xlsx');
      expect(wb.feuilles.length, 2);
      final noms = wb.feuilles.map((f) => f.nom).toSet();
      expect(noms, {'7ème A', '8ème B'});
    });

    test('doublons : même nom autorisé dans deux classes différentes', () {
      final rows = [
        const ImportedEleveRow(ligne: 2, nom: 'DIARRA', prenom: 'Ibrahim', classe: '7A'),
        const ImportedEleveRow(ligne: 3, nom: 'DIARRA', prenom: 'Ibrahim', classe: '8A'),
        const ImportedEleveRow(ligne: 4, nom: 'DIARRA', prenom: 'Ibrahim', classe: '7A'),
      ];
      final res = ExcelImportService.marquerDoublons(rows, cible: (r) => r.classe!);
      expect(res[0].valide, isTrue);
      expect(res[1].valide, isTrue);
      expect(res[2].probleme, 'Doublon dans le fichier');
    });
  });
}
