import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/classe.dart';
import '../models/cours.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import '../services/compta_utils.dart';

class CourseInputRow {
  int? id;
  final TextEditingController nameController;
  final TextEditingController coeffController;

  CourseInputRow({
    this.id,
    required String name,
    required String coeff,
  })  : nameController = TextEditingController(text: name),
        coeffController = TextEditingController(text: coeff);

  void dispose() {
    nameController.dispose();
    coeffController.dispose();
  }
}

class ClassFormScreen extends StatefulWidget {
  final Classe? classe;

  const ClassFormScreen({super.key, this.classe});

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _niveauController = TextEditingController();
  final _fraisInscController = TextEditingController();
  final _fraisScolController = TextEditingController();
  final List<CourseInputRow> _courseRows = [];
  int? _nextClassId;
  String _modeCalcul = Classe.modeSecondaire;
  bool get _isPrimaire => _modeCalcul == Classe.modePrimaire;
  bool _isLoading = false;

  final List<String> _predefinedNiveaux = [
    "Primaire",
    "Collège",
    "Lycée",
    "Supérieur",
  ];

  @override
  void initState() {
    super.initState();
    if (widget.classe != null) {
      _nextClassId = widget.classe!.nextClassId;
      _modeCalcul = widget.classe!.modeCalcul;
      if (widget.classe!.fraisInscription > 0) {
        _fraisInscController.text = formatMontant(widget.classe!.fraisInscription);
      }
      if (widget.classe!.fraisScolarite > 0) {
        _fraisScolController.text = formatMontant(widget.classe!.fraisScolarite);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.classe != null) {
        _nomController.text = widget.classe!.nom;
        _niveauController.text = widget.classe!.niveau;
        await context.read<AppStateProvider>().loadClassDetails(widget.classe!.id!);
        if (mounted) {
          final courses = context.read<AppStateProvider>().getCourses(widget.classe!.id!);
          setState(() {
            _courseRows.clear();
            for (var course in courses) {
              _courseRows.add(CourseInputRow(id: course.id, name: course.nom, coeff: course.coefficient.toString()));
            }
            if (_courseRows.isEmpty) _addCourseRow();
          });
        }
      } else {
        setState(() {
          _niveauController.text = _predefinedNiveaux.first;
          _modeCalcul = Classe.modePourNiveau(_niveauController.text);
          _addCourseRow();
        });
      }
    });
  }

  @override
  void dispose() {
    _nomController.dispose();
    _niveauController.dispose();
    _fraisInscController.dispose();
    _fraisScolController.dispose();
    for (var row in _courseRows) {
      row.dispose();
    }
    super.dispose();
  }

  String? _validerMontant(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final m = parseMontant(value);
    if (m == null || m < 0) return "Montant invalide";
    return null;
  }

  void _addCourseRow() {
    setState(() {
      _courseRows.add(CourseInputRow(name: '', coeff: '1'));
    });
  }

  void _removeCourseRow(int index) {
    if (_courseRows.length > 1) {
      setState(() {
        final row = _courseRows.removeAt(index);
        row.dispose();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Une classe doit comporter au moins une matière."), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      if (_courseRows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Veuillez ajouter au moins une matière."), backgroundColor: AppTheme.error),
        );
        return;
      }
      setState(() => _isLoading = true);
      final classe = Classe(
        id: widget.classe?.id,
        nom: _nomController.text.trim(),
        niveau: _niveauController.text.trim(),
        nextClassId: _nextClassId,
        modeCalcul: _modeCalcul,
        fraisInscription: parseMontant(_fraisInscController.text) ?? 0,
        fraisScolarite: parseMontant(_fraisScolController.text) ?? 0,
      );
      final List<Cours> coursList = _courseRows.map((row) {
        return Cours(
          id: row.id,
          nom: row.nameController.text.trim(),
          coefficient: _isPrimaire ? 1 : int.parse(row.coeffController.text.trim()),
          classeId: widget.classe?.id ?? 0,
        );
      }).toList();
      try {
        await context.read<AppStateProvider>().saveClasse(classe, coursList);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.classe == null ? "Classe créée avec succès !" : "Classe mise à jour avec succès !"),
              backgroundColor: AppTheme.success,
            ),
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
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.classe != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isEditing ? "Modifier la classe" : "Créer une classe"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // General Class Details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.school_rounded, size: 20, color: AppTheme.primary),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Informations de la Classe",
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _nomController,
                                  decoration: const InputDecoration(
                                    labelText: "Nom de la classe *",
                                    hintText: "ex: Terminale Scientifique A",
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) return "Veuillez entrer le nom de la classe";
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _niveauController.text.isNotEmpty ? _niveauController.text : null,
                                  items: [
                                    ..._predefinedNiveaux,
                                    if (_niveauController.text.isNotEmpty &&
                                        !_predefinedNiveaux.contains(_niveauController.text))
                                      _niveauController.text,
                                  ].map((niv) => DropdownMenuItem(value: niv, child: Text(niv))).toList(),
                                  decoration: const InputDecoration(labelText: "Niveau *"),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _niveauController.text = val;
                                        _modeCalcul = Classe.modePourNiveau(val);
                                      });
                                    }
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return "Sélectionnez un niveau";
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text("Mode de calcul des moyennes", style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: Classe.modePrimaire,
                                icon: Icon(Icons.child_care_rounded),
                                label: Text("Primaire (1ère à 6ème)"),
                              ),
                              ButtonSegment(
                                value: Classe.modeSecondaire,
                                icon: Icon(Icons.school_rounded),
                                label: Text("Secondaire (7ème à 12ème)"),
                              ),
                            ],
                            selected: {_modeCalcul},
                            onSelectionChanged: (sel) => setState(() => _modeCalcul = sel.first),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isPrimaire
                                ? "Note de composition sur 10. Moyenne = somme des notes / nombre de matières (sans coefficient)."
                                : "Note de classe /20 + composition /40. Moyenne du cours = total / 3, puis moyenne pondérée par les coefficients.",
                            style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                          Builder(
                            builder: (context) {
                              final allClasses = context.watch<AppStateProvider>().classes;
                              final selectableClasses = allClasses.where((c) => c.id != widget.classe?.id).toList();
                              if (_nextClassId != null && !selectableClasses.any((c) => c.id == _nextClassId)) {
                                _nextClassId = null;
                              }
                              return DropdownButtonFormField<int?>(
                                initialValue: _nextClassId,
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text("Aucune (Élèves diplômés / Sortants)"),
                                  ),
                                  ...selectableClasses.map((c) => DropdownMenuItem<int?>(
                                        value: c.id,
                                        child: Text("${c.nom} (${c.niveau})"),
                                      )),
                                ],
                                decoration: const InputDecoration(
                                  labelText: "Classe supérieure de destination",
                                  helperText: "Classe dans laquelle les élèves admis seront promus.",
                                ),
                                onChanged: (val) => setState(() => _nextClassId = val),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Fees Card (comptabilité)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.payments_rounded, size: 20, color: AppTheme.accent),
                              ),
                              const SizedBox(width: 12),
                              Text("Frais scolaires", style: Theme.of(context).textTheme.titleLarge),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "Montants exigés pour chaque élève de cette classe (utilisés par le module Comptabilité). "
                            "Laissez vide si non applicable.",
                            style: TextStyle(color: AppTheme.textLight, fontSize: 13),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _fraisInscController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: "Frais d'inscription",
                                    hintText: "ex: 10 000",
                                    suffixText: "FCFA",
                                  ),
                                  validator: _validerMontant,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: TextFormField(
                                  controller: _fraisScolController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: "Frais de scolarité (année)",
                                    hintText: "ex: 90 000",
                                    suffixText: "FCFA",
                                  ),
                                  validator: _validerMontant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Subjects Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.menu_book_rounded, size: 20, color: AppTheme.secondary),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _isPrimaire ? "Matières" : "Matières & Coefficients",
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: _addCourseRow,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.secondary,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text("Ajouter"),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isPrimaire
                                ? "Saisissez les matières enseignées."
                                : "Saisissez les matières enseignées et leurs coefficients.",
                            style: TextStyle(color: AppTheme.textLight, fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _courseRows.length,
                            itemBuilder: (context, index) {
                              final row = _courseRows[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [AppTheme.primary, AppTheme.primaryLight],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        "${index + 1}",
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      flex: 4,
                                      child: TextFormField(
                                        controller: row.nameController,
                                        decoration: const InputDecoration(
                                          labelText: "Nom de la matière *",
                                          hintText: "Mathématiques, Français...",
                                        ),
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) return "Nom requis";
                                          return null;
                                        },
                                      ),
                                    ),
                                    if (!_isPrimaire) const SizedBox(width: 14),
                                    if (!_isPrimaire)
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: row.coeffController,
                                        decoration: const InputDecoration(labelText: "Coefficient *"),
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) return "Requis";
                                          final val = int.tryParse(value);
                                          if (val == null || val <= 0) return "> 0";
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Tooltip(
                                      message: "Retirer la matière",
                                      child: Material(
                                        color: AppTheme.error.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(10),
                                        child: InkWell(
                                          onTap: () => _removeCourseRow(index),
                                          borderRadius: BorderRadius.circular(10),
                                          child: const Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Annuler"),
                      ),
                      const SizedBox(width: 14),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _save,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(isEditing ? "Enregistrer les modifications" : "Enregistrer la classe"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
