import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
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

  group('planches A4 : 8 cartes par feuille, recto et verso coordonnés', () {
    const largeurPage = CarteScolaireService.pageLargeurMm;
    const hauteurPage = CarteScolaireService.pageHauteurMm;
    const largeur = CarteScolaireService.largeurMm;
    const hauteur = CarteScolaireService.hauteurMm;
    const parPage = CarteScolaireService.cartesParPage;

    int nbPages(Uint8List pdf) =>
        RegExp(r'/Type\s*/Page(?![a-zA-Z])').allMatches(String.fromCharCodes(pdf)).length;

    test('8 cartes au maximum par feuille (2 colonnes × 4 lignes)', () {
      expect(parPage, 8);
      expect(CarteScolaireService.colonnes, 2);
      expect(CarteScolaireService.lignes, 4);
    });

    test('grille centrée au millimètre et marges imprimables', () {
      final premiere = CarteScolaireService.positionCase(0);
      final derniere = CarteScolaireService.positionCase(parPage - 1);
      final margeDroite = largeurPage - (derniere.x + largeur);
      final margeBas = hauteurPage - (derniere.y + hauteur);
      expect(premiere.x, closeTo(margeDroite, 1e-9));
      expect(premiere.y, closeTo(margeBas, 1e-9));
      // Les imprimantes ne savent pas imprimer au ras du bord : on garde au moins 10 mm
      expect(premiere.x, greaterThanOrEqualTo(10));
      expect(premiere.y, greaterThanOrEqualTo(10));
    });

    test('chaque verso tombe exactement derrière son recto (retournement sur le bord long)', () {
      for (var i = 0; i < parPage; i++) {
        final recto = CarteScolaireService.positionCase(i);
        final verso = CarteScolaireService.positionCase(i, verso: true);
        // Feuille retournée sur le bord long : x devient (largeur de la feuille − x − largeur de la carte)
        final versoRetourne = largeurPage - verso.x - largeur;
        expect(versoRetourne, closeTo(recto.x, 1e-9), reason: 'carte $i');
        expect(verso.y, closeTo(recto.y, 1e-9), reason: 'carte $i');
      }
    });

    test('aucune carte ne chevauche sa voisine', () {
      for (var i = 0; i < parPage; i++) {
        for (var j = i + 1; j < parPage; j++) {
          final a = CarteScolaireService.positionCase(i);
          final b = CarteScolaireService.positionCase(j);
          final separeesX = a.x + largeur <= b.x || b.x + largeur <= a.x;
          final separeesY = a.y + hauteur <= b.y || b.y + hauteur <= a.y;
          expect(separeesX || separeesY, isTrue, reason: 'cartes $i et $j');
        }
      }
    });

    test('9 cartes : 2 feuilles recto (+ 2 feuilles verso si demandé)', () async {
      Future<Uint8List> generer(bool verso) => CarteScolaireService.genererPlanches(
            etablissement: etab,
            anneeScolaire: '2026-2027',
            cartes: [for (var i = 1; i <= 9; i++) carte(i)],
            options: OptionsCarte(couleur: OptionsCarte.couleurs.first, verso: verso),
          );
      final sansVerso = await generer(false);
      final avecVerso = await generer(true);
      expect(String.fromCharCodes(avecVerso.take(4)), '%PDF');
      expect(nbPages(sansVerso), 2);
      expect(nbPages(avecVerso), 4);
    });

    test('aperçu : recto et verso ont exactement les mêmes dimensions (85,6 × 54 mm)', () async {
      String mediaBox(Uint8List pdf) => RegExp(r'/MediaBox\s*\[[^\]]*\]').firstMatch(String.fromCharCodes(pdf))!.group(0)!;
      final faces = <String>[];
      for (final verso in [false, true]) {
        final bytes = await CarteScolaireService.genererApercu(
          etablissement: etab,
          anneeScolaire: '2026-2027',
          carte: carte(1),
          options: OptionsCarte(couleur: OptionsCarte.couleurs[2]),
          verso: verso,
        );
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        faces.add(mediaBox(bytes));
      }
      expect(faces[0], faces[1]);
      final valeurs = RegExp(r'[\d.]+').allMatches(faces[0]).map((m) => double.parse(m.group(0)!)).toList();
      expect(valeurs[2] / PdfPageFormat.mm, closeTo(largeur, 0.01));
      expect(valeurs[3] / PdfPageFormat.mm, closeTo(hauteur, 0.01));
    });
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
