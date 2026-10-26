import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/eleve.dart';
import '../models/cours.dart';
import '../models/note.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';

class NotesEntryScreen extends StatefulWidget {
  final Eleve eleve;
  final int classId;
  final String className;

  const NotesEntryScreen({
    super.key,
    required this.eleve,
    required this.classId,
    required this.className,
  });

  @override
  State<NotesEntryScreen> createState() => _NotesEntryScreenState();
}

class _NotesEntryScreenState extends State<NotesEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  int _selectedTrimestre = 1;
  List<Cours> _courses = [];
  bool _isLoading = false;
  bool _isSaving = false;

  final Map<int, TextEditingController> _classNoteControllers = {};
  final Map<int, TextEditingController> _compNoteControllers = {};
  final Map<int, FocusNode> _classNoteFocus = {};
  final Map<int, FocusNode> _compNoteFocus = {};

  late final bool _primaire;
  int get _bareme => _primaire ? 10 : 20;

  double? _generalAverage;
  int _completedCoursesCount = 0;
  final Map<int, double> _courseAverages = {};

  @override
  void initState() {
    super.initState();
    _primaire = context.read<AppStateProvider>().isClassePrimaire(widget.classId);
    _courses = context.read<AppStateProvider>().getCourses(widget.classId);
    for (var course in _courses) {
      _classNoteControllers[course.id!] = TextEditingController();
      _compNoteControllers[course.id!] = TextEditingController();
      _classNoteFocus[course.id!] = FocusNode();
      _compNoteFocus[course.id!] = FocusNode();
      _classNoteControllers[course.id!]!.addListener(_recalculate);
      _compNoteControllers[course.id!]!.addListener(_recalculate);
    }
    _loadNotesForTrimestre(_selectedTrimestre);
  }

  @override
  void dispose() {
    for (var course in _courses) {
      _classNoteControllers[course.id!]!.removeListener(_recalculate);
      _compNoteControllers[course.id!]!.removeListener(_recalculate);
      _classNoteControllers[course.id!]!.dispose();
      _compNoteControllers[course.id!]!.dispose();
      _classNoteFocus[course.id!]!.dispose();
      _compNoteFocus[course.id!]!.dispose();
    }
    super.dispose();
  }

  String _formatDouble(double val) {
    if (val == val.toInt()) return val.toInt().toString();
    return val.toStringAsFixed(2);
  }

  void _recalculate() {
    double totalWeightedPoints = 0;
    int totalCoefficients = 0;
    int completedCount = 0;
    _courseAverages.clear();

    for (var course in _courses) {
      final classStr = _classNoteControllers[course.id!]!.text.replaceAll(',', '.');
      final compStr = _compNoteControllers[course.id!]!.text.replaceAll(',', '.');
      final classNote = double.tryParse(classStr);
      final compNote = double.tryParse(compStr);

      if (_primaire) {
        // Primaire : seule la composition (sur 10) compte, sans coefficient
        if (compNote != null && compNote >= 0 && compNote <= 10) {
          _courseAverages[course.id!] = compNote;
          totalWeightedPoints += compNote;
          totalCoefficients += 1;
          completedCount++;
        }
      } else if (classNote != null && compNote != null &&
          classNote >= 0 && classNote <= 20 &&
          compNote >= 0 && compNote <= 40) {
        final avg = (classNote + compNote) / 3;
        _courseAverages[course.id!] = avg;
        totalWeightedPoints += avg * course.coefficient;
        totalCoefficients += course.coefficient;
        completedCount++;
      }
    }

    setState(() {
      _completedCoursesCount = completedCount;
      if (completedCount > 0 && totalCoefficients > 0) {
        _generalAverage = totalWeightedPoints / totalCoefficients;
      } else {
        _generalAverage = null;
      }
    });
  }

  Future<void> _loadNotesForTrimestre(int trim) async {
    setState(() => _isLoading = true);
    try {
      final notes = await context.read<AppStateProvider>().getNotesForEleve(widget.eleve.id!, trim);
      for (var course in _courses) {
        _classNoteControllers[course.id!]!.text = '';
        _compNoteControllers[course.id!]!.text = '';
      }
      for (var note in notes) {
        if (note.noteClasse != null) {
          _classNoteControllers[note.coursId]!.text = _formatDouble(note.noteClasse!);
        }
        if (note.noteComposition != null) {
          _compNoteControllers[note.coursId]!.text = _formatDouble(note.noteComposition!);
        }
      }
      _selectedTrimestre = trim;
      _recalculate();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du chargement des notes : $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      final List<Note> notesToSave = [];
      for (var course in _courses) {
        final classStr = _classNoteControllers[course.id!]!.text.replaceAll(',', '.');
        final compStr = _compNoteControllers[course.id!]!.text.replaceAll(',', '.');
        notesToSave.add(Note(
          eleveId: widget.eleve.id!,
          coursId: course.id!,
          trimestre: _selectedTrimestre,
          noteClasse: _primaire ? null : double.tryParse(classStr),
          noteComposition: double.tryParse(compStr),
        ));
      }
      try {
        await context.read<AppStateProvider>().saveNotes(
          widget.eleve.id!, widget.classId, _selectedTrimestre, notesToSave,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notes enregistrées avec succès !'), backgroundColor: AppTheme.success),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur d'enregistrement : $e"), backgroundColor: AppTheme.error),
          );
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  String? _validateClassNote(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final cleanValue = value.trim().replaceAll(',', '.');
    final note = double.tryParse(cleanValue);
    if (note == null) return "Nombre invalide";
    if (note < 0 || note > 20) return "Entre 0 et 20";
    return null;
  }

  String? _validateCompNote(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final cleanValue = value.trim().replaceAll(',', '.');
    final note = double.tryParse(cleanValue);
    if (note == null) return "Nombre invalide";
    final max = _primaire ? 10 : 40;
    if (note < 0 || note > max) return "Entre 0 et $max";
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final isActive = state.isCurrentYearActive;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          isActive
              ? "Saisie des Notes : ${widget.eleve.prenom} ${widget.eleve.nom}"
              : "Consultation : ${widget.eleve.prenom} ${widget.eleve.nom}",
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top Bar: Trimester
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
                          _buildTrimestreButton(1, "T1"),
                          const SizedBox(width: 6),
                          _buildTrimestreButton(2, "T2"),
                          const SizedBox(width: 6),
                          _buildTrimestreButton(3, "T3"),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Classe : ${widget.className}",
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                // Main Form
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "Grille d'évaluation",
                                            style: Theme.of(context).textTheme.titleLarge,
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: _completedCoursesCount == _courses.length && _courses.isNotEmpty
                                                  ? AppTheme.success.withValues(alpha: 0.08)
                                                  : AppTheme.surfaceAlt,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              "$_completedCoursesCount / ${_courses.length} matières",
                                              style: TextStyle(
                                                color: _completedCoursesCount == _courses.length && _courses.isNotEmpty
                                                    ? AppTheme.success
                                                    : AppTheme.textLight,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Table(
                                        columnWidths: _primaire
                                            ? const {
                                                0: FlexColumnWidth(3),
                                                1: FlexColumnWidth(2),
                                              }
                                            : const {
                                                0: FlexColumnWidth(3),
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
                                              if (!_primaire) _buildTableHeaderCell("Coef"),
                                              if (!_primaire) _buildTableHeaderCell("Classe /20"),
                                              _buildTableHeaderCell(_primaire ? "Composition /10" : "Compo /40"),
                                              if (!_primaire) _buildTableHeaderCell("Moyenne"),
                                            ],
                                          ),
                                          ..._courses.map((course) {
                                            final avg = _courseAverages[course.id];
                                            return TableRow(
                                              decoration: const BoxDecoration(
                                                border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
                                              ),
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                  child: Text(
                                                    course.nom,
                                                    style: const TextStyle(fontWeight: FontWeight.w500, color: AppTheme.textDark, fontSize: 13),
                                                  ),
                                                ),
                                                if (!_primaire)
                                                Center(
                                                  child: Text(
                                                    course.coefficient.toString(),
                                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textMedium),
                                                  ),
                                                ),
                                                if (!_primaire)
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                                  child: TextFormField(
                                                    controller: _classNoteControllers[course.id],
                                                    focusNode: _classNoteFocus[course.id],
                                                    readOnly: !isActive,
                                                    decoration: const InputDecoration(
                                                      hintText: "-",
                                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    validator: _validateClassNote,
                                                    onFieldSubmitted: (_) {
                                                      FocusScope.of(context).requestFocus(_compNoteFocus[course.id]);
                                                    },
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                                  child: TextFormField(
                                                    controller: _compNoteControllers[course.id],
                                                    focusNode: _compNoteFocus[course.id],
                                                    readOnly: !isActive,
                                                    decoration: const InputDecoration(
                                                      hintText: "-",
                                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    validator: _validateCompNote,
                                                    onFieldSubmitted: (_) {
                                                      final currentIndex = _courses.indexOf(course);
                                                      if (currentIndex + 1 < _courses.length) {
                                                        final nextCourse = _courses[currentIndex + 1];
                                                        FocusScope.of(context).requestFocus(
                                                          _primaire ? _compNoteFocus[nextCourse.id] : _classNoteFocus[nextCourse.id],
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ),
                                                if (!_primaire)
                                                Center(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: avg != null
                                                          ? (avg >= 10 ? AppTheme.success : AppTheme.error).withValues(alpha: 0.06)
                                                          : Colors.transparent,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      avg != null ? _formatDouble(avg) : "-",
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        color: avg != null
                                                            ? (avg >= 10 ? AppTheme.success : AppTheme.error)
                                                            : AppTheme.textLight.withValues(alpha: 0.4),
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Summary bar
                              Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppTheme.primary, AppTheme.primaryDark],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(alpha: 0.2),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(Icons.stars_rounded, color: Colors.white, size: 24),
                                          ),
                                          const SizedBox(width: 16),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                isActive ? "Moyenne Générale Provisoire" : "Moyenne Générale",
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _generalAverage != null
                                                    ? "${_formatDouble(_generalAverage!)} / $_bareme"
                                                    : "Saisie incomplète",
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if (isActive)
                                        ElevatedButton.icon(
                                          onPressed: _isSaving ? null : _save,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor: AppTheme.primary,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                          ),
                                          icon: _isSaving
                                              ? const SizedBox(
                                                  width: 18, height: 18,
                                                  child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                                                )
                                              : const Icon(Icons.check_circle_outline_rounded),
                                          label: const Text("Enregistrer"),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.lock_outline_rounded, color: Colors.white.withValues(alpha: 0.6), size: 16),
                                              const SizedBox(width: 8),
                                              Text(
                                                "Archive (Lecture seule)",
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600, fontSize: 12),
                                              ),
                                            ],
                                          ),
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
                ),
              ],
            ),
    );
  }

  Widget _buildTrimestreButton(int trim, String label) {
    final isSelected = _selectedTrimestre == trim;
    return InkWell(
      onTap: () {
        if (_selectedTrimestre != trim) _loadNotesForTrimestre(trim);
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
