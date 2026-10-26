import 'package:flutter_test/flutter_test.dart';
import 'package:bulletin_automatique/models/eleve.dart';
import 'package:bulletin_automatique/models/etablissement.dart';
import 'package:bulletin_automatique/models/paiement.dart';
import 'package:bulletin_automatique/services/carte_scolaire_service.dart';
import 'package:bulletin_automatique/services/compta_utils.dart';
import 'package:bulletin_automatique/services/pdf_service.dart';
import 'package:bulletin_automatique/services/text_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final etab = Etablissement(
    nom: 'Complexe Scolaire Les Étoiles de Bandiagara',
    adresse: 'Quartier Administratif, Bandiagara',
    telephone: '76 00 00 00',
    anneeScolaire: '2026-2027',
  );

  CarteEleve carte(int id) => CarteEleve(
        Eleve(
          id: id,
          nom: 'TRAORÉ',
          prenom: 'Aïssata Fatoumata',
          classeId: 1,
          matricule: 'M${id.toString().padLeft(3, '0')}',
          dateNaissance: '05/03/2012',
          telephoneParent: '76 12 34 56',
        ),
        '7ème Année A',
      );

  test('accents retirés en conservant les majuscules', () {
    expect(retirerAccents('Élève TRAORÉ, né à Ségou'), 'Eleve TRAORE, ne a Segou');
  });

  test('contenu du QR code et référence de la carte', () {
    final qr = CarteScolaireService.donneesQr(carte(12), etab, '2026-2027');
    expect(qr, contains('CARTE SCOLAIRE'));
    expect(qr, contains('Eleve: TRAORE Aissata Fatoumata'));
    expect(qr, contains('Classe: 7eme Annee A'));
    expect(qr, contains('Matricule: M012'));
    expect(qr, contains('Ref: CS-2026-00012'));
    expect(qr.contains('é'), isFalse);
  });

  test('planches A4 : 12 cartes recto-verso sans erreur de mise en page', () async {
    final bytes = await CarteScolaireService.genererPlanches(
      etablissement: etab,
      anneeScolaire: '2026-2027',
      cartes: [for (var i = 1; i <= 12; i++) carte(i)],
      options: const OptionsCarte(couleur: CouleurCarte('Bleu canard', 0xFF007984), verso: true),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('aperçu d\'une carte (recto et verso)', () async {
    for (final verso in [false, true]) {
      final bytes = await CarteScolaireService.genererApercu(
        etablissement: etab,
        anneeScolaire: '2026-2027',
        carte: carte(1),
        options: OptionsCarte(couleur: OptionsCarte.couleurs[2]),
        verso: verso,
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });

  test('reçu regroupant inscription et scolarité', () async {
    Paiement p(String type, double montant) => Paiement(
          id: 1,
          eleveId: 1,
          type: type,
          montant: montant,
          datePaiement: '2026-10-25',
          mode: 'Orange Money',
          numeroRecu: 'REC-000001',
          observation: '1ère tranche',
          eleveNom: 'TRAORÉ',
          elevePrenom: 'Aïssata',
          eleveMatricule: 'M001',
          classeNom: '7ème A',
        );
    final bytes = await PDFService.buildRecu(
      etablissement: etab,
      anneeScolaire: '2026-2027',
      paiements: [p(Paiement.typeInscription, 10000), p(Paiement.typeScolarite, 45000)],
      situation: const SituationEleve(
        eleveId: 1,
        nom: 'TRAORÉ',
        prenom: 'Aïssata',
        classeId: 1,
        classeNom: '7ème A',
        fraisInscription: 10000,
        fraisScolarite: 90000,
        remiseScolarite: 0,
        payeInscription: 10000,
        payeScolarite: 45000,
      ),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
