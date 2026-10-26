import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/classe.dart';
import '../models/cours.dart';
import '../models/eleve.dart';
import '../models/note.dart';
import '../providers/app_state_provider.dart';
import '../database/db_helper.dart';
import '../theme/app_theme.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  Classe? _selectedClass;
  int _selectedTrimestre = 1;
  int get _bareme => _selectedClass?.bareme ?? 20;
  bool get _primaire => _selectedClass?.isPrimaire ?? false;
  bool _isLoadingStats = false;

  // Stats variables
  bool _hasData = false;
  int _totalStudents = 0;
  int _gradedStudents = 0;
  double _classMoyenne = 0.0;
  double _successRate = 0.0;
  MapEntry<Eleve, double>? _bestStudent;
  MapEntry<Eleve, double>? _worstStudent;
  List<MapEntry<Cours, double>> _courseAveragesList = [];

  // Per-student per-subject performance data
  List<_StudentSubjectProfile> _studentProfiles = [];
  List<Cours> _loadedCourses = [];
  _StudentSubjectProfile? _selectedStudentProfile;

  // Distribution counters
  int _distInsuffisant = 0;
  int _distPassable = 0;
  int _distAssezBien = 0;
  int _distBien = 0;
  int _distTresBien = 0;
  int _distExcellent = 0;

  void _selectClass(Classe classe) {
    setState(() {
      _selectedClass = classe;
      _isLoadingStats = true;
      _selectedStudentProfile = null;
    });
    _loadClassStats();
  }

  void _deselectClass() {
    setState(() {
      _selectedClass = null;
      _hasData = false;
      _selectedStudentProfile = null;
    });
  }

  Future<void> _loadClassStats() async {
    if (_selectedClass == null) return;
    setState(() => _isLoadingStats = true);

    try {
      final state = context.read<AppStateProvider>();
      final db = await DBHelper.database;
      final classId = _selectedClass!.id!;

      // 1. Get courses
      final List<Map<String, dynamic>> courseMaps = await db.query(
        'cours',
        where: 'classe_id = ?',
        whereArgs: [classId],
      );
      final courses = courseMaps.map((m) => Cours.fromMap(m)).toList();

      // 2. Get students
      final List<Map<String, dynamic>> eleveMaps = await db.query(
        'eleves',
        where: 'classe_id = ?',
        whereArgs: [classId],
      );
      final eleves = eleveMaps.map((m) => Eleve.fromMap(m)).toList();

      if (eleves.isEmpty) {
        setState(() {
          _hasData = false;
          _isLoadingStats = false;
        });
        return;
      }

      // 3. Compute student averages
      final List<MapEntry<Eleve, double>> studentAverages = [];
      int successCount = 0;
      
      int dInsuffisant = 0;
      int dPassable = 0;
      int dAssezBien = 0;
      int dBien = 0;
      int dTresBien = 0;
      int dExcellent = 0;

      for (var eleve in eleves) {
        final avg = await state.calculateMoyenneGenerale(eleve.id!, classId, _selectedTrimestre);
        if (avg != null) {
          studentAverages.add(MapEntry(eleve, avg));
          final avg20 = avg * 20 / _bareme; // seuils exprimés sur 20
          if (avg20 >= 10.0) successCount++;
          
          if (avg20 < 10.0) {
            dInsuffisant++;
          } else if (avg20 < 12.0) {
            dPassable++;
          } else if (avg20 < 14.0) {
            dAssezBien++;
          } else if (avg20 < 16.0) {
            dBien++;
          } else if (avg20 < 18.0) {
            dTresBien++;
          } else {
            dExcellent++;
          }
        }
      }

      if (studentAverages.isEmpty) {
        setState(() {
          _hasData = false;
          _isLoadingStats = false;
        });
        return;
      }

      // Sort student averages descending
      studentAverages.sort((a, b) => b.value.compareTo(a.value));
      
      final bestStudent = studentAverages.first;
      final worstStudent = studentAverages.last;
      
      double classAvgSum = 0;
      for (var entry in studentAverages) {
        classAvgSum += entry.value;
      }
      final classMoyenne = classAvgSum / studentAverages.length;
      final successRate = (successCount / studentAverages.length) * 100;

      // 4. Compute course-by-course averages
      final List<Map<String, dynamic>> noteMaps = await db.rawQuery('''
        SELECT n.* FROM notes n
        INNER JOIN eleves e ON n.eleve_id = e.id
        WHERE e.classe_id = ? AND n.trimestre = ?
      ''', [classId, _selectedTrimestre]);
      
      final List<Note> notes = noteMaps.map((m) => Note.fromMap(m)).toList();
      final List<MapEntry<Cours, double>> courseAveragesList = [];

      for (var course in courses) {
        final courseNotes = notes.where((n) => n.coursId == course.id).toList();
        double totalCourseWeighted = 0;
        int noteCount = 0;

        for (var note in courseNotes) {
          final avg = note.moyenneCoursPour(_primaire);
          if (avg != null) {
            totalCourseWeighted += avg;
            noteCount++;
          }
        }

        if (noteCount > 0) {
          courseAveragesList.add(MapEntry(course, totalCourseWeighted / noteCount));
        }
      }

      // Sort courses by average descending
      courseAveragesList.sort((a, b) => b.value.compareTo(a.value));

      // 5. Build per-student per-subject profiles
      final List<_StudentSubjectProfile> profiles = [];
      for (var entry in studentAverages) {
        final eleve = entry.key;
        final moyGen = entry.value;
        final eleveNotes = notes.where((n) => n.eleveId == eleve.id).toList();
        
        final Map<int, double> subjectAvgs = {}; // coursId -> moyenneCours
        final List<Cours> strengths = [];
        final List<Cours> weaknesses = [];

        for (var course in courses) {
          final noteMatch = eleveNotes.where((n) => n.coursId == course.id).toList();
          if (noteMatch.isNotEmpty) {
            final moy = noteMatch.first.moyenneCoursPour(_primaire);
            if (moy != null) {
              subjectAvgs[course.id!] = moy;
              final moy20 = moy * 20 / _bareme;
              if (moy20 >= 12.0) {
                strengths.add(course);
              } else if (moy20 < 10.0) {
                weaknesses.add(course);
              }
            }
          }
        }

        profiles.add(_StudentSubjectProfile(
          eleve: eleve,
          moyenneGenerale: moyGen,
          subjectAverages: subjectAvgs,
          strengths: strengths,
          weaknesses: weaknesses,
        ));
      }

      setState(() {
        _classMoyenne = classMoyenne;
        _successRate = successRate;
        _bestStudent = bestStudent;
        _worstStudent = worstStudent;
        _totalStudents = eleves.length;
        _gradedStudents = studentAverages.length;
        _courseAveragesList = courseAveragesList;
        _studentProfiles = profiles;
        _loadedCourses = courses;
        
        _distInsuffisant = dInsuffisant;
        _distPassable = dPassable;
        _distAssezBien = dAssezBien;
        _distBien = dBien;
        _distTresBien = dTresBien;
        _distExcellent = dExcellent;

        _hasData = true;
        _isLoadingStats = false;
      });
    } catch (e) {
      setState(() => _isLoadingStats = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de calcul des statistiques : $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  String _formatDouble(double val) {
    if (val == val.toInt()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final classes = state.classes;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            if (_selectedClass != null) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _deselectClass,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              _selectedClass == null
                  ? "Statistiques et Analyses"
                  : "Statistiques : ${_selectedClass!.nom}",
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
          ],
        ),
      ),
      body: _selectedClass == null
          ? _buildClassGrid(classes)
          : _buildDetailStatsView(),
    );
  }

  // ==========================================
  // VIEW 1: CLASS SELECTION GRID
  // ==========================================
  Widget _buildClassGrid(List<Classe> classes) {
    if (classes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: AppTheme.textLight.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            const Text(
              "Aucune classe disponible",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            const Text(
              "Veuillez créer des classes et y affecter des élèves pour voir les statistiques.",
              style: TextStyle(color: AppTheme.textLight),
            ),
          ],
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    int crossAxisCount = 3;
    if (width < 900) {
      crossAxisCount = 1;
    } else if (width < 1300) {
      crossAxisCount = 2;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Sélectionnez une classe pour analyser ses performances",
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              mainAxisExtent: 180,
            ),
            itemCount: classes.length,
            itemBuilder: (context, index) {
              final classe = classes[index];
              return InkWell(
                onTap: () => _selectClass(classe),
                borderRadius: BorderRadius.circular(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                classe.nom,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textDark),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                classe.niveau,
                                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, size: 18, color: AppTheme.textLight),
                            const SizedBox(width: 8),
                            Text(
                              "${classe.elevesCount ?? 0} Élèves",
                              style: const TextStyle(color: AppTheme.textLight, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Voir l'analyse détaillée",
                              style: TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Icon(Icons.arrow_forward_rounded, color: AppTheme.primaryLight, size: 18),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 2: DETAILS ANALYSIS PANEL
  // ==========================================
  Widget _buildDetailStatsView() {
    return Column(
      children: [
        // Filter Bar (Trimestre selection)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    "Trimestre de l'analyse : ",
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark),
                  ),
                  const SizedBox(width: 16),
                  _buildTrimestreBtn(1, "1er Trimestre"),
                  const SizedBox(width: 8),
                  _buildTrimestreBtn(2, "2e Trimestre"),
                  const SizedBox(width: 8),
                  _buildTrimestreBtn(3, "3e Trimestre"),
                ],
              ),
              OutlinedButton.icon(
                onPressed: _deselectClass,
                icon: const Icon(Icons.grid_view_rounded, size: 16),
                label: const Text("Retour aux classes"),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingStats
              ? const Center(child: CircularProgressIndicator())
              : (!_hasData ? _buildNoDataPlaceholder() : _buildStatsContent()),
        ),
      ],
    );
  }

  Widget _buildNoDataPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, size: 60, color: AppTheme.textLight.withValues(alpha: 0.4)),
            const SizedBox(height: 20),
            const Text(
              "Données insuffisantes",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            Text(
              "Aucun élève de la classe '${_selectedClass!.nom}' n'a de notes complètes enregistrées pour le trimestre $_selectedTrimestre.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsContent() {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 1000;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: KPI Cards (4 cards)
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 750) {
                    return Column(
                      children: [
                        _buildKpiCard("Effectif évalué", "$_gradedStudents / $_totalStudents", "élèves classés", Icons.group_rounded, AppTheme.primary),
                        const SizedBox(height: 16),
                        _buildKpiCard("Moyenne Classe", "${_formatDouble(_classMoyenne)} / $_bareme", "moyenne générale", Icons.school_rounded, AppTheme.secondary),
                        const SizedBox(height: 16),
                        _buildKpiCard("Taux de réussite", "${_formatDouble(_successRate)}%", "moyenne >= ${_bareme ~/ 2}/$_bareme", Icons.star_rounded, AppTheme.accent),
                        const SizedBox(height: 16),
                        _buildKpiCard("Matières évaluées", "${_courseAveragesList.length}", "matières avec notes", Icons.book_rounded, Colors.purple),
                      ],
                    );
                  } else if (constraints.maxWidth < 1100) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildKpiCard("Effectif évalué", "$_gradedStudents / $_totalStudents", "élèves classés", Icons.group_rounded, AppTheme.primary)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildKpiCard("Moyenne Classe", "${_formatDouble(_classMoyenne)} / $_bareme", "moyenne générale", Icons.school_rounded, AppTheme.secondary)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildKpiCard("Taux de réussite", "${_formatDouble(_successRate)}%", "moyenne >= ${_bareme ~/ 2}/$_bareme", Icons.star_rounded, AppTheme.accent)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildKpiCard("Matières évaluées", "${_courseAveragesList.length}", "matières avec notes", Icons.book_rounded, Colors.purple)),
                          ],
                        ),
                      ],
                    );
                  } else {
                    return Row(
                      children: [
                        Expanded(child: _buildKpiCard("Effectif évalué", "$_gradedStudents / $_totalStudents", "élèves classés", Icons.group_rounded, AppTheme.primary)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildKpiCard("Moyenne Classe", "${_formatDouble(_classMoyenne)} / $_bareme", "moyenne générale", Icons.school_rounded, AppTheme.secondary)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildKpiCard("Taux de réussite", "${_formatDouble(_successRate)}%", "moyenne >= ${_bareme ~/ 2}/$_bareme", Icons.star_rounded, AppTheme.accent)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildKpiCard("Matières évaluées", "${_courseAveragesList.length}", "matières avec notes", Icons.book_rounded, Colors.purple)),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 32),
              // Row 2: Records Card (Best and Worst students)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppTheme.border, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Extrêmes de la Classe",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 650;
                          final content = [
                            // Best student
                            Expanded(
                              flex: isCompact ? 0 : 1,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.15), width: 1),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.success.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.emoji_events_rounded, color: AppTheme.success, size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Meilleure Moyenne Générale",
                                            style: TextStyle(color: AppTheme.textLight, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            "${_bestStudent!.key.prenom} ${_bestStudent!.key.nom}",
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                          ),
                                          if (_bestStudent!.key.matricule != null)
                                            Text(
                                              "Matricule: ${_bestStudent!.key.matricule}",
                                              style: const TextStyle(color: AppTheme.textLight, fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      "${_formatDouble(_bestStudent!.value)}/$_bareme",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.success),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!isCompact) const SizedBox(width: 24),
                            if (isCompact) const SizedBox(height: 16),
                            // Worst student
                            Expanded(
                              flex: isCompact ? 0 : 1,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.error.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.15), width: 1),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.error.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.trending_down_rounded, color: AppTheme.error, size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Moyenne Générale la Plus Basse",
                                            style: TextStyle(color: AppTheme.textLight, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            "${_worstStudent!.key.prenom} ${_worstStudent!.key.nom}",
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                          ),
                                          if (_worstStudent!.key.matricule != null)
                                            Text(
                                              "Matricule: ${_worstStudent!.key.matricule}",
                                              style: const TextStyle(color: AppTheme.textLight, fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      "${_formatDouble(_worstStudent!.value)}/$_bareme",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.error),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ];
                          return isCompact ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content) : Row(children: content);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Row 3: Split columns (Strengths & Weaknesses vs Grade Distribution)
              isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildMatierePerformanceCard()),
                        const SizedBox(width: 32),
                        Expanded(flex: 2, child: _buildDistributionCard()),
                      ],
                    )
                  : Column(
                      children: [
                        _buildMatierePerformanceCard(),
                        const SizedBox(height: 32),
                        _buildDistributionCard(),
                      ],
                    ),
              const SizedBox(height: 32),
              // Row 4: Per-Student Performance Grid
              _buildStudentPerformanceGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, String sub, IconData icon, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.15), width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              color.withValues(alpha: 0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color,
                    color.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: AppTheme.textLight, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(color: AppTheme.textLight, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatierePerformanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Performances par Matière",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            const Text(
              "Matières classées par moyenne générale décroissante (Toutes notes confondues)",
              style: TextStyle(color: AppTheme.textLight, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(4),
                1: FixedColumnWidth(100),
                2: FixedColumnWidth(120),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppTheme.border, width: 1.5)),
                  ),
                  children: [
                    _buildTableHeaderCell("Matière"),
                    _buildTableHeaderCell("Moyenne"),
                    _buildTableHeaderCell("Diagnostic"),
                  ],
                ),
                ..._courseAveragesList.map((entry) {
                  final course = entry.key;
                  final avg = entry.value;
                  
                  Color diagColor;
                  String diagText;
                  IconData diagIcon;
                  if (avg >= _bareme * 0.6) {
                    diagColor = AppTheme.success;
                    diagText = "Point Fort";
                    diagIcon = Icons.check_circle_rounded;
                  } else if (avg < _bareme / 2) {
                    diagColor = AppTheme.error;
                    diagText = "Point Faible";
                    diagIcon = Icons.warning_amber_rounded;
                  } else {
                    diagColor = AppTheme.textLight;
                    diagText = "Neutre";
                    diagIcon = Icons.info_outline_rounded;
                  }

                  return TableRow(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          course.nom,
                          style: const TextStyle(fontWeight: FontWeight.w500, color: AppTheme.textDark),
                        ),
                      ),
                      Center(
                        child: Text(
                          "${_formatDouble(avg)} / $_bareme",
                          style: TextStyle(fontWeight: FontWeight.bold, color: diagColor),
                        ),
                      ),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: diagColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: diagColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(diagIcon, color: diagColor, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                diagText,
                                style: TextStyle(color: diagColor, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
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
    );
  }

  Widget _buildDistributionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Répartition des Performances",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            const Text(
              "Répartition des moyennes générales par mentions",
              style: TextStyle(color: AppTheme.textLight, fontSize: 12),
            ),
            const SizedBox(height: 32),
            _buildDistributionRow("Excellent (>=18)", _distExcellent, AppTheme.secondary),
            const SizedBox(height: 16),
            _buildDistributionRow("Très Bien (16-18)", _distTresBien, Colors.green),
            const SizedBox(height: 16),
            _buildDistributionRow("Bien (14-16)", _distBien, Colors.teal),
            const SizedBox(height: 16),
            _buildDistributionRow("Assez Bien (12-14)", _distAssezBien, AppTheme.primaryLight),
            const SizedBox(height: 16),
            _buildDistributionRow("Passable (10-12)", _distPassable, AppTheme.accent),
            const SizedBox(height: 16),
            _buildDistributionRow("Insuffisant (<10)", _distInsuffisant, AppTheme.error),
          ],
        ),
      ),
    );
  }

  Widget _buildDistributionRow(String label, int count, Color color) {
    double percent = _gradedStudents > 0 ? (count / _gradedStudents) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: AppTheme.textDark)),
            Text(
              "$count ${count > 1 ? 'élèves' : 'élève'} (${(percent * 100).toStringAsFixed(1)}%)",
              style: const TextStyle(fontSize: 12, color: AppTheme.textLight, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: const Color(0xFFF1F5F9),
            color: color,
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildTrimestreBtn(int trim, String label) {
    final isSelected = _selectedTrimestre == trim;
    return InkWell(
      onTap: () {
        if (_selectedTrimestre != trim) {
          setState(() {
            _selectedTrimestre = trim;
            _selectedStudentProfile = null;
          });
          _loadClassStats();
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textLight,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppTheme.textLight,
          fontSize: 13,
        ),
        textAlign: text == "Matière" ? TextAlign.left : TextAlign.center,
      ),
    );
  }

  // ==========================================
  // SECTION: Performance par Élève
  // ==========================================
  Widget _buildStudentPerformanceGrid() {
    if (_studentProfiles.isEmpty || _loadedCourses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section Header ───────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_search_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Performance par Élève",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Sélectionnez un élève pour analyser ses notes par matière",
                      style: TextStyle(color: AppTheme.textLight, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            // ── Dropdown de sélection ─────────────────
            DropdownButtonFormField<_StudentSubjectProfile>(
              initialValue: _selectedStudentProfile,
              decoration: InputDecoration(
                labelText: "Sélectionner un élève",
                prefixIcon: const Icon(Icons.person_rounded, color: AppTheme.primary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                ),
                filled: true,
                fillColor: AppTheme.surfaceAlt,
              ),
              hint: const Text("Choisir un élève..."),
              items: _studentProfiles.map((profile) {
                return DropdownMenuItem<_StudentSubjectProfile>(
                  value: profile,
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              profile.moyenneGenerale >= _bareme / 2 ? AppTheme.primary : AppTheme.error,
                              profile.moyenneGenerale >= _bareme / 2 ? AppTheme.primaryLight : AppTheme.error.withValues(alpha: 0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          profile.eleve.prenom.isNotEmpty ? profile.eleve.prenom[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(
                          '${profile.eleve.nom} ${profile.eleve.prenom}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (profile.moyenneGenerale >= _bareme / 2 ? AppTheme.success : AppTheme.error).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_formatDouble(profile.moyenneGenerale)}/$_bareme',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: profile.moyenneGenerale >= _bareme / 2 ? AppTheme.success : AppTheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (profile) {
                setState(() => _selectedStudentProfile = profile);
              },
            ),
            // ── Tableau de notes ──────────────────────
            if (_selectedStudentProfile != null) ...[
              const SizedBox(height: 28),
              const Divider(color: AppTheme.border),
              const SizedBox(height: 20),
              _buildStudentNoteTable(_selectedStudentProfile!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentNoteTable(_StudentSubjectProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Student identity bar ──────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      profile.moyenneGenerale >= _bareme / 2 ? AppTheme.primary : AppTheme.error,
                      profile.moyenneGenerale >= _bareme / 2 ? AppTheme.primaryLight : AppTheme.error.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  profile.eleve.prenom.isNotEmpty ? profile.eleve.prenom[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${profile.eleve.prenom} ${profile.eleve.nom}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textDark),
                    ),
                    if (profile.eleve.matricule != null)
                      Text(
                        'Matricule : ${profile.eleve.matricule}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      ),
                  ],
                ),
              ),
              // Summary chips
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_up_rounded, size: 14, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Text(
                      '${profile.strengths.length} Force${profile.strengths.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.success),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_down_rounded, size: 14, color: AppTheme.error),
                    const SizedBox(width: 4),
                    Text(
                      '${profile.weaknesses.length} Faiblesse${profile.weaknesses.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.error),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: (profile.moyenneGenerale >= _bareme / 2 ? AppTheme.success : AppTheme.error).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (profile.moyenneGenerale >= _bareme / 2 ? AppTheme.success : AppTheme.error).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'Moy. Gén. : ${_formatDouble(profile.moyenneGenerale)} / $_bareme',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: profile.moyenneGenerale >= _bareme / 2 ? AppTheme.success : AppTheme.error,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // ── Notes Table (Matière | Coeff | Moyenne | Diagnostic) ──
        Table(
          columnWidths: const {
            0: FlexColumnWidth(4),  // Matière
            1: FixedColumnWidth(70), // Coeff
            2: FixedColumnWidth(100), // Moyenne
            3: FixedColumnWidth(130), // Diagnostic
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            // Header
            TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border, width: 1.5)),
              ),
              children: [
                _buildTableHeaderCell("Matière"),
                _buildTableHeaderCell("Coeff."),
                _buildTableHeaderCell("Moyenne"),
                _buildTableHeaderCell("Diagnostic"),
              ],
            ),
            // Data rows — one per course
            ..._loadedCourses.map((course) {
              final avg = profile.subjectAverages[course.id];

              Color diagColor;
              String diagText;
              IconData diagIcon;

              if (avg == null) {
                diagColor = AppTheme.textLight;
                diagText = "Non noté";
                diagIcon = Icons.remove_circle_outline_rounded;
              } else if (avg >= _bareme * 0.6) {
                diagColor = AppTheme.success;
                diagText = "Point Fort";
                diagIcon = Icons.check_circle_rounded;
              } else if (avg < _bareme / 2) {
                diagColor = AppTheme.error;
                diagText = "Point Faible";
                diagIcon = Icons.warning_amber_rounded;
              } else {
                diagColor = AppTheme.accent;
                diagText = "À consolider";
                diagIcon = Icons.info_outline_rounded;
              }

              return TableRow(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
                ),
                children: [
                  // Matière
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      course.nom,
                      style: const TextStyle(fontWeight: FontWeight.w500, color: AppTheme.textDark),
                    ),
                  ),
                  // Coefficient
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _primaire ? '—' : '${course.coefficient}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.textMedium,
                        ),
                      ),
                    ),
                  ),
                  // Moyenne
                  Center(
                    child: Text(
                      avg != null ? '${_formatDouble(avg)} / $_bareme' : '—',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: avg != null ? diagColor : AppTheme.textLight,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // Diagnostic badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: diagColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: diagColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(diagIcon, color: diagColor, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            diagText,
                            style: TextStyle(color: diagColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }
}

/// Internal model to hold a student's per-subject analysis profile
class _StudentSubjectProfile {
  final Eleve eleve;
  final double moyenneGenerale;
  final Map<int, double> subjectAverages; // coursId -> moyenneCours
  final List<Cours> strengths;  // courses where avg >= 12
  final List<Cours> weaknesses; // courses where avg < 10

  _StudentSubjectProfile({
    required this.eleve,
    required this.moyenneGenerale,
    required this.subjectAverages,
    required this.strengths,
    required this.weaknesses,
  });
}

