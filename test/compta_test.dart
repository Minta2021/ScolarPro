import 'package:flutter_test/flutter_test.dart';
import 'package:bulletin_automatique/services/compta_utils.dart';
import 'package:bulletin_automatique/services/text_utils.dart';

SituationEleve situation({
  double fraisInsc = 10000,
  double fraisScol = 90000,
  double remise = 0,
  double payeInsc = 0,
  double payeScol = 0,
  int classeId = 1,
}) =>
    SituationEleve(
      eleveId: 1,
      nom: 'TRAORE',
      prenom: 'Awa',
      classeId: classeId,
      classeNom: '7ème A',
      fraisInscription: fraisInsc,
      fraisScolarite: fraisScol,
      remiseScolarite: remise,
      payeInscription: payeInsc,
      payeScolarite: payeScol,
    );

void main() {
  group('Montants', () {
    test('formatage avec séparateur de milliers', () {
      expect(formatMontant(0), '0');
      expect(formatMontant(999), '999');
      expect(formatMontant(1000), '1 000');
      expect(formatMontant(1250000), '1 250 000');
      expect(formatMontant(25000.4), '25 000');
      expect(formatFcfa(90000), '90 000 FCFA');
    });

    test('lecture des montants saisis', () {
      expect(parseMontant('25000'), 25000);
      expect(parseMontant('25 000'), 25000);
      expect(parseMontant('25 000 FCFA'), 25000);
      expect(parseMontant('25.000'), 25000);
      expect(parseMontant('1.250.000'), 1250000);
      expect(parseMontant('12,5'), 12.5);
      expect(parseMontant(''), isNull);
      expect(parseMontant('abc'), isNull);
    });

    test('nombre en lettres (orthographe traditionnelle)', () {
      const attendus = {
        0: 'zéro',
        1: 'un',
        17: 'dix-sept',
        21: 'vingt et un',
        71: 'soixante et onze',
        72: 'soixante-douze',
        80: 'quatre-vingts',
        81: 'quatre-vingt-un',
        91: 'quatre-vingt-onze',
        99: 'quatre-vingt-dix-neuf',
        100: 'cent',
        200: 'deux cents',
        201: 'deux cent un',
        1000: 'mille',
        1981: 'mille neuf cent quatre-vingt-un',
        21000: 'vingt et un mille',
        25000: 'vingt-cinq mille',
        80000: 'quatre-vingt mille',
        150000: 'cent cinquante mille',
        200000: 'deux cent mille',
        250500: 'deux cent cinquante mille cinq cents',
        1000000: 'un million',
        2500000: 'deux millions cinq cent mille',
        80000000: 'quatre-vingts millions',
        1000000000: 'un milliard',
      };
      attendus.forEach((n, texte) => expect(nombreEnLettres(n), texte, reason: '$n'));
      expect(montantEnLettres(25000), 'Vingt-cinq mille francs CFA');
    });
  });

  group('Statuts de paiement', () {
    test('calcul du statut', () {
      expect(calculerStatut(fraisBrut: 0, du: 0, paye: 0), StatutPaiement.nonDefini);
      expect(calculerStatut(fraisBrut: 90000, du: 0, paye: 0), StatutPaiement.exonere);
      expect(calculerStatut(fraisBrut: 90000, du: 90000, paye: 0), StatutPaiement.nonPaye);
      expect(calculerStatut(fraisBrut: 90000, du: 90000, paye: 30000), StatutPaiement.partiel);
      expect(calculerStatut(fraisBrut: 90000, du: 90000, paye: 90000), StatutPaiement.solde);
      expect(StatutPaiement.exonere.enRegle, isTrue);
      expect(StatutPaiement.partiel.enRegle, isFalse);
    });

    test('remise sur la scolarité', () {
      final s = situation(remise: 30000, payeScol: 60000, payeInsc: 10000);
      expect(s.duScolarite, 60000);
      expect(s.resteScolarite, 0);
      expect(s.statutScolarite, StatutPaiement.solde);
      expect(s.statutInscription, StatutPaiement.solde);
      expect(s.resteTotal, 0);
    });

    test('résumé : nombre d\'élèves qui ont payé', () {
      final resume = ResumeCompta.depuis([
        situation(payeInsc: 10000, payeScol: 90000), // tout payé
        situation(payeInsc: 10000, payeScol: 45000), // scolarité partielle
        situation(), // rien payé
        situation(fraisInsc: 0, fraisScol: 0, classeId: 2), // classe sans frais
      ]);
      expect(resume.effectif, 4);
      expect(resume.inscription.concernes, 3);
      expect(resume.inscription.enRegle, 2);
      expect(resume.inscription.nonPayes, 1);
      expect(resume.scolarite.enRegle, 1);
      expect(resume.scolarite.partiels, 1);
      expect(resume.scolarite.nonPayes, 1);
      expect(resume.scolarite.nonDefinis, 1);
      expect(resume.totalEncaisse, 10000 + 90000 + 10000 + 45000);
      expect(resume.totalReste, 0 + 45000 + 10000 + 90000);
    });
  });

  group('Comparaison des noms de classe', () {
    test('variantes d\'écriture reconnues', () {
      expect(cleClasse('7ème A'), cleClasse('7e A'));
      expect(cleClasse('7EME-A'), cleClasse('7ème A'));
      expect(cleClasse('1ère année'), cleClasse('1ere annee'));
      expect(cleClasse('Terminale SE'), 'terminalese');
      expect(cleClasse('7ème A') == cleClasse('7ème B'), isFalse);
      expect(cleEleve('TOURÉ', 'Sali'), cleEleve('Toure', 'sali'));
    });
  });
}
