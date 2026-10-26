import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/eleve.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';

class StudentPromotionState {
  final Eleve eleve;
  final String className;
  final double? moyenneAnnuelle;
  final int bareme;
  final String autoDecision; // 'Admis', 'Redouble'
  String finalDecision; // 'Admis', 'Redouble', 'Exclu'
  /// La classe n'a pas de classe supérieure : un élève admis quitte l'établissement (fin de cycle).
  final bool finDeCycle;

  StudentPromotionState({
    required this.eleve,
    required this.className,
    required this.moyenneAnnuelle,
    this.bareme = 20,
    required this.autoDecision,
    required this.finalDecision,
    this.finDeCycle = false,
  });

  bool get sortant => finalDecision == "Admis" && finDeCycle;
}

class PromotionWizardScreen extends StatefulWidget {
  const PromotionWizardScreen({super.key});

  @override
  State<PromotionWizardScreen> createState() => _PromotionWizardScreenState();
}

class _PromotionWizardScreenState extends State<PromotionWizardScreen> {
  int _currentStep = 0;
  bool _isLoading = false;
  String _loadingMessage = "";

  // Step 1: Target Year
  final _yearFormKey = GlobalKey<FormState>();
  final _newYearController = TextEditingController();

  // Step 3: Promotion List
  List<StudentPromotionState> _students = [];
  List<StudentPromotionState> _filteredStudents = [];
  final TextEditingController _searchController = TextEditingController();
  int? _selectedClassFilterId;
  String _selectedDecisionFilter = "Tous";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);

    // Suggest next school year
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeYear = context.read<AppStateProvider>().activeAnneeScolaire;
      if (activeYear != null) {
        final regExp = RegExp(r'^(\d{4})-(\d{4})$');
        final match = regExp.firstMatch(activeYear.libelle);
        if (match != null) {
          final start = int.parse(match.group(1)!);
          final end = int.parse(match.group(2)!);
          _newYearController.text = "${start + 1}-${end + 1}";
        } else {
          final now = DateTime.now();
          _newYearController.text = "${now.year}-${now.year + 1}";
        }
      }
    });
  }

  @override
  void dispose() {
    _newYearController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Load students and calculate annual averages
  Future<void> _loadPromotionData() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = "Calcul des moyennes annuelles de tous les élèves...";
    });

    try {
      final provider = context.read<AppStateProvider>();
      final activeYear = provider.activeAnneeScolaire;
      if (activeYear == null) return;

      final List<StudentPromotionState> tempStudents = [];

      for (var classe in provider.classes) {
        // Load details to populate provider cache for courses/eleves
        await provider.loadClassDetails(classe.id!);
        final eleves = provider.getEleves(classe.id!);

        for (var eleve in eleves) {
          final avg = await provider.calculateMoyenneAnnuelle(eleve.id!, classe.id!);
          final String autoDec = (avg != null && avg >= classe.bareme / 2) ? "Admis" : "Redouble";
          
          tempStudents.add(StudentPromotionState(
            eleve: eleve,
            className: classe.nom,
            moyenneAnnuelle: avg,
            bareme: classe.bareme,
            autoDecision: autoDec,
            finalDecision: autoDec, // initially matches auto decision
            finDeCycle: classe.nextClassId == null,
          ));
        }
      }

      setState(() {
        _students = tempStudents;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur lors de la préparation des données : $e"),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _applyFilters() {
    final search = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredStudents = _students.where((s) {
        // Search filter
        final matchesSearch = s.eleve.nom.toLowerCase().contains(search) ||
            s.eleve.prenom.toLowerCase().contains(search) ||
            (s.eleve.matricule ?? '').toLowerCase().contains(search);

        // Class filter
        final matchesClass = _selectedClassFilterId == null || s.eleve.classeId == _selectedClassFilterId;

        // Decision filter
        final matchesDecision = _selectedDecisionFilter == "Tous" ||
            (_selectedDecisionFilter == "Admis" && s.finalDecision == "Admis") ||
            (_selectedDecisionFilter == "Redouble" && s.finalDecision == "Redouble") ||
            (_selectedDecisionFilter == "Exclu" && s.finalDecision == "Exclu");

        return matchesSearch && matchesClass && matchesDecision;
      }).toList();
    });
  }

  // Execute the promotion
  Future<void> _executePromotion() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = "Clôture de l'année et création de la nouvelle structure en cours...";
    });

    try {
      final provider = context.read<AppStateProvider>();
      final newYearLib = _newYearController.text.trim();

      // Convert decision list to Map<eleveId, decision>
      final Map<int, String> decisions = {
        for (var s in _students) s.eleve.id!: s.finalDecision
      };

      final res = await provider.executePromotion(newYearLib, decisions);

      setState(() => _isLoading = false);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 28),
                SizedBox(width: 12),
                Text("Promotion réussie !"),
              ],
            ),
            content: Text(
              "L'année scolaire a été clôturée avec succès.\n"
              "La nouvelle année académique '$newYearLib' est maintenant active.\n\n"
              "• Classes créées : ${res.classesCreees}"
              "${res.classesReutilisees > 0 ? ' (+ ${res.classesReutilisees} déjà existante(s) réutilisée(s))' : ''}\n"
              "• Élèves admis en classe supérieure : ${res.admis}\n"
              "• Redoublants : ${res.redoublants}\n"
              "• Sortants (fin de cycle, non réinscrits) : ${res.sortants}\n"
              "• Exclus : ${res.exclus}"
              "${res.dejaPresents > 0 ? '\n• Déjà inscrits dans la nouvelle année (non dupliqués) : ${res.dejaPresents}' : ''}",
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to settings screen
                },
                child: const Text("Fermer"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_rounded, color: AppTheme.error, size: 28),
                SizedBox(width: 12),
                Text("Erreur lors de la promotion"),
              ],
            ),
            content: Text("Une erreur s'est produite lors de l'exécution de la promotion :\n$e"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Compris"),
              ),
            ],
          ),
        );
      }
    }
  }

  // Navigation handlers
  void _nextStep() {
    if (_currentStep == 0) {
      if (!_yearFormKey.currentState!.validate()) return;
      
      // Check if new year matches current active year or already exists
      final provider = context.read<AppStateProvider>();
      final newYear = _newYearController.text.trim();
      if (provider.activeAnneeScolaire?.libelle == newYear) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("L'année cible doit être différente de l'année en cours."),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
      
      _currentStep++;
      setState(() {});
    } else if (_currentStep == 1) {
      _currentStep++;
      setState(() {});
      _loadPromotionData(); // load data when entering step 3
    } else if (_currentStep == 2) {
      _currentStep++;
      setState(() {});
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          "Assistant de Fin d'Année & Promotion",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(
                        _loadingMessage,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                // Horizontal Stepper Bar
                _buildStepperHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: _currentStep == 2 ? 1100 : 800,
                        ),
                        child: _buildStepContent(state),
                      ),
                    ),
                  ),
                ),
                // Footer navigation buttons
                _buildNavigationFooter(),
              ],
            ),
    );
  }

  Widget _buildStepperHeader() {
    final steps = [
      "Nouvelle Année",
      "Flux des Classes",
      "Évaluation des Élèves",
      "Validation"
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Container(
              width: 60,
              height: 2,
              color: (index ~/ 2) < _currentStep ? AppTheme.primary : AppTheme.border,
            );
          }
          final stepIdx = index ~/ 2;
          final isCompleted = stepIdx < _currentStep;
          final isActive = stepIdx == _currentStep;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppTheme.success
                      : (isActive ? AppTheme.primary : Colors.white),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCompleted
                        ? AppTheme.success
                        : (isActive ? AppTheme.primary : AppTheme.border),
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: isCompleted
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        "${stepIdx + 1}",
                        style: TextStyle(
                          color: isActive ? Colors.white : AppTheme.textLight,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Text(
                steps[stepIdx],
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? AppTheme.textDark : AppTheme.textLight,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(AppStateProvider state) {
    switch (_currentStep) {
      case 0:
        return _buildStep1(state);
      case 1:
        return _buildStep2(state);
      case 2:
        return _buildStep3(state);
      case 3:
        return _buildStep4(state);
      default:
        return Container();
    }
  }

  // STEP 1: Choose Target Year
  Widget _buildStep1(AppStateProvider state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Form(
          key: _yearFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Définir la nouvelle Année Scolaire",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Veuillez saisir le libellé de l'année scolaire suivante qui accueillera les élèves promus et redoublants.",
                style: TextStyle(color: AppTheme.textLight, fontSize: 15),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Année Active Actuelle", style: TextStyle(color: AppTheme.textLight, fontSize: 13)),
                          const SizedBox(height: 6),
                          Text(
                            state.activeAnneeScolaire?.libelle ?? "Non définie",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: AppTheme.textDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  const Icon(Icons.arrow_forward_rounded, color: AppTheme.textLight, size: 28),
                  const SizedBox(width: 24),
                  Expanded(
                    child: TextFormField(
                      controller: _newYearController,
                      decoration: const InputDecoration(
                        labelText: "Nouvelle Année Cible *",
                        hintText: "ex: 2026-2027",
                        helperText: "Format attendu: AAAA-AAAA",
                      ),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Veuillez saisir l'année scolaire cible";
                        }
                        final regExp = RegExp(r'^\d{4}-\d{4}$');
                        if (!regExp.hasMatch(value.trim())) {
                          return "Format invalide (ex: 2026-2027)";
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Divider(color: AppTheme.border),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppTheme.primary),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Lors de l'activation de la nouvelle année, l'année actuelle sera automatiquement archivée. "
                        "Vous pourrez toujours la consulter en lecture seule depuis le menu de sélection d'année en haut de la barre latérale.",
                        style: TextStyle(fontSize: 13, color: AppTheme.primary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // STEP 2: Classes configuration summary
  Widget _buildStep2(AppStateProvider state) {
    final classes = state.classes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Vérification des Flux de Passage",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              "Voici la configuration des flux de passage des classes pour la rentrée suivante. Les élèves admis iront dans la classe supérieure désignée. Les redoublants resteront dans une classe équivalente.",
              style: TextStyle(color: AppTheme.textLight, fontSize: 15),
            ),
            const SizedBox(height: 32),
            if (classes.isEmpty)
              const Center(
                child: Text(
                  "Aucune classe n'est configurée pour cette année scolaire.",
                  style: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.textLight),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: classes.length,
                separatorBuilder: (context, index) => const Divider(color: AppTheme.border),
                itemBuilder: (context, index) {
                  final c = classes[index];
                  final nextClass = c.nextClassId != null
                      ? classes.firstWhere((item) => item.id == c.nextClassId, orElse: () => c)
                      : null;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.nom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(c.niveau, style: const TextStyle(color: AppTheme.textLight, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded, color: AppTheme.primary),
                        const SizedBox(width: 32),
                        Expanded(
                          child: nextClass != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nextClass.nom,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.success),
                                    ),
                                    const Text("Promotion (Admis)", style: TextStyle(color: AppTheme.success, fontSize: 12)),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        "Diplôme / Sortie",
                                        style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                    const Text("Aucune classe supérieure", style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
                                  ],
                                ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.nom,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.error),
                              ),
                              const Text("Redoublement", style: TextStyle(color: AppTheme.error, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 32),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 16),
            const Text(
              "Note : Si vous souhaitez modifier la classe de destination pour un niveau, vous pouvez le faire depuis le formulaire d'édition de la classe concernée dans l'écran de 'Gestion des Classes'.",
              style: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.textLight, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // STEP 3: Assessment list and overrides
  Widget _buildStep3(AppStateProvider state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
                      "Évaluation et Décision par Élève",
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Moyennes annuelles calculées. Surchargez manuellement la décision finale en cas de dérogation.",
                      style: TextStyle(color: AppTheme.textLight, fontSize: 14),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
                  ),
                  child: Text(
                    "Total : ${_students.length} élèves",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Filters & Search Bar
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: "Rechercher par nom, prénom ou matricule...",
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedClassFilterId,
                    decoration: const InputDecoration(labelText: "Filtrer par classe"),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text("Toutes les classes")),
                      ...state.classes.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.nom))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedClassFilterId = val;
                        _applyFilters();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedDecisionFilter,
                    decoration: const InputDecoration(labelText: "Décision finale"),
                    items: const [
                      DropdownMenuItem(value: "Tous", child: Text("Toutes les décisions")),
                      DropdownMenuItem(value: "Admis", child: Text("Admis (Passage)")),
                      DropdownMenuItem(value: "Redouble", child: Text("Redoublants")),
                      DropdownMenuItem(value: "Exclu", child: Text("Exclus")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDecisionFilter = val;
                          _applyFilters();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Table of students
            if (_filteredStudents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    "Aucun élève ne correspond aux critères de recherche.",
                    style: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.textLight),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3), // Nom Prénom
                    1: FlexColumnWidth(2), // Classe de départ
                    2: FlexColumnWidth(2), // Moyenne Annuelle
                    3: FlexColumnWidth(2), // Décision Auto
                    4: FlexColumnWidth(3), // Décision Finale / Action
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    // Header Row
                    TableRow(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                      children: [
                        _buildTableHeaderCell("Élève"),
                        _buildTableHeaderCell("Classe"),
                        _buildTableHeaderCell("Moyenne Ann."),
                        _buildTableHeaderCell("Décision Auto"),
                        _buildTableHeaderCell("Décision Finale / Action"),
                      ],
                    ),
                    // Data Rows
                    ..._filteredStudents.map((s) {
                      final isOverridden = s.finalDecision != s.autoDecision;
                      
                      return TableRow(
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppTheme.border)),
                        ),
                        children: [
                          // Student Identity
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${s.eleve.nom} ${s.eleve.prenom}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                ),
                                if (s.eleve.matricule != null)
                                  Text(
                                    s.eleve.matricule!,
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                                  ),
                              ],
                            ),
                          ),
                          // Class
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(s.className),
                          ),
                          // Annual Average
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              s.moyenneAnnuelle != null
                                  ? "${s.moyenneAnnuelle!.toStringAsFixed(2)} / ${s.bareme}"
                                  : "N/A",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: s.moyenneAnnuelle == null
                                    ? AppTheme.textLight
                                    : (s.moyenneAnnuelle! >= s.bareme / 2 ? AppTheme.success : AppTheme.error),
                              ),
                            ),
                          ),
                          // Auto Decision Badge
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: s.autoDecision == "Admis"
                                    ? AppTheme.success.withValues(alpha: 0.08)
                                    : AppTheme.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                s.autoDecision == "Admis" ? "Admis" : "Redouble",
                                style: TextStyle(
                                  color: s.autoDecision == "Admis" ? AppTheme.success : AppTheme.error,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          // Interactive Dropdown override
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: DropdownButtonHideUnderline(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isOverridden ? AppTheme.primary : AppTheme.border,
                                    width: isOverridden ? 1.5 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  color: isOverridden ? AppTheme.primary.withValues(alpha: 0.02) : Colors.white,
                                ),
                                child: DropdownButton<String>(
                                  value: s.finalDecision,
                                  icon: Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: isOverridden ? AppTheme.primary : AppTheme.textLight,
                                  ),
                                  style: TextStyle(
                                    color: isOverridden ? AppTheme.primary : AppTheme.textDark,
                                    fontWeight: isOverridden ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: "Admis", child: Text("Admis (Passage)")),
                                    DropdownMenuItem(value: "Redouble", child: Text("Redouble")),
                                    DropdownMenuItem(value: "Exclu", child: Text("Exclu de l'école")),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        s.finalDecision = val;
                                        _applyFilters();
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (s.sortant)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 6),
                              child: Text(
                                "Fin de cycle : quitte l'établissement",
                                style: TextStyle(color: Colors.amber.shade800, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                            ],
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppTheme.textLight,
          fontSize: 12,
        ),
      ),
    );
  }

  // STEP 4: Review and run promotion
  Widget _buildStep4(AppStateProvider state) {
    // Calculate statistics
    final total = _students.length;
    final admis = _students.where((s) => s.finalDecision == "Admis" && !s.finDeCycle).length;
    final sortants = _students.where((s) => s.sortant).length;
    final redoublants = _students.where((s) => s.finalDecision == "Redouble").length;
    final exclus = _students.where((s) => s.finalDecision == "Exclu").length;

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Récapitulatif des Promotions",
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  "Vérifiez les effectifs calculés avant de valider la clôture définitive de l'année '${state.activeAnneeScolaire?.libelle}'.",
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 15),
                ),
                const SizedBox(height: 32),

                // Statistics Grid
                Row(
                  children: [
                    _buildSummaryCard("Total Élèves", "$total", Icons.people_alt_rounded, Colors.blue),
                    const SizedBox(width: 16),
                    _buildSummaryCard("Admis (Passent)", "$admis", Icons.check_circle_rounded, AppTheme.success),
                    const SizedBox(width: 16),
                    _buildSummaryCard("Redoublants", "$redoublants", Icons.replay_rounded, Colors.orange),
                    const SizedBox(width: 16),
                    _buildSummaryCard("Sortants (fin de cycle)", "$sortants", Icons.school_rounded, Colors.amber.shade800),
                    const SizedBox(width: 16),
                    _buildSummaryCard("Exclus", "$exclus", Icons.cancel_rounded, AppTheme.error),
                  ],
                ),
                
                const SizedBox(height: 40),
                const Divider(color: AppTheme.border),
                const SizedBox(height: 24),
                
                // Warning note
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 28),
                          SizedBox(width: 16),
                          Text(
                            "Action Irréversible !",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.error),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "En cliquant sur 'Clôturer et Exécuter', l'année scolaire '${state.activeAnneeScolaire?.libelle}' sera passée en archive (toujours consultable). "
                        "Les nouvelles classes pour l'année '${_newYearController.text}' seront créées et les élèves y seront affectés selon le plan validé.\n"
                        "Toutes les notes et tous les paiements de la nouvelle année seront vierges au départ "
                        "(les frais des classes et les remises des élèves sont repris).\n"
                        "Si des classes portant le même nom existent déjà dans l'année cible, elles sont réutilisées (pas de doublon).",
                        style: const TextStyle(fontSize: 14, color: AppTheme.textDark, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              color.withValues(alpha: 0.01),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.01),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color,
                    color.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 32,
                color: AppTheme.textDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textLight,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Navigation Footer
  Widget _buildNavigationFooter() {
    final isLastStep = _currentStep == 3;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous button
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: _previousStep,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text("Étape précédente"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            )
          else
            const SizedBox.shrink(),

          // Next / Finish button
          ElevatedButton.icon(
            onPressed: isLastStep ? _executePromotion : _nextStep,
            icon: Icon(isLastStep ? Icons.check_circle_rounded : Icons.arrow_forward_rounded),
            label: Text(isLastStep ? "Clôturer et Exécuter" : "Étape suivante"),
            style: ElevatedButton.styleFrom(
              backgroundColor: isLastStep ? AppTheme.success : AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
