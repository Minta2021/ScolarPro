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

  static const double largeurMm = 85.6;
  static const double hauteurMm = 54;
  static const int colonnes = 2;
  static const int lignes = 5;
  static const int cartesParPage = colonnes * lignes;

  static double get _w => largeurMm * PdfPageFormat.mm;
  static double get _h => hauteurMm * PdfPageFormat.mm;

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
              height: 13 * mm,
              color: couleur,
              padding: pw.EdgeInsets.symmetric(horizontal: 2.5 * mm, vertical: 1.6 * mm),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
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
                            maxLines: 2,
                            style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: blanc)),
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
                  pw.SizedBox(width: 1.5 * mm),
                  pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('CARTE SCOLAIRE',
                          style: pw.TextStyle(fontSize: 6.6, fontWeight: pw.FontWeight.bold, color: blanc)),
                      pw.SizedBox(height: 1),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: pw.BoxDecoration(color: blanc, borderRadius: pw.BorderRadius.circular(3)),
                        child: pw.Text(annee,
                            style: pw.TextStyle(fontSize: 5.6, fontWeight: pw.FontWeight.bold, color: couleur)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Corps ──
            pw.Expanded(
              child: pw.Padding(
                padding: pw.EdgeInsets.fromLTRB(2.5 * mm, 2.2 * mm, 2.5 * mm, 1 * mm),
                child: pw.Row(
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
                          pw.Text(e.nom.toUpperCase(),
                              maxLines: 1, style: pw.TextStyle(fontSize: 8.6, fontWeight: pw.FontWeight.bold)),
                          pw.Text(e.prenom,
                              maxLines: 1, style: const pw.TextStyle(fontSize: 7.4, color: PdfColors.grey900)),
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
              ),
            ),

            // ── Pied de carte ──
            pw.Container(
              height: 5.5 * mm,
              padding: pw.EdgeInsets.symmetric(horizontal: 2.5 * mm),
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: couleur, width: 0.8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Valable pour l\'année scolaire $annee',
                      style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700)),
                  pw.Text('${o.signataire} : ..................',
                      style: pw.TextStyle(fontSize: 5.2, fontWeight: pw.FontWeight.bold, color: couleur)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _verso(CarteEleve c, Etablissement etab, String annee, OptionsCarte o) {
    final mm = PdfPageFormat.mm;
    final couleur = o.couleur.pdf;
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
            pw.Container(
              height: 7 * mm,
              color: couleur,
              alignment: pw.Alignment.center,
              child: pw.Text(etab.nom.toUpperCase(),
                  maxLines: 1, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ),
            pw.Expanded(
              child: pw.Padding(
                padding: pw.EdgeInsets.all(3 * mm),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Cette carte est strictement personnelle.',
                        style: pw.TextStyle(fontSize: 6.4, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 1 * mm),
                    pw.Text(
                      "Elle doit être présentée à toute demande du personnel de l'établissement "
                      "et reste valable uniquement pour l'année scolaire $annee.",
                      style: const pw.TextStyle(fontSize: 5.6),
                    ),
                    pw.SizedBox(height: 2 * mm),
                    pw.Text('En cas de perte, merci de la rapporter à :',
                        style: const pw.TextStyle(fontSize: 5.6, color: PdfColors.grey800)),
                    pw.SizedBox(height: 0.8 * mm),
                    pw.Text(etab.nom, style: pw.TextStyle(fontSize: 6.4, fontWeight: pw.FontWeight.bold, color: couleur)),
                    if ((etab.adresse ?? '').isNotEmpty) pw.Text(etab.adresse!, style: const pw.TextStyle(fontSize: 5.6)),
                    if ((etab.telephone ?? '').isNotEmpty)
                      pw.Text('Tél. : ${etab.telephone}', style: const pw.TextStyle(fontSize: 5.6)),
                    pw.Spacer(),
                    if ((c.eleve.telephoneParent ?? '').isNotEmpty)
                      pw.Text('Contact du parent : ${c.eleve.telephoneParent}',
                          style: pw.TextStyle(fontSize: 5.8, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Réf. ${reference(c, annee)}', style: const pw.TextStyle(fontSize: 4.8, color: PdfColors.grey600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // DOCUMENTS
  // ════════════════════════════════════════════════════════════════

  /// Planches A4 prêtes à imprimer et découper : 10 cartes par page (2 × 5).
  /// Avec le verso, chaque page recto est suivie de sa page verso, disposée en miroir
  /// pour une impression recto-verso (retournement sur le bord long).
  static Future<Uint8List> genererPlanches({
    required Etablissement etablissement,
    required String anneeScolaire,
    required List<CarteEleve> cartes,
    required OptionsCarte options,
  }) async {
    final doc = pw.Document(theme: await _pdfTheme(), title: 'Cartes scolaires $anneeScolaire');
    final logo = _image(etablissement.logoPath);
    final mm = PdfPageFormat.mm;
    const ecartX = 4.0;
    const ecartY = 3.0;
    // 1 point de marge de sécurité pour les arrondis de calcul
    final margeX = (210 - (colonnes * largeurMm + (colonnes - 1) * ecartX)) / 2 * mm - 1;
    final margeY = (297 - (lignes * hauteurMm + (lignes - 1) * ecartY)) / 2 * mm - 1;

    pw.Widget planche(List<pw.Widget?> cases) {
      return pw.Column(
        children: [
          for (var r = 0; r < lignes; r++) ...[
            if (r > 0) pw.SizedBox(height: ecartY * mm),
            pw.Row(
              children: [
                for (var col = 0; col < colonnes; col++) ...[
                  if (col > 0) pw.SizedBox(width: ecartX * mm),
                  cases[r * colonnes + col] ?? pw.SizedBox(width: _w, height: _h),
                ],
              ],
            ),
          ],
        ],
      );
    }

    for (var debut = 0; debut < cartes.length; debut += cartesParPage) {
      final groupe = cartes.skip(debut).take(cartesParPage).toList();
      final recto = List<pw.Widget?>.filled(cartesParPage, null);
      final verso = List<pw.Widget?>.filled(cartesParPage, null);
      for (var i = 0; i < groupe.length; i++) {
        recto[i] = _recto(groupe[i], etablissement, anneeScolaire, options, logo);
        // Miroir horizontal : la carte de gauche au recto se retrouve à droite au verso
        final r = i ~/ colonnes;
        final col = i % colonnes;
        verso[r * colonnes + (colonnes - 1 - col)] = _verso(groupe[i], etablissement, anneeScolaire, options);
      }
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.symmetric(horizontal: margeX, vertical: margeY),
        build: (_) => planche(recto),
      ));
      if (options.verso) {
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.symmetric(horizontal: margeX, vertical: margeY),
          build: (_) => planche(verso),
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
          ? _verso(carte, etablissement, anneeScolaire, options)
          : _recto(carte, etablissement, anneeScolaire, options, logo),
    ));
    return doc.save();
  }
}
