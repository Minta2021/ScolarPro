import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../providers/app_state_provider.dart';
import '../models/classe.dart';
import '../theme/app_theme.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  Classe? _selectedClass;
  int _selectedTrimestre = 1;
  String? _selectedAnneeScolaire;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppStateProvider>();
      if (state.classes.isNotEmpty) {
        setState(() {
          _selectedClass = state.classes.first;
        });
      }
      final annee = state.selectedAnneeScolaire?.libelle ?? state.etablissement?.anneeScolaire;
      if (annee != null) {
        setState(() {
          _selectedAnneeScolaire = annee;
        });
      }
    });
  }

  Future<void> _exportToExcel() async {
    final classesAnnee = context.read<AppStateProvider>().classes;
    if (_selectedClass == null || !classesAnnee.any((c) => c.id == _selectedClass!.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Veuillez sélectionner une classe."),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    final state = context.read<AppStateProvider>();
    
    try {
      // Force load the class details (with notes count for current selected trimester)
      await state.loadClassDetails(_selectedClass!.id!, trimestre: _selectedTrimestre);
      final eleves = state.getEleves(_selectedClass!.id!);

      if (eleves.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Aucun élève dans cette classe à exporter."),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _isExporting = false);
        return;
      }

      // Collect data with averages, rank and mention
      final bareme = state.getBareme(_selectedClass!.id!);
      final ranks = await state.calculateRanks(_selectedClass!.id!, _selectedTrimestre);
      final List<Map<String, dynamic>> exportData = [];
      for (var eleve in eleves) {
        final avg = await state.calculateMoyenneGenerale(eleve.id!, _selectedClass!.id!, _selectedTrimestre);
        exportData.add({
          'nom_prenom': "${eleve.nom} ${eleve.prenom}",
          'matricule': eleve.matricule ?? 'N/A',
          'date_naissance': eleve.dateNaissance ?? 'N/A',
          // Arrondi à 2 décimales, enregistré comme un vrai nombre (calculs possibles dans Excel)
          'moyenne': avg != null ? double.parse(avg.toStringAsFixed(2)) : null,
          'rang': ranks[eleve.id!] ?? 'Non classé',
          'mention': avg != null ? AppStateProvider.getMention(avg, bareme: bareme) : '-',
          'annee_scolaire': state.selectedAnneeScolaire?.libelle ?? _selectedAnneeScolaire ?? 'N/A',
        });
      }

      // Open save-file picker
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter les informations des élèves',
        fileName: 'export_${_selectedClass!.nom.replaceAll(' ', '_')}_trimestre_$_selectedTrimestre.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile == null) {
        // User cancelled
        setState(() => _isExporting = false);
        return;
      }

      // Ensure extension is xlsx on Windows
      if (!outputFile.toLowerCase().endsWith('.xlsx')) {
        outputFile += '.xlsx';
      }

      // Write Excel file
      final excel = ex.Excel.createExcel();
      
      // Rename default sheet
      excel.rename('Sheet1', 'Export Eleves');
      final sheet = excel['Export Eleves'];

      // Style headers
      sheet.appendRow([
        ex.TextCellValue("Nom & Prénom"),
        ex.TextCellValue("Matricule"),
        ex.TextCellValue("Date de Naissance"),
        ex.TextCellValue("Moyenne Trimestre $_selectedTrimestre (/$bareme)"),
        ex.TextCellValue("Rang"),
        ex.TextCellValue("Mention"),
        ex.TextCellValue("Année Scolaire"),
      ]);

      // Add student data
      for (var row in exportData) {
        sheet.appendRow([
          ex.TextCellValue(row['nom_prenom'] as String),
          ex.TextCellValue(row['matricule'] as String),
          ex.TextCellValue(row['date_naissance'] as String),
          row['moyenne'] != null ? ex.DoubleCellValue(row['moyenne'] as double) : ex.TextCellValue('N/A'),
          ex.TextCellValue(row['rang'] as String),
          ex.TextCellValue(row['mention'] as String),
          ex.TextCellValue(row['annee_scolaire'] as String),
        ]);
      }

      // Save bytes to file
      final bytes = excel.save();
      if (bytes != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Données exportées avec succès : ${p.basename(outputFile)}"),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur lors de l'exportation : $e"),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final classes = state.classes;
    final isConfigured = state.etablissement != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          "Exportation de Données",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Exportation Excel (.xlsx)",
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Exportez la liste des élèves avec leurs moyennes trimestrielles en fonction des filtres sélectionnés.",
                      style: TextStyle(color: AppTheme.textLight),
                    ),
                    const SizedBox(height: 32),
                    if (classes.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 40, color: AppTheme.textLight.withValues(alpha: 0.5)),
                              const SizedBox(height: 12),
                              const Text(
                                "Veuillez d'abord créer des classes et ajouter des élèves.",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Filter: Classe
                          DropdownButtonFormField<Classe>(
                            initialValue: _selectedClass != null && classes.any((c) => c.id == _selectedClass!.id)
                                ? classes.firstWhere((c) => c.id == _selectedClass!.id)
                                : null,
                            decoration: const InputDecoration(
                              labelText: "Sélectionner la classe",
                            ),
                            items: classes.map((c) {
                              return DropdownMenuItem<Classe>(
                                value: c,
                                child: Text(c.nom),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedClass = val;
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          // Filter: Trimestre
                          DropdownButtonFormField<int>(
                            initialValue: _selectedTrimestre,
                            decoration: const InputDecoration(
                              labelText: "Trimestre",
                            ),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text("1er Trimestre")),
                              DropdownMenuItem(value: 2, child: Text("2e Trimestre")),
                              DropdownMenuItem(value: 3, child: Text("3e Trimestre")),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedTrimestre = val;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          // Filter: Année Scolaire
                          TextFormField(
                            key: ValueKey('annee-${state.selectedAnneeScolaire?.id}'),
                            initialValue: state.selectedAnneeScolaire?.libelle ??
                                _selectedAnneeScolaire ??
                                (isConfigured ? state.etablissement!.anneeScolaire : "Non configurée"),
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: "Année scolaire (choisie dans la barre latérale)",
                            ),
                          ),
                          const SizedBox(height: 40),
                          const Divider(color: AppTheme.border),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isExporting ? null : _exportToExcel,
                              icon: _isExporting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.table_view_rounded),
                              label: const Text("Générer le fichier Excel"),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
