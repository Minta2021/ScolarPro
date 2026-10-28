import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/eleve.dart';
import '../models/etablissement.dart';
import 'text_utils.dart';

/// Une couleur proposée pour les cartes.
class CouleurCarte {
  final String nom;
  final int argb;

  const CouleurCarte(this.nom, this.argb);

  PdfColor get pdf => PdfColor.fromInt(argb);
}

/// Réglages d'impression des cartes.
class OptionsCarte {
  final CouleurCarte couleur;
  final bool afficherPhoto;
  final bool verso;
  final String signataire;

  const OptionsCarte({
    required this.couleur,
    this.afficherPhoto = true,
    this.verso = false,
    this.signataire = 'Le Directeur',
  });

  static const List<CouleurCarte> couleurs = [
    CouleurCarte('Bleu canard', 0xFF007984),
    CouleurCarte('Bleu roi', 0xFF1E40AF),
    CouleurCarte('Vert', 0xFF15803D),
    CouleurCarte('Bordeaux', 0xFF9F1239),
    CouleurCarte('Orange', 0xFFC2410C),
    CouleurCarte('Anthracite', 0xFF1F2937),
  ];
}

/// Un élève à imprimer, avec le nom de sa classe.
class CarteEleve {
  final Eleve eleve;
  final String classeNom;

  const CarteEleve(this.eleve, this.classeNom);
}

/// Génération des cartes scolaires (format carte bancaire 85,6 × 54 mm).
class CarteScolaireService {
  CarteScolaireService._();

  // ── Dimensions d'une carte : strictement identiques au recto et au verso ──
  static const double largeurMm = 85.6;
  static const double hauteurMm = 54;

  // ── Planche A4 : 8 cartes au maximum (2 colonnes × 4 lignes) ──
  static const double pageLargeurMm = 210;
  static const double pageHauteurMm = 297;
  static const int colonnes = 2;
  static const int lignes = 4;
  static const int cartesParPage = colonnes * lignes;

  /// Espace blanc entre deux cartes voisines (horizontalement et verticalement).
  static const double ecartMm = 10;

  /// Marges calculées pour que la grille soit exactement centrée sur la feuille.
  /// C'est ce centrage qui garantit que le verso tombe pile derrière le recto.
  static const double margeXMm = (pageLargeurMm - (colonnes * largeurMm + (colonnes - 1) * ecartMm)) / 2;
  static const double margeYMm = (pageHauteurMm - (lignes * hauteurMm + (lignes - 1) * ecartMm)) / 2;

  // Bandeaux communs aux deux faces
  static const double _enteteMm = 13;
  static const double _piedMm = 5.5;

  static double get _w => largeurMm * PdfPageFormat.mm;
  static double get _h => hauteurMm * PdfPageFormat.mm;

  /// Position (en mm, depuis le coin haut-gauche de la feuille) de la case [index] d'une planche.
  ///
  /// Au verso, la position est le miroir horizontal exact de celle du recto : une fois la feuille
  /// retournée sur le bord long, le verso de chaque carte se trouve juste derrière son recto.
  static ({double x, double y}) positionCase(int index, {bool verso = false}) {
    final ligne = index ~/ colonnes;
    final colonne = index % colonnes;
    final x = margeXMm + colonne * (largeurMm + ecartMm);
    final y = margeYMm + ligne * (hauteurMm + ecartMm);
    return (x: verso ? pageLargeurMm - x - largeurMm : x, y: y);
  }

  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> _pdfTheme() async {
    if (_theme != null) return _theme!;
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
      _theme = pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold);
    } catch (_) {
      _theme = pw.ThemeData.base();
    }
    return _theme!;
  }

  static pw.ImageProvider? _image(String? path) {
    if (path == null || path.isEmpty) return null;
    try {
      final f = File(path);
      if (f.existsSync()) return pw.MemoryImage(f.readAsBytesSync());
    } catch (_) {}
    return null;
  }

  /// Référence unique de la carte : année de début + identifiant de l'élève.
  static String reference(CarteEleve c, String anneeScolaire) {
    final debut = RegExp(r'\d{4}').firstMatch(anneeScolaire)?.group(0) ?? '0000';
    return 'CS-$debut-${(c.eleve.id ?? 0).toString().padLeft(5, '0')}';
  }

  /// Texte contenu dans le QR code (lisible par n'importe quelle application de scan).
  static String donneesQr(CarteEleve c, Etablissement etab, String anneeScolaire) {
    final e = c.eleve;
    final lignesQr = <String>[
      'CARTE SCOLAIRE',
      'Ecole: ${etab.nom}',
      'Annee: $anneeScolaire',
      'Eleve: ${e.nom} ${e.prenom}',
      if (e.matricule != null && e.matricule!.isNotEmpty) 'Matricule: ${e.matricule}',
      'Classe: ${c.classeNom}',
      if (e.dateNaissance != null && e.dateNaissance!.isNotEmpty) 'Ne(e) le: ${e.dateNaissance}',
      if (e.telephoneParent != null && e.telephoneParent!.isNotEmpty) 'Tel. parent: ${e.telephoneParent}',
      if (etab.telephone != null && etab.telephone!.isNotEmpty) 'Tel. ecole: ${etab.telephone}',
      'Ref: ${reference(c, anneeScolaire)}',
    ];
    return retirerAccents(lignesQr.join('\n'));
  }

  // ════════════════════════════════════════════════════════════════
  // DESSIN D'UNE CARTE
  // ════════════════════════════════════════════════════════════════

  /// Cadre commun au recto et au verso : mêmes dimensions, même bordure, même bandeau
  /// supérieur et même pied de carte. Seul le contenu change d'une face à l'autre.
  static pw.Widget _cadre({
    required PdfColor couleur,
    required pw.Widget entete,
    required pw.Widget corps,
    required pw.Widget pied,
  }) {
    final mm = PdfPageFormat.mm;
    return pw.Container(
      width: _w,
      height: _h,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey500, width: 0.4),
        borderRadius: pw.BorderRadius.circular(2.5 * mm),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 2.5 * mm,
        verticalRadius: 2.5 * mm,
        child: pw.Column(
          children: [
            // ── Bandeau supérieur ──
            pw.Container(
              height: _enteteMm * mm,
              color: couleur,
              padding: pw.EdgeInsets.symmetric(horizontal: 2.5 * mm, vertical: 1.6 * mm),
              child: entete,
            ),
            // ── Corps ──
            pw.Expanded(
              child: pw.Padding(
                padding: pw.EdgeInsets.fromLTRB(2.5 * mm, 2.2 * mm, 2.5 * mm, 1 * mm),
                child: corps,
              ),
            ),
            // ── Pied de carte ──
            pw.Container(
              height: _piedMm * mm,
              padding: pw.EdgeInsets.symmetric(horizontal: 2.5 * mm),
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: couleur, width: 0.8)),
              ),
              child: pied,
            ),
          ],
        ),
      ),
    );
  }

  /// Logo et coordonnées de l'établissement (partie gauche du bandeau, identique sur les deux faces).
  static List<pw.Widget> _enteteEtablissement(Etablissement etab, pw.ImageProvider? logo, PdfColor couleur) {
    final mm = PdfPageFormat.mm;
    const blanc = PdfColors.white;
    return [
      pw.Container(
        width: 9.5 * mm,
        height: 9.5 * mm,
        padding: const pw.EdgeInsets.all(1.5),
        decoration: pw.BoxDecoration(color: blanc, borderRadius: pw.BorderRadius.circular(1.5 * mm)),
        child: logo != null
            ? pw.Image(logo, fit: pw.BoxFit.contain)
            : pw.Center(
                child: pw.Text(etab.nom.isNotEmpty ? etab.nom[0].toUpperCase() : 'E',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: couleur)),
              ),
      ),
      pw.SizedBox(width: 2 * mm),
      pw.Expanded(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(etab.nom.toUpperCase(),
                maxLines: 2, style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: blanc)),
            if ((etab.adresse ?? '').isNotEmpty || (etab.telephone ?? '').isNotEmpty)
              pw.Text(
                [etab.adresse ?? '', if ((etab.telephone ?? '').isNotEmpty) 'Tél. ${etab.telephone}']
                    .where((t) => t.isNotEmpty)
                    .join(' · '),
                maxLines: 1,
                style: const pw.TextStyle(fontSize: 4.8, color: PdfColors.grey200),
              ),
          ],
        ),
      ),
    ];
  }

  static pw.Widget _recto(
    CarteEleve c,
    Etablissement etab,
    String annee,
    OptionsCarte o,
    pw.ImageProvider? logo,
  ) {
    final mm = PdfPageFormat.mm;
    final couleur = o.couleur.pdf;
    final e = c.eleve;
    final photo = o.afficherPhoto ? _image(e.photoPath) : null;
    final initiales = '${e.nom.isNotEmpty ? e.nom[0] : ''}${e.prenom.isNotEmpty ? e.prenom[0] : ''}';
    const blanc = PdfColors.white;

    pw.Widget ligneInfo(String label, String valeur) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1.2),
          child: pw.RichText(
            maxLines: 1,
            text: pw.TextSpan(children: [
              pw.TextSpan(text: '$label : ', style: const pw.TextStyle(fontSize: 5.6, color: PdfColors.grey700)),
              pw.TextSpan(text: valeur, style: pw.TextStyle(fontSize: 6.2, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
        );

    return _cadre(
      couleur: couleur,
      entete: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          ..._enteteEtablissement(etab, logo, couleur),
          pw.SizedBox(width: 1.5 * mm),
          pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('CARTE SCOLAIRE', style: pw.TextStyle(fontSize: 6.6, fontWeight: pw.FontWeight.bold, color: blanc)),
              pw.SizedBox(height: 1),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: pw.BoxDecoration(color: blanc, borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Text(annee, style: pw.TextStyle(fontSize: 5.6, fontWeight: pw.FontWeight.bold, color: couleur)),
              ),
            ],
          ),
        ],
      ),
      corps: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Photo
          pw.Container(
            width: 19 * mm,
            height: 24 * mm,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: couleur, width: 0.8),
              borderRadius: pw.BorderRadius.circular(1.2 * mm),
            ),
            child: photo != null
                ? pw.ClipRRect(
                    horizontalRadius: 1.2 * mm,
                    verticalRadius: 1.2 * mm,
                    child: pw.Image(photo, fit: pw.BoxFit.cover, width: 19 * mm, height: 24 * mm),
                  )
                : pw.Center(
                    child: pw.Text(initiales.toUpperCase(),
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: couleur)),
                  ),
          ),
          pw.SizedBox(width: 2.5 * mm),
          // Identité
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(e.nom.toUpperCase(), maxLines: 1, style: pw.TextStyle(fontSize: 8.6, fontWeight: pw.FontWeight.bold)),
                pw.Text(e.prenom, maxLines: 1, style: const pw.TextStyle(fontSize: 7.4, color: PdfColors.grey900)),
                pw.SizedBox(height: 1.6 * mm),
                ligneInfo('Classe', c.classeNom),
                ligneInfo('Matricule', (e.matricule ?? '').isEmpty ? '—' : e.matricule!),
                if ((e.dateNaissance ?? '').isNotEmpty) ligneInfo('Né(e) le', e.dateNaissance!),
                if ((e.telephoneParent ?? '').isNotEmpty) ligneInfo('Tél. parent', e.telephoneParent!),
              ],
            ),
          ),
          pw.SizedBox(width: 1.5 * mm),
          // QR code
          pw.Column(
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: donneesQr(c, etab, annee),
                width: 19 * mm,
                height: 19 * mm,
                drawText: false,
              ),
              pw.SizedBox(height: 0.8 * mm),
              pw.Text(reference(c, annee), style: const pw.TextStyle(fontSize: 4.6, color: PdfColors.grey700)),
            ],
          ),
        ],
      ),
      pied: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Valable pour l\'année scolaire $annee', style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700)),
          pw.Text('${o.signataire} : ..................',
              style: pw.TextStyle(fontSize: 5.2, fontWeight: pw.FontWeight.bold, color: couleur)),
        ],
      ),
    );
  }

  static pw.Widget _verso(
    CarteEleve c,
    Etablissement etab,
    String annee,
    OptionsCarte o,
    pw.ImageProvider? logo,
  ) {
    final mm = PdfPageFormat.mm;
    final couleur = o.couleur.pdf;
    final telParent = c.eleve.telephoneParent ?? '';

    return _cadre(
      couleur: couleur,
      entete: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: _enteteEtablissement(etab, logo, couleur),
      ),
      corps: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text('Cette carte est strictement personnelle.',
              style: pw.TextStyle(fontSize: 6.6, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 0.8 * mm),
          pw.Text(
            "Elle doit être présentée à toute demande du personnel de l'établissement "
            "et reste valable uniquement pour l'année scolaire $annee.",
            style: const pw.TextStyle(fontSize: 5.8),
          ),
          pw.Spacer(),
          pw.Container(
            padding: pw.EdgeInsets.fromLTRB(2 * mm, 1.2 * mm, 2 * mm, 1.2 * mm),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border(left: pw.BorderSide(color: couleur, width: 2)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('En cas de perte, merci de la rapporter à :',
                    style: const pw.TextStyle(fontSize: 5.6, color: PdfColors.grey800)),
                pw.SizedBox(height: 0.6 * mm),
                pw.Text(etab.nom,
                    maxLines: 2, style: pw.TextStyle(fontSize: 6.4, fontWeight: pw.FontWeight.bold, color: couleur)),
                if ((etab.adresse ?? '').isNotEmpty)
                  pw.Text(etab.adresse!, maxLines: 1, style: const pw.TextStyle(fontSize: 5.6)),
                if ((etab.telephone ?? '').isNotEmpty)
                  pw.Text('Tél. : ${etab.telephone}', style: const pw.TextStyle(fontSize: 5.6)),
              ],
            ),
          ),
          pw.SizedBox(height: 1 * mm),
        ],
      ),
      pied: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            telParent.isNotEmpty ? 'Contact du parent : $telParent' : 'Valable pour l\'année scolaire $annee',
            style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700),
          ),
          pw.Text('Réf. ${reference(c, annee)}',
              style: pw.TextStyle(fontSize: 5.2, fontWeight: pw.FontWeight.bold, color: couleur)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // DOCUMENTS
  // ════════════════════════════════════════════════════════════════

  /// Traits de coupe dans les marges, dans le prolongement des bords de chaque carte.
  /// La grille étant centrée, ils sont au même endroit au recto et au verso.
  static List<pw.Widget> _traitsDeCoupe() {
    final mm = PdfPageFormat.mm;
    const longueurMm = 5.0;
    const retraitMm = 2.0; // espace laissé entre le trait et la carte
    const epaisseur = 0.35; // en points
    const couleur = PdfColors.grey600;

    pw.Widget trait({required double x, required double y, required double largeur, required double hauteur}) =>
        pw.Positioned(left: x, top: y, child: pw.Container(width: largeur, height: hauteur, color: couleur));

    final traits = <pw.Widget>[];
    // Traits verticaux, en haut et en bas de la feuille
    for (var col = 0; col < colonnes; col++) {
      final gauche = positionCase(col).x;
      for (final x in [gauche, gauche + largeurMm]) {
        for (final y in [margeYMm - retraitMm - longueurMm, pageHauteurMm - margeYMm + retraitMm]) {
          traits.add(trait(x: x * mm - epaisseur / 2, y: y * mm, largeur: epaisseur, hauteur: longueurMm * mm));
        }
      }
    }
    // Traits horizontaux, à gauche et à droite de la feuille
    for (var ligne = 0; ligne < lignes; ligne++) {
      final haut = positionCase(ligne * colonnes).y;
      for (final y in [haut, haut + hauteurMm]) {
        for (final x in [margeXMm - retraitMm - longueurMm, pageLargeurMm - margeXMm + retraitMm]) {
          traits.add(trait(x: x * mm, y: y * mm - epaisseur / 2, largeur: longueurMm * mm, hauteur: epaisseur));
        }
      }
    }
    return traits;
  }

  /// Planches A4 prêtes à imprimer et découper : 8 cartes au maximum par page (2 × 4),
  /// grille centrée au millimètre, traits de coupe dans les marges.
  /// Avec le verso, chaque page recto est suivie de sa page verso, où chaque carte est placée
  /// au miroir exact de son recto (impression recto-verso, retournement sur le bord long).
  static Future<Uint8List> genererPlanches({
    required Etablissement etablissement,
    required String anneeScolaire,
    required List<CarteEleve> cartes,
    required OptionsCarte options,
  }) async {
    final doc = pw.Document(theme: await _pdfTheme(), title: 'Cartes scolaires $anneeScolaire');
    final logo = _image(etablissement.logoPath);
    final mm = PdfPageFormat.mm;

    pw.Page planche(List<pw.Widget> faces, {required bool verso}) => pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              ..._traitsDeCoupe(),
              for (var i = 0; i < faces.length; i++)
                pw.Positioned(
                  left: positionCase(i, verso: verso).x * mm,
                  top: positionCase(i, verso: verso).y * mm,
                  child: faces[i],
                ),
            ],
          ),
        );

    for (var debut = 0; debut < cartes.length; debut += cartesParPage) {
      final groupe = cartes.skip(debut).take(cartesParPage).toList();
      doc.addPage(planche(
        [for (final c in groupe) _recto(c, etablissement, anneeScolaire, options, logo)],
        verso: false,
      ));
      if (options.verso) {
        doc.addPage(planche(
          [for (final c in groupe) _verso(c, etablissement, anneeScolaire, options, logo)],
          verso: true,
        ));
      }
    }
    return doc.save();
  }

  /// Une seule carte (page au format de la carte) : sert à l'aperçu à l'écran.
  static Future<Uint8List> genererApercu({
    required Etablissement etablissement,
    required String anneeScolaire,
    required CarteEleve carte,
    required OptionsCarte options,
    bool verso = false,
  }) async {
    final doc = pw.Document(theme: await _pdfTheme());
    final logo = _image(etablissement.logoPath);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(_w, _h),
      margin: pw.EdgeInsets.zero,
      build: (_) => verso
          ? _verso(carte, etablissement, anneeScolaire, options, logo)
          : _recto(carte, etablissement, anneeScolaire, options, logo),
    ));
    return doc.save();
  }
}
