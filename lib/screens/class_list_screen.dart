import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/classe.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import 'class_form_screen.dart';
import 'class_detail_screen.dart';
import 'import_eleves_screen.dart';

class ClassListScreen extends StatefulWidget {
  const ClassListScreen({super.key});

  @override
  State<ClassListScreen> createState() => _ClassListScreenState();
}

class _ClassListScreenState extends State<ClassListScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final classes = state.classes;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("Gestion des Classes"),
        actions: [
          if (state.isCurrentYearActive) ...[
            OutlinedButton.icon(
              onPressed: () => _navigateToImport(context),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text("Importer des élèves (Excel)"),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: ElevatedButton.icon(
                onPressed: () => _navigateToForm(context, null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text("Créer une classe"),
              ),
            ),
          ],
        ],
      ),
      body: classes.isEmpty
          ? _buildEmptyState(context, state)
          : _buildClassGrid(context, classes, state),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppStateProvider state) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.12),
                    AppTheme.secondary.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school_rounded,
                color: AppTheme.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Aucune classe créée",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              state.isCurrentYearActive
                  ? "Commencez par créer une classe et y associer des matières, "
                      "ou importez directement la liste des élèves depuis un fichier Excel : "
                      "les classes seront créées automatiquement."
                  : "Aucune classe n'a été enregistrée pour cette année scolaire.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textLight, fontSize: 14, height: 1.5),
            ),
            if (state.isCurrentYearActive) ...[
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () => _navigateToForm(context, null),
                icon: const Icon(Icons.add_rounded),
                label: const Text("Ajouter ma première classe"),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _navigateToImport(context),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text("Importer la liste des élèves (Excel)"),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClassGrid(BuildContext context, List<Classe> classes, AppStateProvider state) {
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
          Row(
            children: [
              Text(
                "Vos Classes",
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${classes.length}",
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Gérez vos classes, leurs matières et accédez aux listes d'élèves.",
            style: TextStyle(color: AppTheme.textLight, height: 1.5),
          ),
          const SizedBox(height: 28),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              mainAxisExtent: 210,
            ),
            itemCount: classes.length,
            itemBuilder: (context, index) {
              final classe = classes[index];
              return _ClassCard(
                classe: classe,
                isActive: state.isCurrentYearActive,
                index: index + 1,
                onTap: () => _navigateToDetails(context, classe),
                onEdit: () => _navigateToForm(context, classe),
                onDelete: () => _confirmDelete(context, classe),
              );
            },
          ),
        ],
      ),
    );
  }

  void _navigateToForm(BuildContext context, Classe? classe) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ClassFormScreen(classe: classe),
      ),
    );
  }

  void _navigateToImport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ImportElevesScreen()),
    );
  }

  void _navigateToDetails(BuildContext context, Classe classe) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ClassDetailScreen(classId: classe.id!, className: classe.nom),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Classe classe) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer la classe ?"),
        content: Text(
          "Êtes-vous sûr de vouloir supprimer la classe '${classe.nom}' ? "
          "Cette action supprimera également tous les élèves de cette classe ainsi que leurs notes de manière irréversible.",
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
                await context.read<AppStateProvider>().deleteClasse(classe.id!);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Classe supprimée avec succès.'),
                    backgroundColor: AppTheme.success,
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erreur de suppression : $e'),
                    backgroundColor: AppTheme.error,
                  ),
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
}

// ── Premium Class Card ──────────────────────────────────────────────
class _ClassCard extends StatefulWidget {
  final Classe classe;
  final bool isActive;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClassCard({
    required this.classe,
    required this.isActive,
    required this.index,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ClassCard> createState() => _ClassCardState();
}

class _ClassCardState extends State<_ClassCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.border,
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? AppTheme.primary.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: _isHovered ? 20 : 8,
                offset: Offset(0, _isHovered ? 8 : 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Name + Level Badge
                Row(
                  children: [
                    // Level icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.primary, AppTheme.primaryLight],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          "${widget.index}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.classe.nom,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppTheme.textDark,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.classe.niveau,
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Stats row
                Row(
                  children: [
                    _buildStat(Icons.people_alt_rounded, "${widget.classe.elevesCount ?? 0} Élèves", AppTheme.secondary),
                    const SizedBox(width: 20),
                    _buildStat(Icons.menu_book_rounded, "${widget.classe.coursCount ?? 0} Matières", AppTheme.accent),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Actions row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: _isHovered ? AppTheme.primary : AppTheme.textLight,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Détails & Élèves",
                          style: TextStyle(
                            color: _isHovered ? AppTheme.primary : AppTheme.textLight,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    if (widget.isActive)
                      Row(
                        children: [
                          _buildIconAction(
                            icon: Icons.edit_outlined,
                            tooltip: "Modifier",
                            color: AppTheme.textLight,
                            bgColor: AppTheme.surfaceAlt,
                            onTap: widget.onEdit,
                          ),
                          const SizedBox(width: 6),
                          _buildIconAction(
                            icon: Icons.delete_outline_rounded,
                            tooltip: "Supprimer",
                            color: AppTheme.error,
                            bgColor: AppTheme.error.withValues(alpha: 0.06),
                            onTap: widget.onDelete,
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppTheme.textMedium,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildIconAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}
