import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../models/classe.dart';
import '../models/eleve.dart';
import '../providers/app_state_provider.dart';
import '../services/excel_import_service.dart';
import '../services/text_utils.dart';
import '../theme/app_theme.dart';

/// Comment choisir la classe de chaque élève importé.
enum _ModeClasse { colonne, feuille, unique }

/// Ce que l'on fait des élèves d'un libellé de classe trouvé dans le fichier.
class _ChoixClasse {
  final String libelle; // tel qu'écrit dans le fichier
  String valeur; // 'id:12', 'creer' ou 'ignorer'

  _ChoixClasse(this.libelle, this.valeur);
}

/// Une ligne du fichier + sa classe de destination calculée.
class _LignePlan {
  final ImportedEleveRow row;
  final String cible; // 'id:12' ou 'new:7a'
  final String destination; // nom affiché de la classe de destination

  _LignePlan(this.row, this.cible, this.destination);
}

/// Assistant d'import des élèves depuis Excel (.xlsx) ou CSV.
/// - sans [classeCibleId] : import de toute l'école (colonne « Classe » ou une feuille par classe) ;
/// - avec [classeCibleId] : import direct dans une classe.
class ImportElevesScreen extends StatefulWidget {
  final int? classeCibleId;

  const ImportElevesScreen({super.key, this.classeCibleId});

  @override
  State<ImportElevesScreen> createState() => _ImportElevesScreenState();
}

class _ImportElevesScreenState extends State<ImportElevesScreen> {
  int _etape = 0;
  bool _chargement = false;

  String? _nomFichier;
  ImportWorkbook? _workbook;
  String? _erreur;

  int _feuilleIndex = 0;
  bool _toutesFeuilles = false;
  int? _ligneEntete;
  ImportMapping _mapping = ImportMapping();
  OrdreNomComplet _ordre = OrdreNomComplet.auto;

  _ModeClasse _modeClasse = _ModeClasse.unique;
  int? _classeUniqueId;

  final Map<String, _ChoixClasse> _choixClasses = {};
  List<Eleve> _existants = [];
  bool _seulementIgnores = false;

  @override
  void initState() {
    super.initState();
    _classeUniqueId = widget.classeCibleId;
  }

  ImportSheet? get _feuille {
    final wb = _workbook;
    if (wb == null || wb.feuilles.isEmpty) return null;
    return wb.feuilles[math.max(0, math.min(_feuilleIndex, wb.feuilles.length - 1))];
  }

  List<Classe> get _classes => context.read<AppStateProvider>().classes;

  // ════════════════════════════════════════════════════════════════
  // ÉTAPE 1 : FICHIER
  // ════════════════════════════════════════════════════════════════

  Future<void> _choisirFichier() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choisir la liste des élèves (Excel ou CSV)',
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv', 'txt', 'xls'],
      );
      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      setState(() => _chargement = true);
      final bytes = await File(path).readAsBytes();
      final wb = ExcelImportService.lireFichier(bytes, nomFichier: p.basename(path));
      if (!mounted) return;
      final existants = await context.read<AppStateProvider>().getElevesAnnee();
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _nomFichier = p.basename(path);
        _workbook = wb;
        _erreur = wb.erreur;
        _existants = existants;
        _choixClasses.clear();
        if (wb.erreur == null) {
          _configurerAutomatiquement();
          _etape = 1;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = "Erreur lors de la lecture du fichier : $e";
      });
    }
  }

  /// Réglages automatiques à l'ouverture du fichier.
  void _configurerAutomatiquement() {
    final wb = _workbook!;
    _feuilleIndex = 0;
    _toutesFeuilles = false;

    // Première feuille qui contient un en-tête reconnu
    for (var i = 0; i < wb.feuilles.length; i++) {
      if (ExcelImportService.detecterLigneEntete(wb.feuilles[i]) != null) {
        _feuilleIndex = i;
        break;
      }
    }
    _appliquerDetectionFeuille();

    if (widget.classeCibleId != null) {
      _modeClasse = _ModeClasse.unique;
      _classeUniqueId = widget.classeCibleId;
      return;
    }

    final feuillesReconnues =
        wb.feuilles.where((f) => ExcelImportService.detecterLigneEntete(f) != null).length;
    if (_mapping[ImportField.classe] != null) {
      _modeClasse = _ModeClasse.colonne;
    } else if (feuillesReconnues > 1) {
      // Plusieurs feuilles avec des listes d'élèves : une feuille = une classe
      _toutesFeuilles = true;
      _modeClasse = _ModeClasse.feuille;
    } else {
      _modeClasse = _ModeClasse.unique;
      _classeUniqueId ??= _classes.isNotEmpty ? _classes.first.id : null;
    }
  }

  void _appliquerDetectionFeuille() {
    final f = _feuille;
    if (f == null) return;
    _ligneEntete = ExcelImportService.detecterLigneEntete(f);
    _mapping = _ligneEntete != null ? ExcelImportService.detecterColonnes(f.lignes[_ligneEntete!]) : ImportMapping();
  }

  Future<void> _telechargerModele() async {
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la fiche modèle',
        fileName: 'modele_import_eleves.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (outputFile == null) return;
      if (!outputFile.toLowerCase().endsWith('.xlsx')) outputFile += '.xlsx';
      final bytes = ExcelImportService.buildTemplate();
      if (bytes == null) return;
      await File(outputFile).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fiche modèle enregistrée : ${p.basename(outputFile)}'), backgroundColor: AppTheme.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de l'enregistrement du modèle : $e"), backgroundColor: AppTheme.error),
      );
    }
  }

  // ════════════════════════════════════════════════════════════════
  // CALCUL DU PLAN D'IMPORT
  // ════════════════════════════════════════════════════════════════

  List<ImportedEleveRow> _lignesBrutes() {
    final wb = _workbook;
    if (wb == null) return [];
    if (_toutesFeuilles) {
      final rows = <ImportedEleveRow>[];
      for (final f in wb.feuilles) {
        final entete = ExcelImportService.detecterLigneEntete(f);
        if (entete == null) continue;
        rows.addAll(ExcelImportService.extraireLignes(
          f,
          ligneEntete: entete,
          mapping: ExcelImportService.detecterColonnes(f.lignes[entete]),
          ordre: _ordre,
          classeFeuille: _modeClasse == _ModeClasse.feuille ? f.nom.trim() : null,
        ));
      }
      return rows;
    }
    final f = _feuille;
    if (f == null || !_mapping.aDesNoms) return [];
    return ExcelImportService.extraireLignes(f, ligneEntete: _ligneEntete, mapping: _mapping, ordre: _ordre);
  }

  String _nomClasse(int id) {
    for (final c in _classes) {
      if (c.id == id) return c.nom;
    }
    return '?';
  }

  /// Libellés de classe trouvés dans le fichier : clé normalisée → (libellé, nombre d'élèves).
  Map<String, (String, int)> _libellesClasses(List<ImportedEleveRow> rows) {
    final result = <String, (String, int)>{};
    for (final r in rows) {
      final lib = r.classe?.trim();
      if (lib == null || lib.isEmpty) continue;
      final cle = cleClasse(lib);
      final actuel = result[cle];
      result[cle] = (actuel?.$1 ?? lib, (actuel?.$2 ?? 0) + 1);
    }
    return result;
  }

  void _initialiserChoixClasses(List<ImportedEleveRow> rows) {
    final parCle = {for (final c in _classes) cleClasse(c.nom): c.id!};
    _libellesClasses(rows).forEach((cle, info) {
      _choixClasses.putIfAbsent(cle, () {
        final existante = parCle[cle];
        return _ChoixClasse(info.$1, existante != null ? 'id:$existante' : 'creer');
      });
    });
  }

  List<_LignePlan> _plan() {
    final brutes = _lignesBrutes();
    final lignes = <_LignePlan>[];

    for (final row in brutes) {
      if (_modeClasse == _ModeClasse.unique) {
        final id = _classeUniqueId;
        lignes.add(_LignePlan(row, id == null ? 'aucune' : 'id:$id', id == null ? '—' : _nomClasse(id)));
        continue;
      }
      final lib = row.classe?.trim();
      if (lib == null || lib.isEmpty) {
        lignes.add(_LignePlan(row.valide ? row.withProbleme('Classe non indiquée') : row, 'aucune', '—'));
        continue;
      }
      final cle = cleClasse(lib);
      final choix = _choixClasses[cle];
      final valeur = choix?.valeur ?? 'creer';
      if (valeur == 'ignorer') {
        final r = row.valide ? row.withProbleme('Classe non importée') : row;
        lignes.add(_LignePlan(r, 'ignorer', lib));
      } else if (valeur.startsWith('id:')) {
        final id = int.parse(valeur.substring(3));
        lignes.add(_LignePlan(row, valeur, _nomClasse(id)));
      } else {
        lignes.add(_LignePlan(row, 'new:$cle', '${choix?.libelle ?? lib} (nouvelle)'));
      }
    }

    // Doublons et élèves déjà inscrits
    final nomsExistants = <String, Set<String>>{};
    for (final e in _existants) {
      nomsExistants.putIfAbsent('id:${e.classeId}', () => {}).add(cleEleve(e.nom, e.prenom));
    }
    final matricules = _existants
        .where((e) => e.matricule != null && e.matricule!.trim().isNotEmpty)
        .map((e) => e.matricule!.trim().toLowerCase())
        .toSet();
    final cibles = {for (final l in lignes) l.row: l.cible};
    final marquees = ExcelImportService.marquerDoublons(
      lignes.map((l) => l.row).toList(),
      cible: (r) => cibles[r] ?? 'aucune',
      nomsExistants: nomsExistants,
      matriculesExistants: matricules,
      messageMatricule: widget.classeCibleId != null ? 'Matricule déjà utilisé' : "Matricule déjà utilisé dans l'établissement",
    );
    return [
      for (var i = 0; i < lignes.length; i++)
        _LignePlan(
          lignes[i].cible == 'aucune' && marquees[i].valide ? marquees[i].withProbleme('Aucune classe choisie') : marquees[i],
          lignes[i].cible,
          lignes[i].destination,
        ),
    ];
  }

  bool get _configurationValide {
    if (_toutesFeuilles) return _lignesBrutes().isNotEmpty;
    if (!_mapping.aDesNoms) return false;
    if (_modeClasse == _ModeClasse.unique) return _classeUniqueId != null;
    if (_modeClasse == _ModeClasse.colonne) return _mapping[ImportField.classe] != null;
    return true;
  }

  Future<void> _importer(List<_LignePlan> plan) async {
    final valides = plan.where((l) => l.row.valide).toList();
    if (valides.isEmpty) return;
    final aImporter = valides.map((l) {
      final r = l.row;
      int? classeId;
      String? nouvelle;
      if (l.cible.startsWith('id:')) {
        classeId = int.parse(l.cible.substring(3));
      } else if (l.cible.startsWith('new:')) {
        nouvelle = _choixClasses[l.cible.substring(4)]?.libelle ?? r.classe;
      }
      return EleveAImporter(
        nom: r.nom,
        prenom: r.prenom,
        matricule: r.matricule,
        dateNaissance: r.dateNaissance,
        telephoneParent: r.telephoneParent,
        classeId: classeId,
        nouvelleClasse: nouvelle,
      );
    }).toList();

    setState(() => _chargement = true);
    try {
      final res = await context.read<AppStateProvider>().importerEleves(aImporter);
      if (!mounted) return;
      setState(() => _chargement = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppTheme.success),
              SizedBox(width: 10),
              Text("Import terminé"),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${res.importes} élève(s) importé(s) avec succès."),
                if (res.classesCreees.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text("${res.classesCreees.length} classe(s) créée(s) : ${res.classesCreees.join(', ')}."),
                  const SizedBox(height: 8),
                  const Text(
                    "Pensez à ouvrir ces classes pour ajouter leurs matières, coefficients et frais.",
                    style: TextStyle(color: AppTheme.textLight, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Terminer")),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _chargement = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de l'import : $e"), backgroundColor: AppTheme.error),
      );
    }
  }

  // ════════════════════════════════════════════════════════════════
  // INTERFACE
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final classeCible = widget.classeCibleId != null ? state.getClasse(widget.classeCibleId!) : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(classeCible != null
            ? "Importer des élèves dans ${classeCible.nom}"
            : "Importer la liste des élèves (Excel)"),
      ),
      body: Column(
        children: [
          _buildEtapes(),
          Expanded(
            child: _chargement
                ? const Center(child: CircularProgressIndicator())
                : (_etape == 0
                    ? _buildEtapeFichier()
                    : (_etape == 1 ? _buildEtapeColonnes() : _buildEtapeVerification())),
          ),
        ],
      ),
    );
  }

  Widget _buildEtapes() {
    const titres = ["Fichier", "Colonnes & classes", "Vérification"];
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < titres.length; i++) ...[
            if (i > 0)
              Container(
                width: 48,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: i <= _etape ? AppTheme.primary : AppTheme.border,
              ),
            CircleAvatar(
              radius: 13,
              backgroundColor: i <= _etape ? AppTheme.primary : AppTheme.border,
              child: Text("${i + 1}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(
              titres[i],
              style: TextStyle(
                fontWeight: i == _etape ? FontWeight.w700 : FontWeight.w500,
                color: i == _etape ? AppTheme.textDark : AppTheme.textLight,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _carte({required Widget child, double maxWidth = 900}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Card(child: Padding(padding: const EdgeInsets.all(28), child: child)),
      ),
    );
  }

  // ── Étape 1 ───────────────────────────────────────────────────────

  Widget _buildEtapeFichier() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: _carte(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Importer une liste d'élèves existante", style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            const Text(
              "Utilisez directement le fichier Excel de l'établissement : pas besoin de le modifier. "
              "Le logiciel reconnaît automatiquement les colonnes (Nom, Prénom, Matricule, Date de naissance, "
              "Classe, Téléphone du parent) et vous laisse corriger si besoin avant d'importer.",
              style: TextStyle(color: AppTheme.textLight, height: 1.5),
            ),
            const SizedBox(height: 20),
            _aide(Icons.view_column_rounded, "Une seule feuille avec une colonne « Classe »",
                "Tous les élèves de l'école sont répartis automatiquement dans leurs classes."),
            _aide(Icons.tab_rounded, "Une feuille par classe (onglets « 7ème A », « 8ème B »...)",
                "Le nom de chaque onglet est utilisé comme nom de classe."),
            _aide(Icons.person_rounded, "« Nom et prénom » dans une seule colonne",
                "Le nom de famille est reconnu s'il est écrit en MAJUSCULES."),
            _aide(Icons.add_box_rounded, "Classes manquantes",
                "Les classes qui n'existent pas encore dans le logiciel peuvent être créées automatiquement."),
            const SizedBox(height: 24),
            if (_erreur != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_erreur!, style: const TextStyle(color: AppTheme.textDark))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _choisirFichier,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text("Choisir le fichier Excel ou CSV"),
                ),
                OutlinedButton.icon(
                  onPressed: _telechargerModele,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text("Télécharger une fiche modèle"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              "Formats acceptés : .xlsx (Excel 2007 et plus récent) et .csv. "
              "Un ancien fichier .xls doit d'abord être enregistré en .xlsx depuis Excel.",
              style: TextStyle(color: AppTheme.textLight, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aide(IconData icon, String titre, String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                Text(texte, style: const TextStyle(color: AppTheme.textLight, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Étape 2 ───────────────────────────────────────────────────────

  String _apercuLigne(ImportSheet f, int r) {
    final cells = f.lignes[r].map((c) => c.texte?.trim() ?? '').where((t) => t.isNotEmpty).take(4).join(' | ');
    return cells.isEmpty ? '(vide)' : cells;
  }

  String _libelleColonne(ImportSheet f, int c) {
    final lettre = ExcelImportService.lettreColonne(c);
    if (_ligneEntete == null) return "Colonne $lettre";
    final t = f.cellule(_ligneEntete!, c).texte?.trim();
    return (t == null || t.isEmpty) ? "Colonne $lettre" : "Colonne $lettre : $t";
  }

  Widget _buildEtapeColonnes() {
    final wb = _workbook!;
    final f = _feuille!;
    final classes = _classes;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _carte(
              maxWidth: 1000,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description_rounded, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_nomFichier ?? '', style: Theme.of(context).textTheme.titleMedium),
                      ),
                      TextButton.icon(
                        onPressed: _choisirFichier,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text("Changer de fichier"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Feuille
                  if (wb.feuilles.length > 1) ...[
                    DropdownButtonFormField<int>(
                      key: ValueKey('feuille-$_toutesFeuilles-$_feuilleIndex'),
                      initialValue: _toutesFeuilles ? -1 : _feuilleIndex,
                      decoration: const InputDecoration(labelText: "Feuille du classeur"),
                      items: [
                        for (var i = 0; i < wb.feuilles.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text("${wb.feuilles[i].nom}  (${wb.feuilles[i].lignes.length} lignes)"),
                          ),
                        if (widget.classeCibleId == null)
                          DropdownMenuItem(
                            value: -1,
                            child: Text("Toutes les feuilles : une feuille = une classe (${wb.feuilles.length} feuilles)"),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _choixClasses.clear();
                          if (v == -1) {
                            _toutesFeuilles = true;
                            _modeClasse = _ModeClasse.feuille;
                          } else {
                            _toutesFeuilles = false;
                            _feuilleIndex = v;
                            _appliquerDetectionFeuille();
                            if (widget.classeCibleId == null) {
                              _modeClasse = _mapping[ImportField.classe] != null ? _ModeClasse.colonne : _ModeClasse.unique;
                              _classeUniqueId ??= classes.isNotEmpty ? classes.first.id : null;
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (_toutesFeuilles)
                    _buildResumeFeuilles(wb)
                  else ...[
                    // Ligne d'en-tête
                    Text("Colonnes du fichier", style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      _ligneEntete != null && _mapping.aDesNoms
                          ? "Les colonnes ont été reconnues automatiquement. Vérifiez-les et corrigez si besoin."
                          : "Les colonnes n'ont pas pu être reconnues : indiquez la ligne des titres et les colonnes à utiliser.",
                      style: TextStyle(
                        color: _ligneEntete != null && _mapping.aDesNoms ? AppTheme.textLight : AppTheme.warning,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      key: ValueKey('entete-$_feuilleIndex-$_ligneEntete'),
                      initialValue: _ligneEntete ?? -1,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: "Ligne des titres de colonnes"),
                      items: [
                        const DropdownMenuItem(value: -1, child: Text("Aucune : la première ligne contient déjà un élève")),
                        for (var r = 0; r < f.lignes.length && r < ExcelImportService.lignesEnteteMax; r++)
                          DropdownMenuItem(
                            value: r,
                            child: Text("Ligne ${r + 1} : ${_apercuLigne(f, r)}", overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _ligneEntete = (v == null || v < 0) ? null : v;
                        _mapping = _ligneEntete != null
                            ? ExcelImportService.detecterColonnes(f.lignes[_ligneEntete!])
                            : ImportMapping();
                        _choixClasses.clear();
                      }),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 14,
                      children: [
                        for (final champ in ImportField.values)
                          if (champ != ImportField.classe || widget.classeCibleId == null)
                            SizedBox(width: 440, child: _buildChoixColonne(f, champ)),
                      ],
                    ),
                    if (_mapping[ImportField.nomPrenom] != null &&
                        (_mapping[ImportField.nom] == null || _mapping[ImportField.prenom] == null)) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<OrdreNomComplet>(
                        initialValue: _ordre,
                        decoration: const InputDecoration(labelText: "Dans la colonne « nom complet »"),
                        items: const [
                          DropdownMenuItem(
                            value: OrdreNomComplet.auto,
                            child: Text("Automatique : le mot en MAJUSCULES est le nom, sinon le 1er mot"),
                          ),
                          DropdownMenuItem(value: OrdreNomComplet.nomPuisPrenom, child: Text("Le NOM est écrit en premier")),
                          DropdownMenuItem(value: OrdreNomComplet.prenomPuisNom, child: Text("Le prénom est écrit en premier")),
                        ],
                        onChanged: (v) => setState(() => _ordre = v ?? OrdreNomComplet.auto),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _buildApercuBrut(f),
                  ],

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildChoixDestination(classes),
                ],
              ),
            ),
          ),
        ),
        _buildBarreNavigation(
          precedent: () => setState(() => _etape = 0),
          suivant: _configurationValide
              ? () {
                  setState(() {
                    _initialiserChoixClasses(_lignesBrutes());
                    _seulementIgnores = false;
                    _etape = 2;
                  });
                }
              : null,
          libelleSuivant: "Vérifier les élèves",
        ),
      ],
    );
  }

  Widget _buildChoixColonne(ImportSheet f, ImportField champ) {
    final nbCols = f.nbColonnes;
    final valeur = _mapping[champ];
    return DropdownButtonFormField<int>(
      key: ValueKey('col-${champ.name}-$_feuilleIndex-$_ligneEntete-$valeur'),
      initialValue: (valeur != null && valeur < nbCols) ? valeur : -1,
      isExpanded: true,
      decoration: InputDecoration(labelText: champ.libelle),
      items: [
        const DropdownMenuItem(value: -1, child: Text("— Aucune —")),
        for (var c = 0; c < nbCols; c++)
          DropdownMenuItem(value: c, child: Text(_libelleColonne(f, c), overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() {
        final m = _mapping.copie();
        if (v == null || v < 0) {
          m.colonnes.remove(champ);
        } else {
          m.colonnes[champ] = v;
        }
        _mapping = m;
        _choixClasses.clear();
        if (widget.classeCibleId == null && champ == ImportField.classe) {
          _modeClasse = m[ImportField.classe] != null ? _ModeClasse.colonne : _ModeClasse.unique;
          _classeUniqueId ??= _classes.isNotEmpty ? _classes.first.id : null;
        }
      }),
    );
  }

  Widget _buildResumeFeuilles(ImportWorkbook wb) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Feuilles du classeur", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          "Chaque feuille reconnue sera importée ; son nom servira de nom de classe.",
          style: TextStyle(color: AppTheme.textLight, fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (final f in wb.feuilles)
          Builder(builder: (context) {
            final entete = ExcelImportService.detecterLigneEntete(f);
            final nb = entete == null
                ? 0
                : ExcelImportService.extraireLignes(f,
                        ligneEntete: entete, mapping: ExcelImportService.detecterColonnes(f.lignes[entete]))
                    .length;
            return ListTile(
              dense: true,
              leading: Icon(
                entete != null ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                color: entete != null ? AppTheme.success : AppTheme.textLight,
              ),
              title: Text(f.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(entete != null
                  ? "$nb élève(s) trouvé(s) — titres en ligne ${entete + 1}"
                  : "Colonnes Nom / Prénom non reconnues : feuille ignorée"),
            );
          }),
      ],
    );
  }

  Widget _buildApercuBrut(ImportSheet f) {
    final debut = _ligneEntete == null ? 0 : _ligneEntete! + 1;
    final fin = math.min(debut + 5, f.lignes.length);
    final colonnes = math.min(f.nbColonnes, 8);
    if (debut >= f.lignes.length || colonnes == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Aperçu du fichier", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 36,
              columnSpacing: 20,
              columns: [
                for (var c = 0; c < colonnes; c++)
                  DataColumn(
                    label: Text(
                      _libelleColonne(f, c),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
              rows: [
                for (var r = debut; r < fin; r++)
                  DataRow(cells: [
                    for (var c = 0; c < colonnes; c++)
                      DataCell(Text(f.cellule(r, c).texte ?? '', style: const TextStyle(fontSize: 12))),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChoixDestination(List<Classe> classes) {
    if (widget.classeCibleId != null) {
      return Row(
        children: [
          const Icon(Icons.class_rounded, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text("Classe de destination : ${_nomClasse(widget.classeCibleId!)}",
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
    }
    final aColonneClasse = !_toutesFeuilles && _mapping[ImportField.classe] != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Dans quelle classe mettre les élèves ?", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        RadioGroup<_ModeClasse>(
          groupValue: _modeClasse,
          onChanged: (v) => setState(() {
            if (v == null) return;
            _modeClasse = v;
            _choixClasses.clear();
            if (v == _ModeClasse.unique) _classeUniqueId ??= classes.isNotEmpty ? classes.first.id : null;
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (aColonneClasse)
                const RadioListTile<_ModeClasse>(
                  value: _ModeClasse.colonne,
                  title: Text("Selon la colonne « Classe » du fichier"),
                  subtitle: Text("Chaque élève va dans la classe indiquée sur sa ligne."),
                ),
              if (_toutesFeuilles)
                const RadioListTile<_ModeClasse>(
                  value: _ModeClasse.feuille,
                  title: Text("Selon le nom de chaque feuille"),
                  subtitle: Text("Ex. : les élèves de la feuille « 7ème A » vont dans la classe 7ème A."),
                ),
              RadioListTile<_ModeClasse>(
                value: _ModeClasse.unique,
                title: const Text("Tous les élèves dans une seule classe"),
                subtitle: classes.isEmpty
                    ? const Text("Aucune classe n'existe encore : créez-en une ou utilisez une colonne « Classe ».")
                    : null,
              ),
            ],
          ),
        ),
        if (_modeClasse == _ModeClasse.unique && classes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: SizedBox(
              width: 360,
              child: DropdownButtonFormField<int>(
                key: ValueKey('classe-unique-$_classeUniqueId'),
                initialValue: classes.any((c) => c.id == _classeUniqueId) ? _classeUniqueId : null,
                decoration: const InputDecoration(labelText: "Classe de destination"),
                items: classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nom))).toList(),
                onChanged: (v) => setState(() => _classeUniqueId = v),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBarreNavigation({
    required VoidCallback? precedent,
    required VoidCallback? suivant,
    required String libelleSuivant,
    IconData iconeSuivant = Icons.arrow_forward_rounded,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          if (precedent != null)
            OutlinedButton.icon(
              onPressed: precedent,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text("Retour"),
            ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: suivant,
            icon: Icon(iconeSuivant, size: 18),
            label: Text(libelleSuivant),
          ),
        ],
      ),
    );
  }

  // ── Étape 3 ───────────────────────────────────────────────────────

  Widget _buildEtapeVerification() {
    final plan = _plan();
    final valides = plan.where((l) => l.row.valide).length;
    final ignores = plan.length - valides;
    final aCreer = _choixClasses.values.where((c) => c.valeur == 'creer').length;
    final libelles = _modeClasse == _ModeClasse.unique ? <String, (String, int)>{} : _libellesClasses(_lignesBrutes());
    final affichees = _seulementIgnores ? plan.where((l) => !l.row.valide).toList() : plan;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _chip(Icons.check_circle_rounded, "$valides élève(s) à importer", AppTheme.success),
                    if (ignores > 0) _chip(Icons.warning_amber_rounded, "$ignores ligne(s) ignorée(s)", AppTheme.error),
                    if (aCreer > 0) _chip(Icons.add_box_rounded, "$aCreer classe(s) à créer", AppTheme.primary),
                  ],
                ),
                const SizedBox(height: 16),
                if (libelles.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Classes trouvées dans le fichier",
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 190),
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final entry in libelles.entries) _buildLigneChoixClasse(entry.key, entry.value),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Text("Détail des lignes", style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (ignores > 0)
                      FilterChip(
                        label: const Text("Afficher seulement les lignes ignorées"),
                        selected: _seulementIgnores,
                        onSelected: (v) => setState(() => _seulementIgnores = v),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildTableauPlan(affichees)),
              ],
            ),
          ),
        ),
        _buildBarreNavigation(
          precedent: () => setState(() => _etape = 1),
          suivant: valides > 0 ? () => _importer(plan) : null,
          libelleSuivant: "Importer $valides élève(s)",
          iconeSuivant: Icons.download_done_rounded,
        ),
      ],
    );
  }

  Widget _buildLigneChoixClasse(String cle, (String, int) info) {
    final choix = _choixClasses[cle] ?? _ChoixClasse(info.$1, 'creer');
    _choixClasses[cle] = choix;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text("« ${info.$1} »  —  ${info.$2} élève(s)",
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark)),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: AppTheme.textLight),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              key: ValueKey('choix-$cle-${choix.valeur}'),
              initialValue: choix.valeur,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [
                DropdownMenuItem(value: 'creer', child: Text("Créer la classe « ${info.$1} »")),
                for (final c in _classes) DropdownMenuItem(value: 'id:${c.id}', child: Text("Classe existante : ${c.nom}")),
                const DropdownMenuItem(value: 'ignorer', child: Text("Ne pas importer ces élèves")),
              ],
              onChanged: (v) => setState(() => choix.valeur = v ?? 'creer'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTableauPlan(List<_LignePlan> lignes) {
    const entete = TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textMedium);
    Widget cell(String t, int flex, {TextStyle? style}) => Expanded(
          flex: flex,
          child: Text(t, style: style ?? const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
        );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: AppTheme.surfaceAlt,
            child: Row(
              children: [
                cell("Ligne", 2, style: entete),
                cell("Nom", 3, style: entete),
                cell("Prénom", 3, style: entete),
                cell("Matricule", 2, style: entete),
                cell("Naissance", 2, style: entete),
                cell("Téléphone", 2, style: entete),
                cell("Classe", 3, style: entete),
                cell("Statut", 3, style: entete),
              ],
            ),
          ),
          Expanded(
            child: lignes.isEmpty
                ? const Center(child: Text("Aucune ligne à afficher.", style: TextStyle(color: AppTheme.textLight)))
                : ListView.separated(
                    itemCount: lignes.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final l = lignes[i];
                      final r = l.row;
                      final style = TextStyle(fontSize: 13, color: r.valide ? AppTheme.textDark : AppTheme.textLight);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          children: [
                            cell(_toutesFeuilles ? "${r.feuille} · ${r.ligne}" : "${r.ligne}", 2, style: style),
                            cell(r.nom.isEmpty ? "—" : r.nom, 3, style: style),
                            cell(r.prenom.isEmpty ? "—" : r.prenom, 3, style: style),
                            cell(r.matricule ?? "—", 2, style: style),
                            cell(r.dateNaissance ?? "—", 2, style: style),
                            cell(r.telephoneParent ?? "—", 2, style: style),
                            cell(l.destination, 3, style: style),
                            Expanded(
                              flex: 3,
                              child: r.valide
                                  ? const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Icon(Icons.check_rounded, color: AppTheme.success, size: 18),
                                    )
                                  : Text(r.probleme!, style: const TextStyle(fontSize: 12, color: AppTheme.error)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
