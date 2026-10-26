import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/etablissement.dart';
import '../models/annee_scolaire.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import 'promotion_wizard_screen.dart';
import '../services/backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _adresseController = TextEditingController();
  final _telController = TextEditingController();
  final _anneeController = TextEditingController();
  final _newAnneeController = TextEditingController();
  String? _logoPath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final etab = context.read<AppStateProvider>().etablissement;
      if (etab != null) {
        _nomController.text = etab.nom;
        _adresseController.text = etab.adresse ?? '';
        _telController.text = etab.telephone ?? '';
        _anneeController.text = etab.anneeScolaire;
        setState(() {
          _logoPath = etab.logoPath;
        });
      } else {
        final now = DateTime.now();
        _anneeController.text = "${now.year}-${now.year + 1}";
      }
    });
  }

  @override
  void dispose() {
    _nomController.dispose();
    _adresseController.dispose();
    _telController.dispose();
    _anneeController.dispose();
    _newAnneeController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);
        final originalFile = File(result.files.single.path!);
        final appDir = await getApplicationSupportDirectory();
        
        await appDir.create(recursive: true);
        
        final extension = p.extension(originalFile.path);
        final fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}$extension';
        final destinationPath = p.join(appDir.path, fileName);

        await originalFile.copy(destinationPath);

        setState(() {
          _logoPath = destinationPath;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la sélection du logo: $e')),
      );
    }
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final newEtab = Etablissement(
        nom: _nomController.text.trim(),
        adresse: _adresseController.text.trim(),
        telephone: _telController.text.trim(),
        logoPath: _logoPath,
        anneeScolaire: _anneeController.text.trim(),
      );

      try {
        await context.read<AppStateProvider>().saveEtablissement(newEtab);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paramètres enregistrés avec succès !'),
            backgroundColor: AppTheme.success,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur d\'enregistrement : $e'), backgroundColor: AppTheme.error),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addAnneeScolaire(AppStateProvider state) async {
    final text = _newAnneeController.text.trim();
    if (text.isEmpty) return;

    final regExp = RegExp(r'^\d{4}-\d{4}$');
    if (!regExp.hasMatch(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Format invalide. Exemple attendu: 2025-2026"),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    // Check if already exists
    if (state.anneesScolaires.any((y) => y.libelle == text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cette année scolaire existe déjà."),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await state.addAnneeScolaire(text);
      _newAnneeController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nouvelle année scolaire ajoutée.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur d\'ajout : $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ==========================================
  // SAUVEGARDE / RESTAURATION
  // ==========================================
  Future<void> _creerSauvegarde() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final date = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la sauvegarde',
        fileName: 'sauvegarde_scolarpro_$date.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (outputFile == null) return;
      if (!outputFile.toLowerCase().endsWith('.zip')) outputFile += '.zip';
      final bytes = await BackupService.creerSauvegarde();
      await File(outputFile).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sauvegarde enregistrée : ${p.basename(outputFile)}'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la sauvegarde : $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restaurerSauvegarde(AppStateProvider state) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Restaurer une sauvegarde ?"),
        content: const Text(
          "Toutes les données actuelles (classes, élèves, notes, paiements, paramètres) seront remplacées "
          "par celles de la sauvegarde choisie.\n\n"
          "Par précaution, une copie de la base actuelle est conservée dans le dossier de l'application.",
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            child: const Text("Choisir la sauvegarde"),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choisir le fichier de sauvegarde (.zip)',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.path == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      await BackupService.restaurer(bytes);
      await state.reloadAll();
      if (!mounted) return;
      final etab = state.etablissement;
      _nomController.text = etab?.nom ?? '';
      _adresseController.text = etab?.adresse ?? '';
      _telController.text = etab?.telephone ?? '';
      _anneeController.text = etab?.anneeScolaire ?? '';
      setState(() => _logoPath = etab?.logoPath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sauvegarde restaurée avec succès.'), backgroundColor: AppTheme.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restauration impossible : $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _confirmDeleteAnnee(AppStateProvider state, AnneeScolaire year) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer l'année scolaire ?"),
        content: Text(
          "Êtes-vous sûr de vouloir supprimer l'année '${year.libelle}' ? "
          "Cette action supprimera également TOUTES les classes, élèves et notes de cette année de manière définitive et irréversible.",
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              setState(() => _isLoading = true);
              try {
                await state.deleteAnneeScolaire(year.id!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Année scolaire supprimée avec succès.'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur lors de la suppression : $e'),
                      backgroundColor: AppTheme.error,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text("Supprimer définitivement"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          "Paramètres de l'Établissement",
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Card 1: General Info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Informations Générales",
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Ces informations figureront en haut de chaque bulletin scolaire généré.",
                            style: TextStyle(color: AppTheme.textLight),
                          ),
                          const SizedBox(height: 32),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Logo Officiel",
                                    style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: 140,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppTheme.primary.withValues(alpha: 0.3),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.02),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                      image: _logoPath != null
                                          ? DecorationImage(
                                              image: FileImage(File(_logoPath!)),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: _logoPath == null
                                        ? const Icon(
                                            Icons.add_a_photo_outlined,
                                            color: AppTheme.primary,
                                            size: 32,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    onPressed: _pickLogo,
                                    icon: const Icon(Icons.upload_rounded, size: 18),
                                    label: const Text("Sélectionner"),
                                  ),
                                  if (_logoPath != null) ...[
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _logoPath = null;
                                        });
                                      },
                                      style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                                      child: const Text("Supprimer"),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(width: 48),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextFormField(
                                      controller: _nomController,
                                      decoration: const InputDecoration(
                                        labelText: "Nom de l'établissement *",
                                        hintText: "ex: Lycée Scientifique d'Excellence",
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return "Veuillez entrer le nom de l'établissement";
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _telController,
                                            decoration: const InputDecoration(
                                              labelText: "Téléphone",
                                              hintText: "ex: +221 33 800 00 00",
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _anneeController,
                                            decoration: const InputDecoration(
                                              labelText: "Année scolaire active *",
                                              hintText: "ex: 2025-2026",
                                              helperText: "Définit le libellé de l'année active.",
                                            ),
                                            validator: (value) {
                                              if (value == null || value.trim().isEmpty) {
                                                return "Veuillez entrer l'année scolaire";
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    TextFormField(
                                      controller: _adresseController,
                                      maxLines: 2,
                                      decoration: const InputDecoration(
                                        labelText: "Adresse physique",
                                        hintText: "ex: Dakar, Sénégal",
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                          const Divider(color: AppTheme.border),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _saveSettings,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: const Text("Enregistrer les paramètres"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Card 2: Academic Years management
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Gestion des Années Scolaires",
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Ajoutez de nouvelles années académiques. L'année active est celle utilisée par défaut ; "
                          "les années précédentes restent consultables (et modifiables si besoin) en archives, "
                          "depuis le sélecteur d'année de la barre latérale.",
                          style: TextStyle(color: AppTheme.textLight),
                        ),
                        const SizedBox(height: 32),
                        // Add year input row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newAnneeController,
                                decoration: const InputDecoration(
                                  labelText: "Nouvelle année scolaire (Format: AAAA-AAAA)",
                                  hintText: "ex: 2026-2027",
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: _isLoading ? null : () => _addAnneeScolaire(state),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text("Ajouter l'année"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        const Divider(color: AppTheme.border),
                        const SizedBox(height: 24),
                        Text(
                          "Liste des Années Académiques",
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: state.anneesScolaires.length,
                          separatorBuilder: (context, index) => const Divider(color: AppTheme.border, height: 1),
                          itemBuilder: (context, index) {
                            final year = state.anneesScolaires[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    year.active ? Icons.check_circle_rounded : Icons.archive_outlined,
                                    color: year.active ? AppTheme.success : AppTheme.textLight,
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    year.libelle,
                                    style: TextStyle(
                                      fontWeight: year.active ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 16,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: year.active 
                                          ? AppTheme.success.withValues(alpha: 0.1)
                                          : AppTheme.textLight.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: year.active 
                                            ? AppTheme.success.withValues(alpha: 0.3)
                                            : AppTheme.textLight.withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      year.active ? "ACTIVE" : "ARCHIVE",
                                      style: TextStyle(
                                        color: year.active ? AppTheme.success : AppTheme.textLight,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (!year.active) ...[
                                    TextButton.icon(
                                      onPressed: _isLoading 
                                          ? null 
                                          : () => state.setActiveAnneeScolaire(year.id!),
                                      icon: const Icon(Icons.star_rounded, size: 16),
                                      label: const Text("Rendre active"),
                                      style: TextButton.styleFrom(foregroundColor: AppTheme.primaryLight),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: _isLoading 
                                          ? null 
                                          : () => _confirmDeleteAnnee(state, year),
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                                      tooltip: "Supprimer définitivement",
                                    ),
                                  ] else
                                    const Text(
                                      "Année active courante",
                                      style: TextStyle(
                                        color: AppTheme.textLight,
                                        fontStyle: FontStyle.italic,
                                        fontSize: 13,
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
                const SizedBox(height: 32),
                // Card 3: Backup / restore
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Sauvegarde & Restauration",
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Enregistrez toutes les données (classes, élèves, notes, paiements, logo et photos) dans un seul fichier .zip. "
                          "Conservez-le sur une clé USB ou un autre ordinateur : en cas de panne, de virus ou de changement de PC, "
                          "vous pourrez tout récupérer.",
                          style: TextStyle(color: AppTheme.textLight, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isLoading ? null : _creerSauvegarde,
                              icon: const Icon(Icons.backup_rounded),
                              label: const Text("Créer une sauvegarde"),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : () => _restaurerSauvegarde(state),
                              icon: const Icon(Icons.restore_rounded),
                              label: const Text("Restaurer une sauvegarde"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Conseil : faites une sauvegarde au moins une fois par semaine, et toujours avant la clôture de l'année.",
                          style: TextStyle(color: AppTheme.textLight, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ),
                if (state.isSelectedYearActive) ...[
                  const SizedBox(height: 32),
                  Card(
                    color: AppTheme.primary.withValues(alpha: 0.02),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.15), width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 28),
                              const SizedBox(width: 16),
                              Text(
                                "Clôture de l'Année & Promotion",
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Cette fonction vous guide à travers le processus de fin d'année scolaire. "
                            "Elle vous permettra de créer la nouvelle année, de dupliquer automatiquement les classes et matières, "
                            "de calculer les moyennes annuelles de tous les élèves et d'affecter chaque élève (passage, redoublement ou exclusion) "
                            "avec la possibilité d'appliquer des dérogations manuelles.",
                            style: TextStyle(color: AppTheme.textDark, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const PromotionWizardScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text("Lancer l'assistant de promotion"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
