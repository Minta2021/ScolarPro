import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/eleve.dart';
import '../models/cours.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import '../services/pdf_service.dart';
import 'notes_entry_screen.dart';
import 'bulletin_screen.dart';
import 'import_eleves_screen.dart';
import 'saisie_notes_classe_screen.dart';

class ClassDetailScreen extends StatefulWidget {
  final int classId;
  final String className;

  const ClassDetailScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  int _selectedTrimestre = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStateProvider>().loadClassDetails(widget.classId, trimestre: _selectedTrimestre);
    });
  }

  void _showAddEleveDialog() {
    final formKey = GlobalKey<FormState>();
    final nomController = TextEditingController();
    final prenomController = TextEditingController();
    final matriculeController = TextEditingController();
    final dateController = TextEditingController();
    final telParentController = TextEditingController();
    String? selectedPhotoPath;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Ajouter un nouvel élève"),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 45,
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                              backgroundImage: selectedPhotoPath != null
                                  ? FileImage(File(selectedPhotoPath!))
                                  : null,
                              child: selectedPhotoPath == null
                                  ? const Icon(Icons.person_rounded, size: 48, color: AppTheme.primary)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () async {
                                  try {
                                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                                    );
                                    if (result != null && result.files.single.path != null) {
                                      final originalFile = File(result.files.single.path!);
                                      final appDir = await getApplicationSupportDirectory();
                                      await appDir.create(recursive: true);
                                      final extension = p.extension(originalFile.path);
                                      final fileName = 'eleve_${DateTime.now().millisecondsSinceEpoch}$extension';
                                      final destinationPath = p.join(appDir.path, fileName);
                                      await originalFile.copy(destinationPath);
                                      setStateDialog(() {
                                        selectedPhotoPath = destinationPath;
                                      });
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Erreur lors de la sélection de la photo: $e')),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                            if (selectedPhotoPath != null)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () {
                                    setStateDialog(() {
                                      selectedPhotoPath = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle),
                                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: nomController,
                        decoration: const InputDecoration(labelText: "Nom de famille *", hintText: "Nom"),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return "Veuillez entrer le nom";
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: prenomController,
                        decoration: const InputDecoration(labelText: "Prénom *", hintText: "Prénom"),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return "Veuillez entrer le prénom";
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: matriculeController,
                        decoration: const InputDecoration(labelText: "Matricule (optionnel)", hintText: "ex: MAT-2026-001"),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: dateController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: "Date de naissance (optionnelle)",
                          hintText: "JJ/MM/AAAA",
                          suffixIcon: Icon(Icons.calendar_today_rounded, size: 20),
                        ),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().subtract(const Duration(days: 365 * 15)),
                            firstDate: DateTime(1990),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            dateController.text = DateFormat('dd/MM/yyyy').format(date);
                            setStateDialog(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: telParentController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: "Téléphone du parent (optionnel)",
                          hintText: "ex: 76 12 34 56",
                          prefixIcon: Icon(Icons.phone_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _importElevesFromExcel();
                  },
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text("Importer une fiche Excel"),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("Annuler"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final newEleve = Eleve(
                        nom: nomController.text.trim().toUpperCase(),
                        prenom: prenomController.text.trim(),
                        classeId: widget.classId,
                        matricule: matriculeController.text.trim().isEmpty ? null : matriculeController.text.trim(),
                        dateNaissance: dateController.text.isEmpty ? null : dateController.text,
                        photoPath: selectedPhotoPath,
                        telephoneParent: telParentController.text.trim().isEmpty ? null : telParentController.text.trim(),
                      );
                      Navigator.of(ctx).pop();
                      try {
                        await context.read<AppStateProvider>().addEleve(newEleve);
                        if (!context.mounted) return;
                        context.read<AppStateProvider>().loadClassDetails(widget.classId, trimestre: _selectedTrimestre);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Élève ajouté avec succès.'), backgroundColor: AppTheme.success),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erreur lors de l\'ajout : $e'), backgroundColor: AppTheme.error),
                        );
                      }
                    }
                  },
                  child: const Text("Ajouter"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // EXCEL IMPORT (assistant commun à toute l'application)
  // ==========================================
  Future<void> _importElevesFromExcel() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ImportElevesScreen(classeCibleId: widget.classId),
      ),
    );
    if (imported == true && mounted) {
      context.read<AppStateProvider>().loadClassDetails(widget.classId, trimestre: _selectedTrimestre);
    }
  }

  void _showEditEleveDialog(Eleve eleve) {
    final formKey = GlobalKey<FormState>();
    final nomController = TextEditingController(text: eleve.nom);
    final prenomController = TextEditingController(text: eleve.prenom);
    final matriculeController = TextEditingController(text: eleve.matricule ?? '');
    final dateController = TextEditingController(text: eleve.dateNaissance ?? '');
    final telParentController = TextEditingController(text: eleve.telephoneParent ?? '');
    String? selectedPhotoPath = eleve.photoPath;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Modifier les informations de l'élève"),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 45,
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                              backgroundImage: selectedPhotoPath != null
                                  ? FileImage(File(selectedPhotoPath!))
                                  : null,
                              child: selectedPhotoPath == null
                                  ? const Icon(Icons.person_rounded, size: 48, color: AppTheme.primary)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () async {
                                  try {
                                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                                    );
                                    if (result != null && result.files.single.path != null) {
                                      final originalFile = File(result.files.single.path!);
                                      final appDir = await getApplicationSupportDirectory();
                                      await appDir.create(recursive: true);
                                      final extension = p.extension(originalFile.path);
                                      final fileName = 'eleve_${DateTime.now().millisecondsSinceEpoch}$extension';
                                      final destinationPath = p.join(appDir.path, fileName);
                                      await originalFile.copy(destinationPath);
                                      setStateDialog(() {
                                        selectedPhotoPath = destinationPath;
                                      });
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Erreur lors de la sélection de la photo: $e')),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                            if (selectedPhotoPath != null)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () {
                                    setStateDialog(() {
                                      selectedPhotoPath = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle),
                                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (selectedPhotoPath != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              final originalFile = File(selectedPhotoPath!);
                              if (originalFile.existsSync()) {
                                String? outputFile = await FilePicker.platform.saveFile(
                                  dialogTitle: 'Exporter la photo de l\'élève',
                                  fileName: 'photo_${nomController.text.trim()}_${prenomController.text.trim()}${p.extension(originalFile.path)}',
                                  type: FileType.custom,
                                  allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                                );
                                if (outputFile != null) {
                                  await originalFile.copy(outputFile);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Photo exportée avec succès.'), backgroundColor: AppTheme.success),
                                  );
                                }
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erreur lors de l\'exportation de la photo: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text("Exporter la photo de l'élève"),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nomController,
                        decoration: const InputDecoration(labelText: "Nom de famille *", hintText: "Nom"),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return "Veuillez entrer le nom";
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: prenomController,
                        decoration: const InputDecoration(labelText: "Prénom *", hintText: "Prénom"),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return "Veuillez entrer le prénom";
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: matriculeController,
                        decoration: const InputDecoration(labelText: "Matricule (optionnel)", hintText: "ex: MAT-2026-001"),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: dateController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: "Date de naissance (optionnelle)",
                          hintText: "JJ/MM/AAAA",
                          suffixIcon: Icon(Icons.calendar_today_rounded, size: 20),
                        ),
                        onTap: () async {
                          DateTime initialDate;
                          if (dateController.text.isNotEmpty) {
                            try {
                              initialDate = DateFormat('dd/MM/yyyy').parse(dateController.text);
                            } catch (e) {
                              initialDate = DateTime.now().subtract(const Duration(days: 365 * 15));
                            }
                          } else {
                            initialDate = DateTime.now().subtract(const Duration(days: 365 * 15));
                          }
                          final date = await showDatePicker(
                            context: context,
                            initialDate: initialDate,
                            firstDate: DateTime(1990),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            dateController.text = DateFormat('dd/MM/yyyy').format(date);
                            setStateDialog(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: telParentController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: "Téléphone du parent (optionnel)",
                          hintText: "ex: 76 12 34 56",
                          prefixIcon: Icon(Icons.phone_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("Annuler"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final updatedEleve = Eleve(
                        id: eleve.id,
                        nom: nomController.text.trim().toUpperCase(),
                        prenom: prenomController.text.trim(),
                        classeId: widget.classId,
                        matricule: matriculeController.text.trim().isEmpty ? null : matriculeController.text.trim(),
                        dateNaissance: dateController.text.isEmpty ? null : dateController.text,
                        photoPath: selectedPhotoPath,
                        telephoneParent: telParentController.text.trim().isEmpty ? null : telParentController.text.trim(),
                        // la remise (comptabilité) est conservée
                        remiseScolarite: eleve.remiseScolarite,
                      );
                      Navigator.of(ctx).pop();
                      try {
                        await context.read<AppStateProvider>().updateEleve(
                              updatedEleve,
                              currentTrimestre: _selectedTrimestre,
                            );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Informations de l\'élève mises à jour.'), backgroundColor: AppTheme.success),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erreur lors de la mise à jour : $e'), backgroundColor: AppTheme.error),
                        );
                      }
                    }
                  },
                  child: const Text("Enregistrer"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteEleve(Eleve eleve) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Retirer l'élève ?"),
        content: Text(
          "Êtes-vous sûr de vouloir supprimer l'élève '${eleve.prenom} ${eleve.nom}' de la classe ? "
          "Cette action supprimera également toutes ses notes et ses paiements de manière définitive.",
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await context.read<AppStateProvider>().deleteEleve(eleve.id!, widget.classId);
                if (!mounted) return;
                context.read<AppStateProvider>().loadClassDetails(widget.classId, trimestre: _selectedTrimestre);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Élève retiré avec succès.'), backgroundColor: AppTheme.success),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erreur de suppression : $e'), backgroundColor: AppTheme.error),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );
  }

  /// Saisie des notes de toute la classe pour une matière (tableau élèves × notes).
  Future<void> _ouvrirSaisieParMatiere({int? coursId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaisieNotesClasseScreen(
          classId: widget.classId,
          className: widget.className,
          coursInitialId: coursId,
          trimestreInitial: _selectedTrimestre,
        ),
      ),
    );
    if (!mounted) return;
    context.read<AppStateProvider>().loadClassDetails(widget.classId, trimestre: _selectedTrimestre);
  }

  Future<void> _generateAllBulletins(List<Eleve> eleves, List<Cours> courses) async {
    final eligible = eleves.where((e) => e.notesCount == courses.length).toList();
    if (eligible.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Aucun bulletin complet"),
          content: Text(
            "Aucun élève de cette classe n'a reçu des notes complètes pour l'ensemble des "
            "${courses.length} matières au ${_selectedTrimestre == 1 ? '1er' : '${_selectedTrimestre}e'} trimestre.\n\n"
            "Seuls les élèves ayant reçu une moyenne dans toutes les matières d'une classe peuvent voir leur bulletin généré.",
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Fermer")),
          ],
        ),
      );
      return;
    }

    final state = context.read<AppStateProvider>();
    final etab = state.etablissement;
    if (etab == null || etab.nom.isEmpty) {
      if (!mounted) return;
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
      await PDFService.generateAndPreviewBulk(
        context: context,
        etablissement: etab,
        className: widget.className,
        courses: courses,
        eleves: eligible,
        // Même effectif que sur le bulletin individuel : tous les élèves de la classe
        effectif: eleves.length,
        trimestre: _selectedTrimestre,
        stateProvider: state,
        anneeScolaire: state.selectedAnneeScolaire?.libelle,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de génération groupée: $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildTrimestreBtn(int trim, String label) {
    final isSelected = _selectedTrimestre == trim;
    return InkWell(
      onTap: () {
        setState(() => _selectedTrimestre = trim);
        context.read<AppStateProvider>().loadClassDetails(widget.classId, trimestre: _selectedTrimestre);
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final courses = state.getCourses(widget.classId);
    final eleves = state.getEleves(widget.classId);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text("Détails : ${widget.className}"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left Panel: Subjects ──────────────────
                Container(
                  width: 300,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(
                      right: BorderSide(color: AppTheme.border.withValues(alpha: 0.7), width: 1),
                    ),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.secondary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.menu_book_rounded, size: 18, color: AppTheme.secondary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Matières",
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textDark),
                                ),
                                Text(
                                  "${courses.length} configurées",
                                  style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ListView.builder(
                          itemCount: courses.length,
                          itemBuilder: (context, index) {
                            final course = courses[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: AppTheme.surfaceAlt,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: eleves.isEmpty ? null : () => _ouvrirSaisieParMatiere(coursId: course.id),
                                  child: Tooltip(
                                    message: "Saisir les notes de « ${course.nom} » pour toute la classe",
                                    waitDuration: const Duration(milliseconds: 600),
                                    child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      "${index + 1}",
                                      style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      course.nom,
                                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark, fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (!context.read<AppStateProvider>().isClassePrimaire(widget.classId))
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "×${course.coefficient}",
                                      style: const TextStyle(
                                        color: AppTheme.secondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.primary),
                                ],
                              ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Right Panel: Students ─────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Effectif de la Classe",
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 22),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${eleves.length} élèves inscrits",
                                  style: const TextStyle(color: AppTheme.textLight),
                                ),
                              ],
                            ),
                            if (state.isCurrentYearActive)
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _importElevesFromExcel,
                                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                                    label: const Text("Importer Excel"),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton.icon(
                                    onPressed: _showAddEleveDialog,
                                    icon: const Icon(Icons.person_add_rounded, size: 18),
                                    label: const Text("Ajouter un élève"),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Filter Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border, width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    "Notes pour :",
                                    style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark, fontSize: 13),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildTrimestreBtn(1, "T1"),
                                  const SizedBox(width: 6),
                                  _buildTrimestreBtn(2, "T2"),
                                  const SizedBox(width: 6),
                                  _buildTrimestreBtn(3, "T3"),
                                ],
                              ),
                              Row(
                                children: [
                              ElevatedButton.icon(
                                onPressed: (eleves.isEmpty || courses.isEmpty) ? null : () => _ouvrirSaisieParMatiere(),
                                icon: const Icon(Icons.grid_on_rounded, size: 16),
                                label: const Text("Saisir les notes par matière"),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: eleves.isEmpty ? null : () => _generateAllBulletins(eleves, courses),
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                                label: const Text("Bulletins PDF"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  side: const BorderSide(color: AppTheme.primary, width: 1.5),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                              ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Students List
                        Expanded(
                          child: eleves.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.people_outline_rounded, color: AppTheme.textLight.withValues(alpha: 0.3), size: 56),
                                      const SizedBox(height: 16),
                                      const Text(
                                        "Aucun élève dans cette classe",
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        "Ajoutez votre premier élève pour commencer.",
                                        style: TextStyle(color: AppTheme.textLight),
                                      ),
                                    ],
                                  ),
                                )
                              : Scrollbar(
                                  child: ListView.builder(
                                    itemCount: eleves.length,
                                    itemBuilder: (context, index) {
                                      final eleve = eleves[index];
                                      return _buildStudentRow(context, eleve, courses, state);
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStudentRow(BuildContext context, Eleve eleve, List<Cours> courses, AppStateProvider state) {
    final notesCount = eleve.notesCount ?? 0;
    final totalCours = courses.length;

    Color statusColor;
    String statusText;
    if (notesCount == 0) {
      statusColor = AppTheme.textLight;
      statusText = "Non noté";
    } else if (notesCount < totalCours) {
      statusColor = AppTheme.accent;
      statusText = "En cours";
    } else {
      statusColor = AppTheme.success;
      statusText = "Complet";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: eleve.photoPath != null && File(eleve.photoPath!).existsSync()
                  ? DecorationImage(image: FileImage(File(eleve.photoPath!)), fit: BoxFit.cover)
                  : null,
              gradient: eleve.photoPath == null || !File(eleve.photoPath!).existsSync()
                  ? const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryLight])
                  : null,
            ),
            alignment: Alignment.center,
            child: eleve.photoPath == null || !File(eleve.photoPath!).existsSync()
                ? Text(
                    "${eleve.nom.isNotEmpty ? eleve.nom[0] : ''}${eleve.prenom.isNotEmpty ? eleve.prenom[0] : ''}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          // Name + status
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "${eleve.prenom} ${eleve.nom}",
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textDark, fontSize: 14),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusText.toUpperCase(),
                        style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  "${eleve.matricule ?? 'Sans matricule'} · $notesCount/$totalCours matières",
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
                ),
              ],
            ),
          ),
          // Date of birth
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(Icons.cake_outlined, size: 14, color: AppTheme.textLight.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Text(
                  eleve.dateNaissance ?? "Non renseignée",
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.isCurrentYearActive) ...[
                _buildActionButton(
                  icon: Icons.edit_outlined,
                  label: "Modifier",
                  onTap: () => _showEditEleveDialog(eleve),
                ),
                const SizedBox(width: 6),
              ],
              _buildActionButton(
                icon: state.isCurrentYearActive ? Icons.edit_note_rounded : Icons.visibility_rounded,
                label: state.isCurrentYearActive ? "Notes" : "Voir",
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => NotesEntryScreen(
                        eleve: eleve,
                        classId: widget.classId,
                        className: widget.className,
                      ),
                    ),
                  );
                  if (context.mounted) {
                    context.read<AppStateProvider>().loadClassDetails(widget.classId, trimestre: _selectedTrimestre);
                  }
                },
              ),
              const SizedBox(width: 6),
              _buildActionButton(
                icon: Icons.description_rounded,
                label: "Bulletin",
                isPrimary: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => BulletinScreen(eleve: eleve, classId: widget.classId),
                    ),
                  );
                },
              ),
              if (state.isCurrentYearActive) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: "Supprimer l'élève",
                  child: Material(
                    color: AppTheme.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => _confirmDeleteEleve(eleve),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isPrimary ? Colors.white : AppTheme.textMedium,
        backgroundColor: isPrimary ? AppTheme.secondary : Colors.transparent,
        side: BorderSide(
          color: isPrimary ? AppTheme.secondary : AppTheme.border,
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
