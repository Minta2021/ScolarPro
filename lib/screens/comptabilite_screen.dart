import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../models/classe.dart';
import '../models/paiement.dart';
import '../providers/app_state_provider.dart';
import '../services/compta_service.dart';
import '../services/compta_utils.dart';
import '../services/pdf_service.dart';
import '../services/text_utils.dart';
import '../theme/app_theme.dart';

/// Filtre de statut de l'onglet « Élèves & paiements ».
enum _FiltreStatut { tous, enRegle, partiel, nonPaye }

/// Couleur associée à un statut de paiement.
Color couleurStatut(StatutPaiement s) {
  switch (s) {
    case StatutPaiement.solde:
      return AppTheme.success;
    case StatutPaiement.exonere:
      return AppTheme.primaryLight;
    case StatutPaiement.partiel:
      return AppTheme.warning;
    case StatutPaiement.nonPaye:
      return AppTheme.error;
    case StatutPaiement.nonDefini:
      return AppTheme.textLight;
  }
}

Widget badgeStatut(StatutPaiement s, {double fontSize = 10}) {
  final c = couleurStatut(s);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      s.libelle.toUpperCase(),
      style: TextStyle(color: c, fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: 0.4),
    ),
  );
}

/// Module Comptabilité : frais d'inscription et de scolarité.
class ComptabiliteScreen extends StatefulWidget {
  const ComptabiliteScreen({super.key});

  @override
  State<ComptabiliteScreen> createState() => _ComptabiliteScreenState();
}

class _ComptabiliteScreenState extends State<ComptabiliteScreen> {
  static final DateFormat _dateFr = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  int? _anneeChargee;
  int? _classeFiltre;
  List<SituationEleve> _situations = [];
  List<Paiement> _journal = [];

  // Onglet élèves
  final TextEditingController _rechercheCtrl = TextEditingController();
  _FiltreStatut _filtreStatut = _FiltreStatut.tous;

  // Onglet journal
  String? _typeJournal;
  DateTime? _du;
  DateTime? _au;

  // Onglet frais
  final Map<int, TextEditingController> _fraisInscCtrls = {};
  final Map<int, TextEditingController> _fraisScolCtrls = {};

  @override
  void initState() {
    super.initState();
    _rechercheCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    for (final c in _fraisInscCtrls.values) {
      c.dispose();
    }
    for (final c in _fraisScolCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    final state = context.read<AppStateProvider>();
    final annee = state.selectedAnneeScolaire;
    if (annee == null) {
      setState(() {
        _loading = false;
        _anneeChargee = null;
        _situations = [];
        _journal = [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final situations = await ComptaService.situations(annee.id!);
      final journal = await ComptaService.journal(annee.id!);
      if (!mounted) return;
      setState(() {
        _situations = situations;
        _journal = journal;
        _anneeChargee = annee.id;
        if (_classeFiltre != null && !state.classes.any((c) => c.id == _classeFiltre)) _classeFiltre = null;
        _loading = false;
      });
      _initControleursFrais(state.classes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _anneeChargee = annee.id; // évite de relancer le chargement en boucle
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de chargement de la comptabilité : $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  void _initControleursFrais(List<Classe> classes) {
    for (final c in classes) {
      _fraisInscCtrls.putIfAbsent(c.id!, () => TextEditingController()).text =
          c.fraisInscription > 0 ? formatMontant(c.fraisInscription) : '';
      _fraisScolCtrls.putIfAbsent(c.id!, () => TextEditingController()).text =
          c.fraisScolarite > 0 ? formatMontant(c.fraisScolarite) : '';
    }
  }

  List<SituationEleve> get _situationsFiltreesClasse =>
      _classeFiltre == null ? _situations : _situations.where((s) => s.classeId == _classeFiltre).toList();

  List<Paiement> get _journalFiltre {
    return _journal.where((pmt) {
      if (_classeFiltre != null && pmt.classeId != _classeFiltre) return false;
      if (_typeJournal != null && pmt.type != _typeJournal) return false;
      final d = DateTime(pmt.date.year, pmt.date.month, pmt.date.day);
      if (_du != null && d.isBefore(DateTime(_du!.year, _du!.month, _du!.day))) return false;
      if (_au != null && d.isAfter(DateTime(_au!.year, _au!.month, _au!.day))) return false;
      return true;
    }).toList();
  }

  List<SituationEleve> get _elevesFiltres {
    final q = normaliser(_rechercheCtrl.text);
    return _situationsFiltreesClasse.where((s) {
      if (q.isNotEmpty) {
        final texte = normaliser('${s.nom} ${s.prenom} ${s.prenom} ${s.nom} ${s.matricule ?? ''}');
        if (!texte.contains(q)) return false;
      }
      // Situation globale de l'élève (inscription + scolarité confondues)
      final st = s.statutGlobal;
      switch (_filtreStatut) {
        case _FiltreStatut.tous:
          return true;
        case _FiltreStatut.enRegle:
          return st.enRegle;
        case _FiltreStatut.partiel:
          return st == StatutPaiement.partiel;
        case _FiltreStatut.nonPaye:
          return st == StatutPaiement.nonPaye;
      }
    }).toList();
  }

  // ════════════════════════════════════════════════════════════════
  // ACTIONS
  // ════════════════════════════════════════════════════════════════

  Future<void> _encaisser(SituationEleve situation, {String? type}) async {
    final state = context.read<AppStateProvider>();
    final lignes = await showDialog<List<Paiement>>(
      context: context,
      builder: (_) => _PaiementDialog(situation: situation, typeInitial: type),
    );
    if (lignes == null || lignes.isEmpty || !mounted) return;
    await _charger();
    if (!mounted) return;
    final total = lignes.fold<double>(0, (t, p) => t + p.montant);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Paiement de ${formatFcfa(total)} enregistré (reçu ${lignes.first.numeroRecu ?? ''}).'),
        backgroundColor: AppTheme.success,
      ),
    );
    if (_imprimerApresEncaissement) {
      await _imprimerRecu(lignes.first, state: state);
    }
  }

  bool _imprimerApresEncaissement = true;

  Future<void> _imprimerRecu(Paiement paiement, {AppStateProvider? state}) async {
    final st = state ?? context.read<AppStateProvider>();
    final etab = st.etablissement;
    if (etab == null || etab.nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Configurez d'abord les paramètres de l'établissement (nom, logo) pour imprimer les reçus."),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    // Un reçu peut regrouper plusieurs lignes (inscription + scolarité payées ensemble)
    final lignes = paiement.numeroRecu != null ? await ComptaService.paiementsDuRecu(paiement.numeroRecu!) : <Paiement>[];
    final situation = await ComptaService.situationEleve(paiement.eleveId);
    if (!mounted) return;
    await PDFService.previewRecu(
      context: context,
      etablissement: etab,
      anneeScolaire: st.selectedAnneeScolaire?.libelle ?? etab.anneeScolaire,
      paiements: lignes.isEmpty ? [paiement] : lignes,
      situation: situation,
    );
  }

  Future<void> _supprimerPaiement(Paiement paiement) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Annuler ce paiement ?"),
        content: Text(
          "Le paiement ${paiement.numeroRecu ?? ''} de ${formatFcfa(paiement.montant)} "
          "(${paiement.eleveNomComplet}, ${paiement.libelle.toLowerCase()}) sera définitivement supprimé.",
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Non")),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text("Supprimer le paiement"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ComptaService.supprimerPaiement(paiement.id!);
    await _charger();
  }

  Future<void> _ouvrirFiche(SituationEleve situation) async {
    final modifie = await showDialog<bool>(
      context: context,
      builder: (_) => _FicheEleveDialog(
        eleveId: situation.eleveId,
        onImprimerRecu: (pmt) => _imprimerRecu(pmt),
      ),
    );
    if (modifie == true) await _charger();
  }

  Future<void> _nouvelEncaissement() async {
    final choisi = await showDialog<SituationEleve>(
      context: context,
      builder: (_) => _ChoixEleveDialog(situations: _situationsFiltreesClasse),
    );
    if (choisi != null && mounted) await _encaisser(choisi);
  }

  Future<void> _enregistrerFrais(List<Classe> classes) async {
    final erreurs = <String>[];
    var modifiees = 0;
    for (final c in classes) {
      final txtI = _fraisInscCtrls[c.id]?.text ?? '';
      final txtS = _fraisScolCtrls[c.id]?.text ?? '';
      final insc = txtI.trim().isEmpty ? 0.0 : parseMontant(txtI);
      final scol = txtS.trim().isEmpty ? 0.0 : parseMontant(txtS);
      if (insc == null || scol == null || insc < 0 || scol < 0) {
        erreurs.add(c.nom);
        continue;
      }
      if (insc != c.fraisInscription || scol != c.fraisScolarite) {
        await ComptaService.majFraisClasse(c.id!, insc, scol);
        modifiees++;
      }
    }
    if (!mounted) return;
    await context.read<AppStateProvider>().loadClasses();
    await _charger();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erreurs.isEmpty
            ? "Frais enregistrés ($modifiees classe(s) modifiée(s))."
            : "Montant invalide pour : ${erreurs.join(', ')}. Les autres classes ont été enregistrées."),
        backgroundColor: erreurs.isEmpty ? AppTheme.success : AppTheme.warning,
      ),
    );
  }

  void _appliquerATousLesNiveaux(Classe modele, List<Classe> classes) {
    setState(() {
      for (final c in classes.where((c) => c.niveau == modele.niveau && c.id != modele.id)) {
        _fraisInscCtrls[c.id]!.text = _fraisInscCtrls[modele.id]!.text;
        _fraisScolCtrls[c.id]!.text = _fraisScolCtrls[modele.id]!.text;
      }
    });
  }

  // ── Exports ───────────────────────────────────────────────────────

  Future<String?> _demanderFichier(String nomParDefaut) async {
    String? out = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer le fichier Excel',
      fileName: nomParDefaut,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (out == null) return null;
    if (!out.toLowerCase().endsWith('.xlsx')) out += '.xlsx';
    return out;
  }

  Future<void> _ecrireExcel(ex.Excel excel, String path) async {
    final bytes = excel.save();
    if (bytes == null) throw Exception("Impossible de générer le fichier Excel.");
    await File(path).writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fichier enregistré : ${p.basename(path)}'), backgroundColor: AppTheme.success),
    );
  }

  ex.CellValue _montantCell(double v) => ex.IntCellValue(v.round());

  Future<void> _exporterSituation(List<SituationEleve> liste) async {
    try {
      final annee = context.read<AppStateProvider>().selectedAnneeScolaire?.libelle ?? '';
      final path = await _demanderFichier('situation_paiements_${annee.replaceAll(' ', '_')}.xlsx');
      if (path == null) return;
      final excel = ex.Excel.createExcel();
      excel.rename('Sheet1', 'Situation');
      final sheet = excel['Situation'];
      sheet.appendRow([
        'Classe', 'Nom', 'Prénom', 'Matricule', 'Téléphone parent',
        'Frais inscription', 'Payé inscription', 'Reste inscription', 'Statut inscription',
        'Frais scolarité', 'Remise', 'Scolarité due', 'Payé scolarité', 'Reste scolarité', 'Statut scolarité',
        'Total payé', 'Reste total',
      ].map((h) => ex.TextCellValue(h)).toList());
      for (final s in liste) {
        sheet.appendRow([
          ex.TextCellValue(s.classeNom),
          ex.TextCellValue(s.nom),
          ex.TextCellValue(s.prenom),
          ex.TextCellValue(s.matricule ?? ''),
          ex.TextCellValue(s.telephoneParent ?? ''),
          _montantCell(s.fraisInscription),
          _montantCell(s.payeInscription),
          _montantCell(s.resteInscription),
          ex.TextCellValue(s.statutInscription.libelle),
          _montantCell(s.fraisScolarite),
          _montantCell(s.remiseScolarite),
          _montantCell(s.duScolarite),
          _montantCell(s.payeScolarite),
          _montantCell(s.resteScolarite),
          ex.TextCellValue(s.statutScolarite.libelle),
          _montantCell(s.payeTotal),
          _montantCell(s.resteTotal),
        ]);
      }
      for (var i = 0; i < 17; i++) {
        sheet.setColumnWidth(i, i < 5 ? 20 : 16);
      }
      await _ecrireExcel(excel, path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur d'exportation : $e"), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _exporterJournal(List<Paiement> liste) async {
    try {
      final path = await _demanderFichier('journal_encaissements.xlsx');
      if (path == null) return;
      final excel = ex.Excel.createExcel();
      excel.rename('Sheet1', 'Encaissements');
      final sheet = excel['Encaissements'];
      sheet.appendRow(['Date', 'N° reçu', 'Élève', 'Matricule', 'Classe', 'Objet', 'Mode', 'Montant (FCFA)', 'Observation']
          .map((h) => ex.TextCellValue(h))
          .toList());
      double total = 0;
      for (final pmt in liste) {
        total += pmt.montant;
        sheet.appendRow([
          ex.TextCellValue(_dateFr.format(pmt.date)),
          ex.TextCellValue(pmt.numeroRecu ?? ''),
          ex.TextCellValue(pmt.eleveNomComplet),
          ex.TextCellValue(pmt.eleveMatricule ?? ''),
          ex.TextCellValue(pmt.classeNom ?? ''),
          ex.TextCellValue(pmt.libelle),
          ex.TextCellValue(pmt.mode ?? ''),
          _montantCell(pmt.montant),
          ex.TextCellValue(pmt.observation ?? ''),
        ]);
      }
      sheet.appendRow([
        null, null, null, null, null, null,
        ex.TextCellValue('TOTAL'),
        _montantCell(total),
        null,
      ]);
      for (var i = 0; i < 9; i++) {
        sheet.setColumnWidth(i, i == 2 ? 26 : 16);
      }
      await _ecrireExcel(excel, path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur d'exportation : $e"), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _imprimerListe(List<SituationEleve> liste, String titre) async {
    final state = context.read<AppStateProvider>();
    final etab = state.etablissement;
    if (etab == null || etab.nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Configurez d'abord les paramètres de l'établissement."),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    await PDFService.previewListeSituation(
      context: context,
      etablissement: etab,
      anneeScolaire: state.selectedAnneeScolaire?.libelle ?? etab.anneeScolaire,
      titre: titre,
      situations: liste,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // INTERFACE
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final annee = state.selectedAnneeScolaire;
    if (!_loading && annee?.id != _anneeChargee) {
      // L'utilisateur a changé d'année dans la barre latérale
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _charger();
      });
    }
    final classes = state.classes;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text("Comptabilité${annee != null ? ' — ${annee.libelle}' : ''}"),
          actions: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<int?>(
                key: ValueKey('filtre-classe-$_classeFiltre-${classes.length}'),
                initialValue: _classeFiltre,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  prefixIcon: Icon(Icons.filter_list_rounded, size: 18),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text("Toutes les classes")),
                  for (final c in classes) DropdownMenuItem<int?>(value: c.id, child: Text(c.nom)),
                ],
                onChanged: (v) => setState(() => _classeFiltre = v),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: "Actualiser",
              onPressed: _loading ? null : _charger,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 16),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.dashboard_rounded, size: 18), text: "Tableau de bord"),
              Tab(icon: Icon(Icons.people_alt_rounded, size: 18), text: "Élèves & paiements"),
              Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: "Journal des encaissements"),
              Tab(icon: Icon(Icons.price_change_rounded, size: 18), text: "Frais par classe"),
            ],
          ),
        ),
        body: annee == null
            ? const Center(child: Text("Aucune année scolaire sélectionnée."))
            : (_loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _buildTableauDeBord(classes),
                      _buildOngletEleves(),
                      _buildOngletJournal(),
                      _buildOngletFrais(classes),
                    ],
                  )),
      ),
    );
  }

  // ── Tableau de bord ───────────────────────────────────────────────

  Widget _buildTableauDeBord(List<Classe> classes) {
    final situations = _situationsFiltreesClasse;
    final resume = ResumeCompta.depuis(situations);
    final maintenant = DateTime.now();
    final duMois = _journalFiltre
        .where((pmt) => pmt.date.year == maintenant.year && pmt.date.month == maintenant.month)
        .fold<double>(0, (t, pmt) => t + pmt.montant);
    final classesSansFrais = classes
        .where((c) => (_classeFiltre == null || c.id == _classeFiltre) && !c.fraisDefinis)
        .map((c) => c.nom)
        .toList();

    if (situations.isEmpty) {
      return const Center(
        child: Text("Aucun élève inscrit pour cette sélection.", style: TextStyle(color: AppTheme.textLight)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (classesSansFrais.isNotEmpty) ...[
            Builder(
              builder: (ctx) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.amber.shade900),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "${classesSansFrais.length} classe(s) sans frais définis : ${classesSansFrais.join(', ')}. "
                        "Leurs élèves ne sont pas comptés dans les statistiques ci-dessous.",
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () => DefaultTabController.of(ctx).animateTo(3),
                      child: const Text("Définir les frais"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          LayoutBuilder(builder: (context, constraints) {
            final cartes = [
              _carteFrais("Frais d'inscription", Icons.how_to_reg_rounded, resume.inscription, "ont payé l'inscription"),
              _carteFrais("Frais de scolarité", Icons.school_rounded, resume.scolarite, "ont soldé la scolarité"),
            ];
            if (constraints.maxWidth < 800) {
              return Column(children: [cartes[0], const SizedBox(height: 16), cartes[1]]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: cartes[0]), const SizedBox(width: 16), Expanded(child: cartes[1])],
            );
          }),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _kpi("Total encaissé", formatFcfa(resume.totalEncaisse), Icons.account_balance_wallet_rounded, AppTheme.success),
              _kpi("Reste à recouvrer", formatFcfa(resume.totalReste), Icons.hourglass_bottom_rounded, AppTheme.error),
              _kpi("Taux de recouvrement", "${resume.tauxRecouvrement.toStringAsFixed(1)} %", Icons.pie_chart_rounded,
                  AppTheme.primary),
              _kpi("Encaissé ce mois-ci", formatFcfa(duMois), Icons.calendar_month_rounded, AppTheme.secondary),
            ],
          ),
          const SizedBox(height: 24),
          _buildTableauParClasse(classes),
        ],
      ),
    );
  }

  Widget _carteFrais(String titre, IconData icon, ResumeFrais r, String libelleEnRegle) {
    final ratio = r.concernes == 0 ? 0.0 : r.enRegle / r.concernes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primary),
                const SizedBox(width: 10),
                Text(titre, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            if (r.concernes == 0)
              const Text("Aucun frais défini pour les classes sélectionnées.", style: TextStyle(color: AppTheme.textLight))
            else ...[
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: AppTheme.fontFamily, color: AppTheme.textDark),
                  children: [
                    TextSpan(
                      text: "${r.enRegle}",
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppTheme.success),
                    ),
                    TextSpan(text: " / ${r.concernes} élèves ", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    TextSpan(text: libelleEnRegle, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: ratio, minHeight: 10, color: AppTheme.success),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _miniStat("Payé en partie", r.partiels, AppTheme.warning),
                  _miniStat("Aucun versement", r.nonPayes, AppTheme.error),
                  if (r.exoneres > 0) _miniStat("Exonérés", r.exoneres, AppTheme.primaryLight),
                ],
              ),
              const Divider(height: 28),
              _ligneMontant("Encaissé", r.encaisse, AppTheme.success),
              _ligneMontant("Attendu", r.attendu, AppTheme.textDark),
              _ligneMontant("Reste à recouvrer", r.reste, AppTheme.error),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, int n, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text("$label : ", style: const TextStyle(color: AppTheme.textLight, fontSize: 13)),
        Text("$n", style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }

  Widget _ligneMontant(String label, double montant, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textLight, fontSize: 13)),
          const Spacer(),
          Text(formatFcfa(montant), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _kpi(String titre, String valeur, IconData icon, Color color) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(color: AppTheme.textLight, fontSize: 12)),
                const SizedBox(height: 2),
                Text(valeur, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableauParClasse(List<Classe> classes) {
    final lignes = <(Classe, ResumeCompta)>[];
    for (final c in classes) {
      if (_classeFiltre != null && c.id != _classeFiltre) continue;
      lignes.add((c, ResumeCompta.depuis(_situations.where((s) => s.classeId == c.id))));
    }
    const h = TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textMedium);
    Widget cell(String t, int flex, {TextStyle? style, TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Text(t, style: style ?? const TextStyle(fontSize: 13), textAlign: align, overflow: TextOverflow.ellipsis),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Détail par classe", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text("Cliquez sur une classe pour voir la liste de ses élèves.",
                style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: AppTheme.surfaceAlt,
              child: Row(children: [
                cell("Classe", 3, style: h),
                cell("Effectif", 2, style: h, align: TextAlign.center),
                cell("Inscription payée", 2, style: h, align: TextAlign.center),
                cell("Scolarité soldée", 2, style: h, align: TextAlign.center),
                cell("Partiel", 2, style: h, align: TextAlign.center),
                cell("Aucun versement", 2, style: h, align: TextAlign.center),
                cell("Encaissé", 3, style: h, align: TextAlign.right),
                cell("Reste", 3, style: h, align: TextAlign.right),
              ]),
            ),
            for (final (c, r) in lignes)
              Builder(
                builder: (ctx) => InkWell(
                  onTap: () {
                    setState(() => _classeFiltre = c.id);
                    DefaultTabController.of(ctx).animateTo(1);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.borderLight))),
                    child: Row(children: [
                      cell(c.nom, 3, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      cell("${r.effectif}", 2, align: TextAlign.center),
                      cell(c.fraisInscription > 0 ? "${r.inscription.enRegle} / ${r.inscription.concernes}" : "—", 2,
                          align: TextAlign.center),
                      cell(c.fraisScolarite > 0 ? "${r.scolarite.enRegle} / ${r.scolarite.concernes}" : "—", 2,
                          align: TextAlign.center),
                      cell(c.fraisScolarite > 0 ? "${r.scolarite.partiels}" : "—", 2, align: TextAlign.center),
                      cell(c.fraisScolarite > 0 ? "${r.scolarite.nonPayes}" : "—", 2, align: TextAlign.center),
                      cell(formatFcfa(r.totalEncaisse), 3,
                          align: TextAlign.right, style: const TextStyle(fontSize: 13, color: AppTheme.success)),
                      cell(formatFcfa(r.totalReste), 3,
                          align: TextAlign.right, style: const TextStyle(fontSize: 13, color: AppTheme.error)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Élèves & paiements ────────────────────────────────────────────

  Widget _buildOngletEleves() {
    final liste = _elevesFiltres;
    final resume = ResumeCompta.depuis(liste);
    final titreListe =
        _filtreStatut == _FiltreStatut.tous ? "Situation des paiements" : "Élèves — ${_libelleFiltre()}";

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _rechercheCtrl,
                  decoration: const InputDecoration(
                    hintText: "Rechercher un élève (nom, matricule)",
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              SegmentedButton<_FiltreStatut>(
                segments: const [
                  ButtonSegment(value: _FiltreStatut.tous, label: Text("Tous")),
                  ButtonSegment(value: _FiltreStatut.enRegle, label: Text("En règle")),
                  ButtonSegment(value: _FiltreStatut.partiel, label: Text("Partiel")),
                  ButtonSegment(value: _FiltreStatut.nonPaye, label: Text("Non payé")),
                ],
                selected: {_filtreStatut},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _filtreStatut = s.first),
              ),
              CheckboxListTileLike(
                value: _imprimerApresEncaissement,
                label: "Imprimer le reçu après chaque encaissement",
                onChanged: (v) => setState(() => _imprimerApresEncaissement = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text("${liste.length} élève(s)", style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 16),
              Text("Reste à recouvrer : ${formatFcfa(resume.totalReste)}",
                  style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: liste.isEmpty ? null : () => _imprimerListe(liste, titreListe),
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text("Imprimer la liste"),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: liste.isEmpty ? null : () => _exporterSituation(liste),
                icon: const Icon(Icons.table_chart_rounded, size: 18),
                label: const Text("Excel"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: liste.isEmpty
                ? const Center(child: Text("Aucun élève ne correspond à ces critères.", style: TextStyle(color: AppTheme.textLight)))
                : ListView.builder(
                    itemCount: liste.length,
                    itemBuilder: (context, i) => _ligneEleve(liste[i]),
                  ),
          ),
        ],
      ),
    );
  }

  String _libelleFiltre() {
    switch (_filtreStatut) {
      case _FiltreStatut.tous:
        return "tous";
      case _FiltreStatut.enRegle:
        return "en règle";
      case _FiltreStatut.partiel:
        return "paiement partiel";
      case _FiltreStatut.nonPaye:
        return "aucun versement";
    }
  }

  Widget _blocFrais(String titre, StatutPaiement statut, double paye, double du, {double remise = 0}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(titre, style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
            const SizedBox(width: 6),
            badgeStatut(statut, fontSize: 9),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          statut == StatutPaiement.nonDefini ? "—" : "${formatMontant(paye)} / ${formatFcfa(du)}",
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
        ),
        if (remise > 0)
          Text("Remise : ${formatFcfa(remise)}", style: const TextStyle(fontSize: 11, color: AppTheme.primaryLight)),
      ],
    );
  }

  Widget _ligneEleve(SituationEleve s) {
    final initiales = "${s.nom.isNotEmpty ? s.nom[0] : ''}${s.prenom.isNotEmpty ? s.prenom[0] : ''}";
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            child: Text(initiales, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.nomComplet, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(
                  "${s.classeNom}${s.matricule != null ? ' · ${s.matricule}' : ''}"
                  "${s.telephoneParent != null ? ' · Tél. ${s.telephoneParent}' : ''}",
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(flex: 3, child: _blocFrais("Inscription", s.statutInscription, s.payeInscription, s.duInscription)),
          Expanded(
            flex: 3,
            child: _blocFrais("Scolarité", s.statutScolarite, s.payeScolarite, s.duScolarite, remise: s.remiseScolarite),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text("Reste à payer", style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                Text(
                  formatFcfa(s.resteTotal),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: s.resteTotal > 0 ? AppTheme.error : AppTheme.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () => _encaisser(s),
            icon: const Icon(Icons.add_card_rounded, size: 16),
            label: const Text("Encaisser"),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: "Fiche de paiement (historique, remise, reçus)",
            onPressed: () => _ouvrirFiche(s),
            icon: const Icon(Icons.receipt_long_rounded, color: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  // ── Journal ───────────────────────────────────────────────────────

  Future<void> _choisirDate({required bool debut}) async {
    final initial = (debut ? _du : _au) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (debut) {
        _du = d;
      } else {
        _au = d;
      }
    });
  }

  Widget _buildOngletJournal() {
    final liste = _journalFiltre;
    final total = liste.fold<double>(0, (t, pmt) => t + pmt.montant);
    const h = TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textMedium);
    Widget cell(String t, int flex, {TextStyle? style, TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Text(t, style: style ?? const TextStyle(fontSize: 13), textAlign: align, overflow: TextOverflow.ellipsis),
        );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  initialValue: _typeJournal,
                  isDense: true,
                  decoration: const InputDecoration(labelText: "Objet", isDense: true),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text("Tous")),
                    DropdownMenuItem<String?>(value: Paiement.typeInscription, child: Text("Inscription")),
                    DropdownMenuItem<String?>(value: Paiement.typeScolarite, child: Text("Scolarité")),
                  ],
                  onChanged: (v) => setState(() => _typeJournal = v),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _choisirDate(debut: true),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(_du == null ? "Du : début" : "Du : ${_dateFr.format(_du!)}"),
              ),
              OutlinedButton.icon(
                onPressed: () => _choisirDate(debut: false),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(_au == null ? "Au : aujourd'hui" : "Au : ${_dateFr.format(_au!)}"),
              ),
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _du = DateTime(now.year, now.month, now.day);
                    _au = _du;
                  });
                },
                child: const Text("Aujourd'hui"),
              ),
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _du = DateTime(now.year, now.month, 1);
                    _au = DateTime(now.year, now.month + 1, 0);
                  });
                },
                child: const Text("Ce mois-ci"),
              ),
              if (_du != null || _au != null || _typeJournal != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _du = null;
                    _au = null;
                    _typeJournal = null;
                  }),
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text("Effacer les filtres"),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text("${liste.length} encaissement(s) — Total : ", style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(formatFcfa(total), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.success)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: liste.isEmpty ? null : () => _exporterJournal(liste),
                icon: const Icon(Icons.table_chart_rounded, size: 18),
                label: const Text("Excel"),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _situationsFiltreesClasse.isEmpty ? null : _nouvelEncaissement,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text("Nouvel encaissement"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              cell("Date", 2, style: h),
              cell("N° reçu", 2, style: h),
              cell("Élève", 4, style: h),
              cell("Classe", 2, style: h),
              cell("Objet", 3, style: h),
              cell("Mode", 2, style: h),
              cell("Montant", 3, style: h, align: TextAlign.right),
              const SizedBox(width: 96),
            ]),
          ),
          Expanded(
            child: liste.isEmpty
                ? const Center(child: Text("Aucun encaissement pour cette période.", style: TextStyle(color: AppTheme.textLight)))
                : ListView.separated(
                    itemCount: liste.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final pmt = liste[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        child: Row(children: [
                          cell(_dateFr.format(pmt.date), 2),
                          cell(pmt.numeroRecu ?? '-', 2, style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
                          cell(pmt.eleveNomComplet, 4, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          cell(pmt.classeNom ?? '', 2),
                          cell(pmt.libelle, 3),
                          cell(pmt.mode ?? '', 2),
                          cell(formatFcfa(pmt.montant), 3,
                              align: TextAlign.right,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.success)),
                          SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: "Imprimer le reçu",
                                  onPressed: () => _imprimerRecu(pmt),
                                  icon: const Icon(Icons.print_rounded, size: 18, color: AppTheme.primary),
                                ),
                                IconButton(
                                  tooltip: "Supprimer ce paiement",
                                  onPressed: () => _supprimerPaiement(pmt),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Frais par classe ──────────────────────────────────────────────

  Widget _buildOngletFrais(List<Classe> classes) {
    if (classes.isEmpty) {
      return const Center(child: Text("Aucune classe pour cette année.", style: TextStyle(color: AppTheme.textLight)));
    }
    final visibles = _classeFiltre == null ? classes : classes.where((c) => c.id == _classeFiltre).toList();
    for (final c in classes) {
      _fraisInscCtrls.putIfAbsent(
          c.id!, () => TextEditingController(text: c.fraisInscription > 0 ? formatMontant(c.fraisInscription) : ''));
      _fraisScolCtrls.putIfAbsent(
          c.id!, () => TextEditingController(text: c.fraisScolarite > 0 ? formatMontant(c.fraisScolarite) : ''));
    }
    final effectifs = <int, int>{};
    for (final s in _situations) {
      effectifs[s.classeId] = (effectifs[s.classeId] ?? 0) + 1;
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Frais exigés par classe", style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text(
                      "Montants en FCFA pour un élève, pour toute l'année scolaire. Une remise individuelle "
                      "(fratrie, enfant du personnel...) peut être accordée depuis la fiche de paiement de l'élève.",
                      style: TextStyle(color: AppTheme.textLight, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    for (final c in visibles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.nom, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text("${c.niveau} · ${effectifs[c.id] ?? 0} élève(s)",
                                      style: const TextStyle(color: AppTheme.textLight, fontSize: 12)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _fraisInscCtrls[c.id],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Inscription",
                                  suffixText: "FCFA",
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _fraisScolCtrls[c.id],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Scolarité (année)",
                                  suffixText: "FCFA",
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: "Copier ces montants sur les autres classes du niveau « ${c.niveau} »",
                              onPressed: () => _appliquerATousLesNiveaux(c, classes),
                              icon: const Icon(Icons.copy_all_rounded, color: AppTheme.primary),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  "Les modifications s'appliquent immédiatement aux situations de paiement des élèves.",
                  style: TextStyle(color: AppTheme.textLight, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _enregistrerFrais(classes),
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text("Enregistrer les frais"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Petite case à cocher avec libellé (sans la largeur infinie d'un CheckboxListTile).
class CheckboxListTileLike extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  const CheckboxListTileLike({super.key, required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMedium)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Boîte de dialogue : enregistrer un paiement
// ════════════════════════════════════════════════════════════════════

/// Mode « inscription et scolarité payées en même temps, sur le même reçu ».
const String _typeLesDeux = 'les_deux';

class _PaiementDialog extends StatefulWidget {
  final SituationEleve situation;
  final String? typeInitial;

  const _PaiementDialog({required this.situation, this.typeInitial});

  @override
  State<_PaiementDialog> createState() => _PaiementDialogState();
}

class _PaiementDialogState extends State<_PaiementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montantInscCtrl = TextEditingController();
  final _montantScolCtrl = TextEditingController();
  final _observationCtrl = TextEditingController();
  late String _type;
  DateTime _date = DateTime.now();
  String _mode = Paiement.modes.first;
  bool _enregistrement = false;

  SituationEleve get s => widget.situation;

  /// Il reste quelque chose à payer pour ce type de frais.
  bool _payable(String type) => s.reste(type) > 0;

  bool get _lesDeuxPossible => _payable(Paiement.typeInscription) && _payable(Paiement.typeScolarite);

  @override
  void initState() {
    super.initState();
    if (widget.typeInitial != null) {
      _type = widget.typeInitial!;
    } else if (_lesDeuxPossible) {
      // Cas le plus fréquent en début d'année : inscription + 1er versement de scolarité
      _type = _typeLesDeux;
    } else if (_payable(Paiement.typeInscription)) {
      _type = Paiement.typeInscription;
    } else {
      _type = Paiement.typeScolarite;
    }
    _montantInscCtrl.addListener(_rafraichir);
    _montantScolCtrl.addListener(_rafraichir);
    _preRemplir();
  }

  void _rafraichir() => setState(() {});

  @override
  void dispose() {
    _montantInscCtrl.dispose();
    _montantScolCtrl.dispose();
    _observationCtrl.dispose();
    super.dispose();
  }

  void _preRemplir() {
    final resteI = s.resteInscription;
    final resteS = s.resteScolarite;
    _montantInscCtrl.text = resteI > 0 ? formatMontant(resteI) : '';
    _montantScolCtrl.text = resteS > 0 ? formatMontant(resteS) : '';
  }

  /// Types de frais concernés par le mode choisi.
  List<String> get _typesConcernes => _type == _typeLesDeux
      ? [Paiement.typeInscription, Paiement.typeScolarite]
      : [_type];

  TextEditingController _ctrl(String type) =>
      type == Paiement.typeInscription ? _montantInscCtrl : _montantScolCtrl;

  double get _total {
    var t = 0.0;
    for (final type in _typesConcernes) {
      t += parseMontant(_ctrl(type).text) ?? 0;
    }
    return t;
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    final lignes = <Paiement>[];
    final observation = _observationCtrl.text.trim().isEmpty ? null : _observationCtrl.text.trim();
    for (final type in _typesConcernes) {
      final m = parseMontant(_ctrl(type).text) ?? 0;
      if (m <= 0) continue;
      lignes.add(Paiement(
        eleveId: s.eleveId,
        type: type,
        montant: m,
        datePaiement: ComptaService.isoDate.format(_date),
        mode: _mode,
        observation: observation,
      ));
    }
    if (lignes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Entrez au moins un montant."), backgroundColor: AppTheme.error),
      );
      return;
    }
    setState(() => _enregistrement = true);
    try {
      final enregistres = await ComptaService.enregistrerPaiements(lignes);
      if (!mounted) return;
      Navigator.of(context).pop(enregistres);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur d'enregistrement : $e"), backgroundColor: AppTheme.error),
      );
    }
  }

  Widget _blocSituation(String type) {
    final statut = s.statut(type);
    final nom = type == Paiement.typeInscription ? "Inscription" : "Scolarité";
    if (statut == StatutPaiement.nonDefini) {
      return Text(
        "$nom : frais non définis pour la classe ${s.classeNom} (onglet « Frais par classe »).",
        style: const TextStyle(color: AppTheme.warning, fontSize: 13),
      );
    }
    return Row(
      children: [
        SizedBox(width: 82, child: Text(nom, style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(
          child: Text(
            "dû ${formatFcfa(s.du(type))} · payé ${formatFcfa(s.dejaPaye(type))}",
            style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
          ),
        ),
        Text("reste ${formatFcfa(s.reste(type))}",
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.error, fontSize: 13)),
        const SizedBox(width: 8),
        badgeStatut(statut),
      ],
    );
  }

  Widget _champMontant(String type) {
    final reste = s.reste(type);
    final payable = _payable(type);
    final label = type == Paiement.typeInscription ? "Montant inscription" : "Montant scolarité";
    return TextFormField(
      controller: _ctrl(type),
      enabled: payable,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: _type == _typeLesDeux ? label : "Montant versé *",
        suffixText: "FCFA",
        helperText: payable ? "Reste à payer : ${formatFcfa(reste)}" : "Rien à payer",
      ),
      validator: (v) {
        final texte = (v ?? '').trim();
        final m = texte.isEmpty ? 0.0 : parseMontant(texte);
        if (m == null || m < 0) return "Montant invalide";
        if (_type != _typeLesDeux && m <= 0) return "Entrez un montant valide";
        if (m > reste + 0.5) return "Dépasse le reste à payer (${formatFcfa(reste)})";
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bloque = !_typesConcernes.any(_payable);

    return AlertDialog(
      title: const Text("Enregistrer un paiement"),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.nomComplet, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text("${s.classeNom}${s.matricule != null ? ' · ${s.matricule}' : ''}",
                    style: const TextStyle(color: AppTheme.textLight)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      const ButtonSegment(value: Paiement.typeInscription, label: Text("Inscription")),
                      const ButtonSegment(value: Paiement.typeScolarite, label: Text("Scolarité")),
                      ButtonSegment(
                        value: _typeLesDeux,
                        label: const Text("Inscription + Scolarité"),
                        icon: const Icon(Icons.join_full_rounded, size: 16),
                        enabled: _lesDeuxPossible,
                      ),
                    ],
                    selected: {_type},
                    showSelectedIcon: false,
                    onSelectionChanged: (sel) => setState(() => _type = sel.first),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _typesConcernes.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        _blocSituation(_typesConcernes[i]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_type == _typeLesDeux)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _champMontant(Paiement.typeInscription)),
                      const SizedBox(width: 12),
                      Expanded(child: _champMontant(Paiement.typeScolarite)),
                    ],
                  )
                else
                  _champMontant(_type),
                if (_type == _typeLesDeux) ...[
                  const SizedBox(height: 8),
                  Text(
                    "Total encaissé sur ce reçu : ${formatFcfa(_total)}",
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.success),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: bloque
                            ? null
                            : () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _date,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now().add(const Duration(days: 1)),
                                );
                                if (d != null) setState(() => _date = d);
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Date du paiement",
                            suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                          ),
                          child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _mode,
                        decoration: const InputDecoration(labelText: "Mode de paiement"),
                        items: Paiement.modes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                        onChanged: bloque ? null : (v) => setState(() => _mode = v ?? Paiement.modes.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observationCtrl,
                  enabled: !bloque,
                  decoration: const InputDecoration(
                    labelText: "Observation (optionnel)",
                    hintText: "ex : 1ère tranche, versé par le père...",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Annuler")),
        ElevatedButton.icon(
          onPressed: (bloque || _enregistrement) ? null : _enregistrer,
          icon: _enregistrement
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_type == _typeLesDeux ? "Enregistrer (un seul reçu)" : "Enregistrer le paiement"),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Boîte de dialogue : choisir un élève
// ════════════════════════════════════════════════════════════════════

class _ChoixEleveDialog extends StatefulWidget {
  final List<SituationEleve> situations;

  const _ChoixEleveDialog({required this.situations});

  @override
  State<_ChoixEleveDialog> createState() => _ChoixEleveDialogState();
}

class _ChoixEleveDialogState extends State<_ChoixEleveDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = normaliser(_q);
    final liste = widget.situations
        .where((s) => q.isEmpty || normaliser('${s.nom} ${s.prenom} ${s.prenom} ${s.matricule ?? ''}').contains(q))
        .take(200)
        .toList();
    return AlertDialog(
      title: const Text("Choisir l'élève"),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: "Nom, prénom ou matricule", prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: liste.length,
                itemBuilder: (context, i) {
                  final s = liste[i];
                  return ListTile(
                    dense: true,
                    title: Text(s.nomComplet, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text("${s.classeNom} · reste ${formatFcfa(s.resteTotal)}"),
                    trailing: badgeStatut(s.statutScolarite),
                    onTap: () => Navigator.of(context).pop(s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Annuler")),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Boîte de dialogue : fiche de paiement d'un élève
// ════════════════════════════════════════════════════════════════════

class _FicheEleveDialog extends StatefulWidget {
  final int eleveId;
  final Future<void> Function(Paiement) onImprimerRecu;

  const _FicheEleveDialog({required this.eleveId, required this.onImprimerRecu});

  @override
  State<_FicheEleveDialog> createState() => _FicheEleveDialogState();
}

class _FicheEleveDialogState extends State<_FicheEleveDialog> {
  SituationEleve? _situation;
  List<Paiement> _paiements = [];
  bool _modifie = false;
  final _remiseCtrl = TextEditingController();
  final _telCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _charger(initial: true);
  }

  @override
  void dispose() {
    _remiseCtrl.dispose();
    _telCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger({bool initial = false}) async {
    final s = await ComptaService.situationEleve(widget.eleveId);
    final pmts = await ComptaService.paiementsEleve(widget.eleveId);
    if (!mounted) return;
    setState(() {
      _situation = s;
      _paiements = pmts;
      if (initial && s != null) {
        _remiseCtrl.text = s.remiseScolarite > 0 ? formatMontant(s.remiseScolarite) : '';
        _telCtrl.text = s.telephoneParent ?? '';
      }
    });
  }

  Future<void> _enregistrerInfos() async {
    final remise = _remiseCtrl.text.trim().isEmpty ? 0.0 : parseMontant(_remiseCtrl.text);
    if (remise == null || remise < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Remise invalide."), backgroundColor: AppTheme.error),
      );
      return;
    }
    await ComptaService.majRemise(widget.eleveId, remise);
    await ComptaService.majTelephoneParent(widget.eleveId, _telCtrl.text);
    _modifie = true;
    await _charger();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Informations enregistrées."), backgroundColor: AppTheme.success),
    );
  }

  Future<void> _nouveauPaiement() async {
    final s = _situation;
    if (s == null) return;
    final lignes = await showDialog<List<Paiement>>(context: context, builder: (_) => _PaiementDialog(situation: s));
    if (lignes == null || lignes.isEmpty) return;
    _modifie = true;
    await _charger();
    await widget.onImprimerRecu(lignes.first);
  }

  Future<void> _supprimer(Paiement pmt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ce paiement ?"),
        content: Text("${pmt.numeroRecu ?? ''} — ${formatFcfa(pmt.montant)} (${pmt.libelle.toLowerCase()})"),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Non")),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ComptaService.supprimerPaiement(pmt.id!);
    _modifie = true;
    await _charger();
  }

  Widget _resumeFrais(String titre, StatutPaiement statut, double du, double paye, double reste) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(titre, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              badgeStatut(statut),
            ]),
            const SizedBox(height: 6),
            Text("Dû : ${formatFcfa(du)}", style: const TextStyle(fontSize: 13)),
            Text("Payé : ${formatFcfa(paye)}", style: const TextStyle(fontSize: 13, color: AppTheme.success)),
            Text("Reste : ${formatFcfa(reste)}",
                style: const TextStyle(fontSize: 13, color: AppTheme.error, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _situation;
    return AlertDialog(
      title: Text(s == null ? "Fiche de paiement" : "Fiche de paiement — ${s.nomComplet}"),
      content: SizedBox(
        width: 720,
        height: 520,
        child: s == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${s.classeNom}${s.matricule != null ? ' · ${s.matricule}' : ''}",
                      style: const TextStyle(color: AppTheme.textLight)),
                  const SizedBox(height: 12),
                  Row(children: [
                    _resumeFrais("Inscription", s.statutInscription, s.duInscription, s.payeInscription, s.resteInscription),
                    const SizedBox(width: 12),
                    _resumeFrais("Scolarité", s.statutScolarite, s.duScolarite, s.payeScolarite, s.resteScolarite),
                  ]),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _remiseCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: "Remise sur la scolarité",
                            helperText: "Scolarité normale : ${formatFcfa(s.fraisScolarite)}",
                            suffixText: "FCFA",
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _telCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: "Téléphone du parent",
                            helperText: " ",
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(onPressed: _enregistrerInfos, child: const Text("Enregistrer")),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text("Historique des paiements", style: TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _nouveauPaiement,
                        icon: const Icon(Icons.add_card_rounded, size: 16),
                        label: const Text("Nouveau paiement"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _paiements.isEmpty
                        ? const Center(
                            child: Text("Aucun paiement enregistré.", style: TextStyle(color: AppTheme.textLight)))
                        : ListView.separated(
                            itemCount: _paiements.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final pmt = _paiements[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.receipt_rounded, color: AppTheme.primary),
                                title: Text("${formatFcfa(pmt.montant)} — ${pmt.libelle}",
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  "${DateFormat('dd/MM/yyyy').format(pmt.date)} · ${pmt.numeroRecu ?? ''} · ${pmt.mode ?? ''}"
                                  "${pmt.observation != null ? ' · ${pmt.observation}' : ''}",
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: "Imprimer le reçu",
                                      onPressed: () => widget.onImprimerRecu(pmt),
                                      icon: const Icon(Icons.print_rounded, size: 18, color: AppTheme.primary),
                                    ),
                                    IconButton(
                                      tooltip: "Supprimer",
                                      onPressed: () => _supprimer(pmt),
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        ElevatedButton(onPressed: () => Navigator.of(context).pop(_modifie), child: const Text("Fermer")),
      ],
    );
  }
}
