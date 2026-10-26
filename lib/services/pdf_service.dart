import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/etablissement.dart';
import '../models/eleve.dart';
import '../models/cours.dart';
import '../models/note.dart';
import '../models/paiement.dart';
import '../providers/app_state_provider.dart';
import 'compta_utils.dart';

/// Données nécessaires pour imprimer le bulletin d'un élève.
class _BulletinData {
  final Eleve eleve;
  final List<Note> notes;
  final double? moyenneGenerale;
  final String rang;

  _BulletinData(this.eleve, this.notes, this.moyenneGenerale, this.rang);
}

class PDFService {
  PDFService._();

  // ── Polices embarquées (accents, symboles, rendu identique hors connexion) ──
  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> _pdfTheme() async {
    if (_theme != null) return _theme!;
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
      final italic = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Italic.ttf'));
      _theme = pw.ThemeData.withFont(base: regular, bold: bold, italic: italic, boldItalic: bold);
    } catch (_) {
      // Repli sur les polices standard du PDF si les fichiers sont introuvables
      _theme = pw.ThemeData.base();
    }
    return _theme!;
  }

  static pw.ImageProvider? _imageFromPath(String? path) {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (file.existsSync()) return pw.MemoryImage(file.readAsBytesSync());
    } catch (_) {
      // Image illisible : on l'ignore silencieusement
    }
    return null;
  }

  static String _libelleTrimestre(int trimestre) => "${trimestre == 1 ? '1er' : '${trimestre}e'} Trimestre";

  // ════════════════════════════════════════════════════════════════
  // BULLETINS
  // ════════════════════════════════════════════════════════════════

  /// Bulletin d'un seul élève.
  static Future<void> generateAndPreview({
    required BuildContext context,
    required Etablissement etablissement,
    required Eleve eleve,
    required String className,
    required List<Cours> courses,
    required List<Note> notes,
    required double? moyenneGenerale,
    required String rang,
    required int effectif,
    required int trimestre,
    bool primaire = false,
    String? anneeScolaire,
  }) async {
    final doc = pw.Document(theme: await _pdfTheme());
    final logo = _imageFromPath(etablissement.logoPath);
    _addBulletinPage(
      doc,
      etablissement: etablissement,
      logo: logo,
      className: className,
      courses: courses,
      data: _BulletinData(eleve, notes, moyenneGenerale, rang),
      effectif: effectif,
      trimestre: trimestre,
      primaire: primaire,
      anneeScolaire: anneeScolaire,
    );

    if (!context.mounted) return;
    await _preview(context, "Bulletin PDF : ${eleve.prenom} ${eleve.nom}", doc);
  }

  /// Bulletins de plusieurs élèves d'une même classe dans un seul PDF.
  /// [effectif] = nombre total d'élèves de la classe (même valeur que sur le bulletin individuel).
  static Future<void> generateAndPreviewBulk({
    required BuildContext context,
    required Etablissement etablissement,
    required String className,
    required List<Cours> courses,
    required List<Eleve> eleves,
    required int effectif,
    required int trimestre,
    required AppStateProvider stateProvider,
    String? anneeScolaire,
  }) async {
    if (eleves.isEmpty) return;
    final classId = eleves.first.classeId;
    final primaire = stateProvider.isClassePrimaire(classId);
    final doc = pw.Document(theme: await _pdfTheme());
    final logo = _imageFromPath(etablissement.logoPath);

    // Pre-calculate ranks for this class/trimestre
    final ranks = await stateProvider.calculateRanks(classId, trimestre);

    for (var eleve in eleves) {
      final notes = await stateProvider.getNotesForEleve(eleve.id!, trimestre);
      final moyenneGenerale = await stateProvider.calculateMoyenneGenerale(eleve.id!, classId, trimestre);
      final rang = ranks[eleve.id!] ?? "Non classé";
      _addBulletinPage(
        doc,
        etablissement: etablissement,
        logo: logo,
        className: className,
        courses: courses,
        data: _BulletinData(eleve, notes, moyenneGenerale, rang),
        effectif: effectif,
        trimestre: trimestre,
        primaire: primaire,
        anneeScolaire: anneeScolaire,
      );
    }

    if (!context.mounted) return;
    await _preview(context, "Bulletins de la Classe : $className", doc);
  }

  static pw.Widget _entete(Etablissement etablissement, pw.ImageProvider? logo, {double logoSize = 55}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                etablissement.nom.toUpperCase(),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
              pw.SizedBox(height: 4),
              if (etablissement.adresse != null && etablissement.adresse!.isNotEmpty)
                pw.Text(etablissement.adresse!, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              if (etablissement.telephone != null && etablissement.telephone!.isNotEmpty)
                pw.Text("Téléphone : ${etablissement.telephone!}",
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ],
          ),
        ),
        if (logo != null)
          pw.SizedBox(width: logoSize, height: logoSize, child: pw.Image(logo, fit: pw.BoxFit.contain))
        else
          pw.SizedBox(width: logoSize, height: logoSize),
      ],
    );
  }

  static void _addBulletinPage(
    pw.Document doc, {
    required Etablissement etablissement,
    required pw.ImageProvider? logo,
    required String className,
    required List<Cours> courses,
    required _BulletinData data,
    required int effectif,
    required int trimestre,
    required bool primaire,
    String? anneeScolaire,
  }) {
    final bareme = primaire ? 10 : 20;
    final eleve = data.eleve;
    final moyenneGenerale = data.moyenneGenerale;
    final studentPhoto = _imageFromPath(eleve.photoPath);
    final annee = anneeScolaire ?? etablissement.anneeScolaire;

    final tableData = courses.map((course) {
      final noteOpt = data.notes.where((n) => n.coursId == course.id).toList();
      final Note? note = noteOpt.isNotEmpty ? noteOpt.first : null;
      final avg = note?.moyenneCoursPour(primaire);
      if (primaire) {
        return [
          course.nom,
          note?.noteComposition != null ? note!.noteComposition!.toStringAsFixed(2) : "-",
        ];
      }
      return [
        course.nom,
        course.coefficient.toString(),
        note?.noteClasse != null ? note!.noteClasse!.toStringAsFixed(2) : "-",
        note?.noteComposition != null ? note!.noteComposition!.toStringAsFixed(2) : "-",
        avg != null ? avg.toStringAsFixed(2) : "-",
      ];
    }).toList();

    final mentionColor = moyenneGenerale != null
        ? (moyenneGenerale >= bareme * 0.6
            ? PdfColors.green800
            : (moyenneGenerale >= bareme / 2 ? PdfColors.teal800 : PdfColors.red800))
        : PdfColors.grey700;

    // MultiPage : si une classe a beaucoup de matières, le bulletin continue sur une 2e page
    // au lieu de provoquer une erreur.
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context pdfContext) => [
          _entete(etablissement, logo),
          pw.SizedBox(height: 4),
          pw.Text("Année Scolaire : $annee", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 12),

          // Bulletin Title
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  "BULLETIN DE NOTES",
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 18, letterSpacing: 1.5, color: PdfColors.blueGrey900),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _libelleTrimestre(trimestre),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Student Identity Details
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            padding: const pw.EdgeInsets.all(12),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            const pw.TextSpan(text: "Nom & Prénom : ", style: pw.TextStyle(fontSize: 10)),
                            pw.TextSpan(
                              text: "${eleve.prenom} ${eleve.nom}",
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text("Matricule : ${eleve.matricule ?? 'N/A'}", style: const pw.TextStyle(fontSize: 9)),
                      if (eleve.dateNaissance != null) ...[
                        pw.SizedBox(height: 6),
                        pw.Text("Date de naissance : ${eleve.dateNaissance!}", style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Classe : $className", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.SizedBox(height: 6),
                    pw.Text("Effectif : $effectif élèves", style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                if (studentPhoto != null) ...[
                  pw.SizedBox(width: 16),
                  pw.Container(
                    width: 45,
                    height: 55,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400, width: 1),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Image(studentPhoto, fit: pw.BoxFit.cover),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Table of Grades
          pw.TableHelper.fromTextArray(
            headers: primaire
                ? ["Matière", "Note de composition (10)"]
                : ["Matière", "Coefficient", "Note Classe (20)", "Note Composition (40)", "Moyenne"],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            rowDecoration:
                const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
            },
            data: tableData,
          ),
          pw.SizedBox(height: 20),

          // Summary footer (Averages & Rankings & Signature Block)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 260,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  color: PdfColors.grey100,
                ),
                padding: const pw.EdgeInsets.all(12),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _ligneResume(
                      "Moyenne Générale :",
                      moyenneGenerale != null ? "${moyenneGenerale.toStringAsFixed(2)} / $bareme" : "-",
                      PdfColors.blue800,
                    ),
                    pw.SizedBox(height: 6),
                    _ligneResume("Rang de l'élève :", "${data.rang} sur $effectif", PdfColors.deepOrange800),
                    pw.SizedBox(height: 6),
                    _ligneResume(
                      "Mention :",
                      moyenneGenerale != null ? AppStateProvider.getMention(moyenneGenerale, bareme: bareme) : "-",
                      mentionColor,
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 6),
                  pw.Text(
                    "Signature du Directeur",
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 9, decoration: pw.TextDecoration.underline),
                  ),
                  pw.SizedBox(height: 48),
                  pw.Text(
                    "[ Cachet et Signature ]",
                    style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _ligneResume(String label, String value, PdfColor color) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: color)),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // REÇU DE PAIEMENT
  // ════════════════════════════════════════════════════════════════

  /// Construit le PDF d'un reçu (format A5 paysage).
  /// [paiements] : les lignes du reçu (une seule, ou inscription + scolarité payées ensemble).
  static Future<Uint8List> buildRecu({
    required Etablissement etablissement,
    required String anneeScolaire,
    required List<Paiement> paiements,
    SituationEleve? situation,
  }) async {
    if (paiements.isEmpty) throw ArgumentError('Aucun paiement à imprimer');
    final doc = pw.Document(theme: await _pdfTheme());
    final logo = _imageFromPath(etablissement.logoPath);
    final premier = paiements.first;
    final dateFr = DateFormat('dd/MM/yyyy').format(premier.date);
    final total = paiements.fold<double>(0, (t, p) => t + p.montant);
    final observations = paiements
        .map((p) => p.observation?.trim() ?? '')
        .where((o) => o.isNotEmpty)
        .toSet()
        .join(' — ');
    final types = paiements.map((p) => p.type).toSet();

    pw.Widget info(String label, String valeur, {bool gras = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 78,
                child: pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ),
              pw.Expanded(
                child: pw.Text(
                  valeur,
                  style: pw.TextStyle(fontSize: 9.5, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal),
                ),
              ),
            ],
          ),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _entete(etablissement, logo, logoSize: 38),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("REÇU DE PAIEMENT",
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("N° ${premier.numeroRecu ?? '-'}",
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                    pw.Text("Date : $dateFr", style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      info("Élève :", premier.eleveNomComplet, gras: true),
                      if (premier.eleveMatricule != null && premier.eleveMatricule!.isNotEmpty)
                        info("Matricule :", premier.eleveMatricule!),
                      info("Classe :", premier.classeNom ?? '-'),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      info("Année scolaire :", anneeScolaire),
                      info("Mode de paiement :", premier.mode ?? 'Espèces'),
                      if (observations.isNotEmpty) info("Observation :", observations),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
              columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4)},
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                  children: [
                    _celluleRecu("Objet du paiement", entete: true),
                    _celluleRecu("Montant", entete: true, droite: true),
                  ],
                ),
                for (final p in paiements)
                  pw.TableRow(children: [
                    _celluleRecu(p.libelle),
                    _celluleRecu(formatFcfa(p.montant), droite: true),
                  ]),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _celluleRecu("TOTAL REÇU", gras: true),
                    _celluleRecu(formatFcfa(total), gras: true, droite: true),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Text("Arrêté le présent reçu à la somme de : ${montantEnLettres(total)}.",
                style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic)),
            if (situation != null) ...[
              pw.SizedBox(height: 5),
              for (final type in [Paiement.typeInscription, Paiement.typeScolarite])
                if (types.contains(type))
                  pw.Text(
                    "Situation ${type == Paiement.typeInscription ? "de l'inscription" : "de la scolarité"} : "
                    "payé ${formatFcfa(situation.dejaPaye(type))} sur ${formatFcfa(situation.du(type))}"
                    " — reste à payer : ${formatFcfa(situation.reste(type))}",
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                  ),
            ],
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Signature du payeur", style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                pw.Text("Le Caissier / La Direction", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 22),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _celluleRecu(String texte, {bool entete = false, bool gras = false, bool droite = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
      child: pw.Text(
        texte,
        textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: entete ? 8.5 : 9.5,
          fontWeight: (entete || gras) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: entete ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  static Future<void> previewRecu({
    required BuildContext context,
    required Etablissement etablissement,
    required String anneeScolaire,
    required List<Paiement> paiements,
    SituationEleve? situation,
  }) async {
    final bytes = await buildRecu(
      etablissement: etablissement,
      anneeScolaire: anneeScolaire,
      paiements: paiements,
      situation: situation,
    );
    if (!context.mounted) return;
    final p = paiements.first;
    await _previewBytes(
      context,
      "Reçu ${p.numeroRecu ?? ''} — ${p.eleveNomComplet}",
      bytes,
      format: PdfPageFormat.a5.landscape,
      fileName: 'recu_${p.numeroRecu ?? p.id}.pdf',
      ajusterALaFenetre: true,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // LISTE DE SITUATION FINANCIÈRE (ex. liste des impayés)
  // ════════════════════════════════════════════════════════════════

  static Future<void> previewListeSituation({
    required BuildContext context,
    required Etablissement etablissement,
    required String anneeScolaire,
    required String titre,
    required List<SituationEleve> situations,
  }) async {
    final doc = pw.Document(theme: await _pdfTheme());
    final logo = _imageFromPath(etablissement.logoPath);
    final resume = ResumeCompta.depuis(situations);
    final edition = DateFormat('dd/MM/yyyy').format(DateTime.now());

    final data = <List<String>>[];
    for (var i = 0; i < situations.length; i++) {
      final s = situations[i];
      data.add([
        '${i + 1}',
        s.nomComplet,
        s.classeNom,
        s.telephoneParent ?? '',
        formatMontant(s.payeInscription),
        formatMontant(s.resteInscription),
        formatMontant(s.payeScolarite),
        formatMontant(s.resteScolarite),
        formatMontant(s.resteTotal),
      ]);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text("Page ${ctx.pageNumber} / ${ctx.pagesCount}",
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (ctx) => [
          _entete(etablissement, logo, logoSize: 40),
          pw.SizedBox(height: 6),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 6),
          pw.Text(titre, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text("Année scolaire : $anneeScolaire  —  édité le $edition  —  ${situations.length} élève(s)",
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const [
              'N°',
              'Élève',
              'Classe',
              'Tél. parent',
              'Inscription payée',
              'Reste inscription',
              'Scolarité payée',
              'Reste scolarité',
              'Reste total',
            ],
            data: data,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            rowDecoration:
                const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            "Total encaissé : ${formatFcfa(resume.totalEncaisse)}   —   Reste à recouvrer : ${formatFcfa(resume.totalReste)}",
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    await _preview(context, titre, doc);
  }

  // ════════════════════════════════════════════════════════════════
  // APERÇU
  // ════════════════════════════════════════════════════════════════

  static Future<void> _preview(BuildContext context, String title, pw.Document doc) async {
    final bytes = await doc.save();
    if (!context.mounted) return;
    await _previewBytes(context, title, bytes);
  }

  static Future<void> _previewBytes(
    BuildContext context,
    String title,
    Uint8List bytes, {
    PdfPageFormat format = PdfPageFormat.a4,
    String fileName = 'document.pdf',
    bool ajusterALaFenetre = false,
  }) async {
    await showDialog(
      context: context,
      builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              double? largeurMax;
              if (ajusterALaFenetre) {
                // La page entière doit tenir dans la fenêtre, sans défilement :
                // on retire la barre d'outils et les marges, puis on applique les proportions de la page.
                const hauteurBarreEtMarges = 120.0;
                final ratio = format.width / format.height;
                final parHauteur = (constraints.maxHeight - hauteurBarreEtMarges) * ratio;
                final parLargeur = constraints.maxWidth - 48;
                largeurMax = (parHauteur < parLargeur ? parHauteur : parLargeur).clamp(240.0, 2000.0).toDouble();
              }
              return PdfPreview(
                build: (_) async => bytes,
                initialPageFormat: format,
                pdfFileName: fileName,
                maxPageWidth: largeurMax,
                allowSharing: true,
                allowPrinting: true,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
              );
            },
          ),
        );
      },
    );
  }
}
