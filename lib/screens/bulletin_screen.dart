import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/eleve.dart';
import '../models/cours.dart';
import '../models/note.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import '../services/pdf_service.dart';

class BulletinScreen extends StatefulWidget {
  final Eleve eleve;
  final int classId;

  const BulletinScreen({
    super.key,
    required this.eleve,
    required this.classId,
  });

  @override
  State<BulletinScreen> createState() => _BulletinScreenState();
}

class _BulletinScreenState extends State<BulletinScreen> {
  int _selectedTrimestre = 1;
  bool _isLoading = false;
  List<Note> _notes = [];
  List<Cours> _courses = [];
  double? _moyenneGenerale;
  String _rankString = "N/A";
  int _classSize = 0;

  @override
  void initState() {
    super.initState();
    _courses = context.read<AppStateProvider>().getCourses(widget.classId);
    _loadBulletinData();
  }

  Future<void> _loadBulletinData() async {
    setState(() => _isLoading = true);
    try {
      final state = context.read<AppStateProvider>();
      await state.loadClassDetails(widget.classId);
      final eleves = state.getEleves(widget.classId);
      _classSize = eleves.length;
      _notes = await state.getNotesForEleve(widget.eleve.id!, _selectedTrimestre);
      _moyenneGenerale = await state.calculateMoyenneGenerale(widget.eleve.id!, widget.classId, _selectedTrimestre);
      final ranks = await state.calculateRanks(widget.classId, _selectedTrimestre);
      _rankString = ranks[widget.eleve.id!] ?? "Non classé";
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de chargement du bulletin : $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatDouble(double val) {
    if (val == val.toInt()) return val.toInt().toString();
    return val.toStringAsFixed(2);
  }

  Future<void> _generatePDF() async {
    final state = context.read<AppStateProvider>();
    final etab = state.etablissement;
    if (etab == null || etab.nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Veuillez configurer les paramètres de l'établissement d'abord !"),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await PDFService.generateAndPreview(
        context: context,
        etablissement: etab,
        eleve: widget.eleve,
        className: state.classes.firstWhere((c) => c.id == widget.classId).nom,
        primaire: state.isClassePrimaire(widget.classId),
        courses: _courses,
        notes: _notes,
        moyenneGenerale: _moyenneGenerale,
        rang: _rankString,
        effectif: _classSize,
        trimestre: _selectedTrimestre,
        anneeScolaire: state.selectedAnneeScolaire?.libelle,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de génération PDF : $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final classe = state.classes.firstWhere((c) => c.id == widget.classId);
    final className = classe.nom;
    final primaire = classe.isPrimaire;
    final bareme = classe.bareme;
    final seuilPassage = bareme / 2; // 10/20 ou 5/10
    final seuilBien = bareme * 0.6; // 12/20 ou 6/10
    final hasNoGrades = _notes.isEmpty || _moyenneGenerale == null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("Bulletin Scolaire"),
        actions: [
          if (!hasNoGrades)
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _generatePDF,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text("Générer & Imprimer PDF"),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Trimester selector
                Container(
                  color: AppTheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text("Période : ", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                          const SizedBox(width: 12),
                          _buildTrimestreButton(1, "1er Trimestre"),
                          const SizedBox(width: 6),
                          _buildTrimestreButton(2, "2e Trimestre"),
                          const SizedBox(width: 6),
                          _buildTrimestreButton(3, "3e Trimestre"),
                        ],
                      ),
                      Text(
                        "Effectif : $_classSize élèves",
                        style: const TextStyle(fontWeight: FontWeight.w500, color: AppTheme.textLight, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 950),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Student Identity Card
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [AppTheme.primary, AppTheme.primaryLight],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Center(
                                        child: Text(
                                          "${widget.eleve.prenom.isNotEmpty ? widget.eleve.prenom[0] : ''}${widget.eleve.nom.isNotEmpty ? widget.eleve.nom[0] : ''}",
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "${widget.eleve.prenom} ${widget.eleve.nom}",
                                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: [
                                              _buildBadge("Classe: $className"),
                                              _buildBadge("Matricule: ${widget.eleve.matricule ?? 'N/A'}"),
                                              if (widget.eleve.dateNaissance != null)
                                                _buildBadge("Né(e) le: ${widget.eleve.dateNaissance!}"),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Grades Table
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Relevé des notes — ${_selectedTrimestre == 1 ? '1er' : '${_selectedTrimestre}e'} Trimestre",
                                      style: Theme.of(context).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 20),
                                    if (hasNoGrades)
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 48),
                                          child: Column(
                                            children: [
                                              Icon(Icons.info_outline_rounded, size: 48, color: AppTheme.textLight.withValues(alpha: 0.4)),
                                              const SizedBox(height: 16),
                                              const Text(
                                                "Aucune note enregistrée pour ce trimestre",
                                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                              ),
                                              const SizedBox(height: 6),
                                              const Text(
                                                "Veuillez d'abord saisir les notes depuis l'écran précédent.",
                                                style: TextStyle(color: AppTheme.textLight),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      Column(
                                        children: [
                                          Table(
                                            columnWidths: primaire
                                                ? const {
                                                    0: FlexColumnWidth(4),
                                                    1: FlexColumnWidth(2),
                                                  }
                                                : const {
                                                    0: FlexColumnWidth(4),
                                                    1: FixedColumnWidth(90),
                                                    2: FlexColumnWidth(2),
                                                    3: FlexColumnWidth(2),
                                                    4: FlexColumnWidth(2),
                                                  },
                                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                            children: [
                                              TableRow(
                                                decoration: BoxDecoration(
                                                  border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.8), width: 1.5)),
                                                ),
                                                children: [
                                                  _buildTableHeaderCell("Matière"),
                                                  if (!primaire) _buildTableHeaderCell("Coef"),
                                                  if (!primaire) _buildTableHeaderCell("Classe /20"),
                                                  _buildTableHeaderCell(primaire ? "Note /10" : "Compo /40"),
                                                  if (!primaire) _buildTableHeaderCell("Moyenne"),
                                                ],
                                              ),
                                              ..._courses.map((course) {
                                                final noteOpt = _notes.where((n) => n.coursId == course.id).toList();
                                                final Note? note = noteOpt.isNotEmpty ? noteOpt.first : null;
                                                final avg = note?.moyenneCours;

                                                return TableRow(
                                                  decoration: const BoxDecoration(
                                                    border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
                                                  ),
                                                  children: [
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                                      child: Text(course.nom, style: const TextStyle(fontWeight: FontWeight.w500, color: AppTheme.textDark)),
                                                    ),
                                                    if (!primaire) Center(child: Text(course.coefficient.toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                                                    if (!primaire) Center(child: Text(note?.noteClasse != null ? _formatDouble(note!.noteClasse!) : "-")),
                                                    Center(child: Text(note?.noteComposition != null ? _formatDouble(note!.noteComposition!) : "-")),
                                                    if (!primaire) Center(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: avg != null
                                                              ? (avg >= seuilPassage ? AppTheme.success : AppTheme.error).withValues(alpha: 0.06)
                                                              : Colors.transparent,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          avg != null ? _formatDouble(avg) : "-",
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.w700,
                                                            color: avg != null
                                                                ? (avg >= seuilPassage ? AppTheme.success : AppTheme.error)
                                                                : AppTheme.textLight.withValues(alpha: 0.4),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }),
                                            ],
                                          ),
                                          const SizedBox(height: 28),
                                          // Summary KPIs
                                          Row(
                                            children: [
                                              Expanded(child: _buildKpiTile("Moyenne Générale",
                                                _moyenneGenerale != null ? "${_formatDouble(_moyenneGenerale!)} / $bareme" : "-",
                                                AppTheme.primary)),
                                              const SizedBox(width: 12),
                                              Expanded(child: _buildKpiTile("Mention",
                                                _moyenneGenerale != null ? AppStateProvider.getMention(_moyenneGenerale!, bareme: bareme) : "-",
                                                _moyenneGenerale != null
                                                    ? (_moyenneGenerale! >= seuilBien ? AppTheme.success
                                                        : (_moyenneGenerale! >= seuilPassage ? AppTheme.secondary : AppTheme.error))
                                                    : AppTheme.textLight)),
                                              const SizedBox(width: 12),
                                              Expanded(child: _buildKpiTile("Rang",
                                                "$_rankString / $_classSize",
                                                AppTheme.accent)),
                                            ],
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildKpiTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textLight, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildTrimestreButton(int trim, String label) {
    final isSelected = _selectedTrimestre == trim;
    return InkWell(
      onTap: () {
        if (_selectedTrimestre != trim) {
          setState(() => _selectedTrimestre = trim);
          _loadBulletinData();
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textLight,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Text(text, style: const TextStyle(color: AppTheme.textMedium, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textLight, fontSize: 12, letterSpacing: 0.2),
        textAlign: text == "Matière" ? TextAlign.left : TextAlign.center,
      ),
    );
  }
}
