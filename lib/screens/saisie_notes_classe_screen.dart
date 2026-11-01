import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/cours.dart';
import '../models/eleve.dart';
import '../models/note.dart';
import '../providers/app_state_provider.dart';
import '../services/notes_utils.dart';
import '../theme/app_theme.dart';

/// Ce que l'utilisateur veut faire de modifications non enregistrées.
enum _ChoixModifs { enregistrer, abandonner, annuler }

/// Saisie des notes de toute une classe pour une matière et un trimestre.
class SaisieNotesClasseScreen extends StatefulWidget {
  final int classId;
  final String className;
  final int? coursInitialId;
  final int trimestreInitial;

  const SaisieNotesClasseScreen({
    super.key,
    required this.classId,
    required this.className,
    this.coursInitialId,
    this.trimestreInitial = 1,
  });

  @override
  State<SaisieNotesClasseScreen> createState() => _SaisieNotesClasseScreenState();
}

class _SaisieNotesClasseScreenState extends State<SaisieNotesClasseScreen> {
  late final bool _primaire;
  List<Cours> _courses = [];
  List<Eleve> _eleves = [];
  int? _coursId;
  late int _trimestre;

  bool _chargement = true;
  bool _enregistrement = false;
  bool _remplissage = false;
  int _rev = 0; // force le rafraîchissement du choix de matière après une annulation

  /// false : saisie ligne par ligne (classe puis composition de chaque élève) ;
  /// true : saisie colonne par colonne (toutes les notes de classe, puis toutes les compositions).
  bool _ordreColonne = false;

  final Map<int, TextEditingController> _classeCtrl = {};
  final Map<int, TextEditingController> _compoCtrl = {};
  final Map<int, FocusNode> _classeFocus = {};
  final Map<int, FocusNode> _compoFocus = {};
  final Map<int, (String, String)> _initial = {};

  double get _maxClasse => 20;
  double get _maxCompo => _primaire ? 10 : 40;
  int get _bareme => _primaire ? 10 : 20;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppStateProvider>();
    _primaire = state.isClassePrimaire(widget.classId);
    _trimestre = widget.trimestreInitial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    for (final c in [..._classeCtrl.values, ..._compoCtrl.values]) {
      c.dispose();
    }
    for (final f in [..._classeFocus.values, ..._compoFocus.values]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final state = context.read<AppStateProvider>();
    await state.loadClassDetails(widget.classId);
    if (!mounted) return;
    _courses = state.getCourses(widget.classId);
    _eleves = state.getEleves(widget.classId);
    for (final e in _eleves) {
      final id = e.id!;
      _classeCtrl[id] = TextEditingController()..addListener(_surChangement);
      _compoCtrl[id] = TextEditingController()..addListener(_surChangement);
      _classeFocus[id] = FocusNode();
      _compoFocus[id] = FocusNode();
    }
    _coursId = _courses.any((c) => c.id == widget.coursInitialId)
        ? widget.coursInitialId
        : (_courses.isNotEmpty ? _courses.first.id : null);
    await _chargerNotes();
  }

  void _surChangement() {
    if (!_remplissage && mounted) setState(() {});
  }

  Future<void> _chargerNotes() async {
    if (_coursId == null) {
      setState(() => _chargement = false);
      return;
    }
    setState(() => _chargement = true);
    final notes = await context.read<AppStateProvider>().getNotesCours(_coursId!, _trimestre);
    if (!mounted) return;
    _remplissage = true;
    _initial.clear();
    for (final e in _eleves) {
      final n = notes[e.id];
      final classe = n?.noteClasse != null ? formatNote(n!.noteClasse!) : '';
      final compo = n?.noteComposition != null ? formatNote(n!.noteComposition!) : '';
      _classeCtrl[e.id]!.text = classe;
      _compoCtrl[e.id]!.text = compo;
      _initial[e.id!] = (classe, compo);
    }
    _remplissage = false;
    setState(() => _chargement = false);
  }

  // ── Modifications ─────────────────────────────────────────────────

  bool _ligneModifiee(int eleveId) {
    final init = _initial[eleveId] ?? ('', '');
    return _classeCtrl[eleveId]!.text.trim() != init.$1 || _compoCtrl[eleveId]!.text.trim() != init.$2;
  }

  int get _nbModifs => _eleves.where((e) => _ligneModifiee(e.id!)).length;

  bool get _modifie => _nbModifs > 0;

  String? _erreurClasse(int id) => _primaire ? null : erreurNote(_classeCtrl[id]!.text, _maxClasse);
  String? _erreurCompo(int id) => erreurNote(_compoCtrl[id]!.text, _maxCompo);

  double? _moyenne(int id) {
    if (_erreurClasse(id) != null || _erreurCompo(id) != null) return null;
    return moyenneMatiere(
      primaire: _primaire,
      noteClasse: lireNote(_classeCtrl[id]!.text),
      noteComposition: lireNote(_compoCtrl[id]!.text),
    );
  }

  /// Enregistre les lignes modifiées. Retourne true si tout s'est bien passé.
  Future<bool> _enregistrer() async {
    if (_coursId == null || _enregistrement) return false;
    final invalides = _eleves.where((e) => _erreurClasse(e.id!) != null || _erreurCompo(e.id!) != null).length;
    if (invalides > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$invalides note(s) invalide(s), affichée(s) en rouge. Corrigez-les avant d'enregistrer."),
          backgroundColor: AppTheme.error,
        ),
      );
      return false;
    }
    final aEnregistrer = <Note>[
      for (final e in _eleves)
        if (_ligneModifiee(e.id!))
          Note(
            eleveId: e.id!,
            coursId: _coursId!,
            trimestre: _trimestre,
            noteClasse: _primaire ? null : lireNote(_classeCtrl[e.id]!.text),
            noteComposition: lireNote(_compoCtrl[e.id]!.text),
          ),
    ];
    if (aEnregistrer.isEmpty) return true;

    setState(() => _enregistrement = true);
    try {
      await context.read<AppStateProvider>().saveNotesCours(widget.classId, aEnregistrer);
      if (!mounted) return false;
      for (final e in _eleves) {
        _initial[e.id!] = (_classeCtrl[e.id]!.text.trim(), _compoCtrl[e.id]!.text.trim());
      }
      setState(() => _enregistrement = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Notes enregistrées pour ${aEnregistrer.length} élève(s)."),
          backgroundColor: AppTheme.success,
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _enregistrement = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur d'enregistrement : $e"), backgroundColor: AppTheme.error),
      );
      return false;
    }
  }

  Future<_ChoixModifs> _demanderQuoiFaire() async {
    final choix = await showDialog<_ChoixModifs>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifications non enregistrées"),
        content: Text("Vous avez modifié les notes de $_nbModifs élève(s). Voulez-vous les enregistrer ?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(_ChoixModifs.annuler), child: const Text("Annuler")),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(_ChoixModifs.abandonner),
            child: const Text("Ne pas enregistrer"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(_ChoixModifs.enregistrer),
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
    return choix ?? _ChoixModifs.annuler;
  }

  /// Avant de changer de matière ou de trimestre : propose d'enregistrer.
  Future<bool> _peutQuitterLaPage() async {
    if (!_modifie) return true;
    final choix = await _demanderQuoiFaire();
    if (choix == _ChoixModifs.annuler) return false;
    if (choix == _ChoixModifs.enregistrer) return _enregistrer();
    return true;
  }

  Future<void> _changerMatiere(int? coursId) async {
    if (coursId == null || coursId == _coursId) return;
    if (!await _peutQuitterLaPage()) {
      setState(() => _rev++); // la liste déroulante revient sur la matière en cours
      return;
    }
    setState(() => _coursId = coursId);
    await _chargerNotes();
  }

  Future<void> _changerTrimestre(int t) async {
    if (t == _trimestre) return;
    if (!await _peutQuitterLaPage()) return;
    setState(() => _trimestre = t);
    await _chargerNotes();
  }

  // ── Navigation au clavier (touche Entrée) ─────────────────────────

  void _suivant(int index, {required bool depuisClasse}) {
    final n = _eleves.length;
    FocusNode? cible;
    if (_primaire) {
      if (index + 1 < n) cible = _compoFocus[_eleves[index + 1].id];
    } else if (_ordreColonne) {
      if (depuisClasse) {
        cible = index + 1 < n ? _classeFocus[_eleves[index + 1].id] : _compoFocus[_eleves.first.id];
      } else if (index + 1 < n) {
        cible = _compoFocus[_eleves[index + 1].id];
      }
    } else {
      if (depuisClasse) {
        cible = _compoFocus[_eleves[index].id];
      } else if (index + 1 < n) {
        cible = _classeFocus[_eleves[index + 1].id];
      }
    }
    if (cible != null) {
      cible.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  // ════════════════════════════════════════════════════════════════
  // INTERFACE
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_modifie,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final choix = await _demanderQuoiFaire();
        if (!mounted) return;
        if (choix == _ChoixModifs.enregistrer) {
          if (await _enregistrer() && mounted) Navigator.of(this.context).pop();
        } else if (choix == _ChoixModifs.abandonner) {
          _remplissage = true;
          for (final e in _eleves) {
            final init = _initial[e.id] ?? ('', '');
            _classeCtrl[e.id]!.text = init.$1;
            _compoCtrl[e.id]!.text = init.$2;
          }
          _remplissage = false;
          setState(() {});
          Navigator.of(this.context).pop();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _enregistrer(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(
              title: Text("Saisie des notes — ${widget.className}"),
              actions: [
                if (_modifie)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: Text(
                        "$_nbModifs modification(s) non enregistrée(s)",
                        style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: ElevatedButton.icon(
                    onPressed: (_modifie && !_enregistrement) ? _enregistrer : null,
                    icon: _enregistrement
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: const Text("Enregistrer (Ctrl+S)"),
                  ),
                ),
              ],
            ),
            body: _chargement && _courses.isEmpty && _eleves.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : (_courses.isEmpty
                    ? _messageVide("Aucune matière dans cette classe.",
                        "Ajoutez d'abord les matières (et leurs coefficients) en modifiant la classe.")
                    : (_eleves.isEmpty
                        ? _messageVide("Aucun élève dans cette classe.", "Ajoutez ou importez d'abord les élèves.")
                        : _buildContenu())),
          ),
        ),
      ),
    );
  }

  Widget _messageVide(String titre, String texte) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, size: 48, color: AppTheme.textLight.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(texte, style: const TextStyle(color: AppTheme.textLight)),
        ],
      ),
    );
  }

  Widget _buildContenu() {
    final indexCours = _courses.indexWhere((c) => c.id == _coursId);
    final stats = StatsMatiere.depuis([for (final e in _eleves) _moyenne(e.id!)], bareme: _bareme);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Choix de la matière et du trimestre ──
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: "Matière précédente",
                onPressed: indexCours > 0 ? () => _changerMatiere(_courses[indexCours - 1].id) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('matiere-$_coursId-$_rev'),
                  initialValue: _coursId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Matière", isDense: true),
                  items: [
                    for (final c in _courses)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(_primaire ? c.nom : "${c.nom}  (coef. ${c.coefficient})",
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _changerMatiere,
                ),
              ),
              IconButton.outlined(
                tooltip: "Matière suivante",
                onPressed: (indexCours >= 0 && indexCours < _courses.length - 1)
                    ? () => _changerMatiere(_courses[indexCours + 1].id)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text("1er trimestre")),
                  ButtonSegment(value: 2, label: Text("2e trimestre")),
                  ButtonSegment(value: 3, label: Text("3e trimestre")),
                ],
                selected: {_trimestre},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _changerTrimestre(s.first),
              ),
              if (!_primaire)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Touche Entrée : ", style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
                    DropdownButton<bool>(
                      value: _ordreColonne,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(fontSize: 12, color: AppTheme.textDark, fontFamily: AppTheme.fontFamily),
                      items: const [
                        DropdownMenuItem(value: false, child: Text("ligne par ligne (classe → compo)")),
                        DropdownMenuItem(value: true, child: Text("colonne par colonne")),
                      ],
                      onChanged: (v) => setState(() => _ordreColonne = v ?? false),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Statistiques en direct ──
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _chip(Icons.edit_note_rounded, "Notés : ${stats.notes} / ${stats.effectif}", AppTheme.primary),
              _chip(Icons.functions_rounded,
                  "Moyenne de la classe : ${stats.moyenne != null ? formatNote(stats.moyenne!) : '—'} / $_bareme",
                  AppTheme.secondary),
              _chip(Icons.arrow_upward_rounded, "Plus forte : ${stats.max != null ? formatNote(stats.max!) : '—'}",
                  AppTheme.success),
              _chip(Icons.arrow_downward_rounded, "Plus faible : ${stats.min != null ? formatNote(stats.min!) : '—'}",
                  AppTheme.error),
              _chip(Icons.warning_amber_rounded, "Sous la moyenne : ${stats.sousLaMoyenne}", AppTheme.warning),
            ],
          ),
          const SizedBox(height: 14),

          // ── Tableau ──
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  _ligneEntete(),
                  const Divider(height: 1),
                  Expanded(
                    child: _chargement
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: _eleves.length,
                            itemBuilder: (context, i) => _ligneEleve(i),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _primaire
                ? "Primaire : note de composition sur 10. Laissez vide si l'élève n'a pas composé."
                : "Note de classe sur 20, composition sur 40. Moyenne de la matière = (classe + composition) / 3. "
                    "Laissez vide si l'élève n'a pas composé.",
            style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
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
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ],
      ),
    );
  }

  static const double _largeurNote = 120;
  static const double _largeurMoyenne = 110;

  Widget _ligneEntete() {
    const style = TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textMedium);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppTheme.surfaceAlt,
      child: Row(
        children: [
          const SizedBox(width: 40, child: Text("N°", style: style)),
          const Expanded(child: Text("Élève", style: style)),
          if (!_primaire)
            const SizedBox(width: _largeurNote, child: Text("Note de classe /20", style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 12),
          SizedBox(
            width: _largeurNote,
            child: Text(_primaire ? "Composition /10" : "Composition /40", style: style, textAlign: TextAlign.center),
          ),
          if (!_primaire) ...[
            const SizedBox(width: 12),
            const SizedBox(
                width: _largeurMoyenne, child: Text("Moyenne /20", style: style, textAlign: TextAlign.center)),
          ],
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _champ({
    required TextEditingController ctrl,
    required FocusNode focus,
    required String? erreur,
    required VoidCallback onSuivant,
  }) {
    final bordure = erreur != null ? AppTheme.error : AppTheme.border;
    final champ = TextField(
        controller: ctrl,
        focusNode: focus,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => onSuivant(),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: erreur != null ? AppTheme.error : AppTheme.textDark,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: "—",
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          fillColor: erreur != null ? AppTheme.error.withValues(alpha: 0.06) : AppTheme.surfaceAlt,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: bordure, width: erreur != null ? 1.5 : 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: erreur != null ? AppTheme.error : AppTheme.primary, width: 2),
          ),
        ),
    );
    return erreur != null ? Tooltip(message: erreur, child: champ) : champ;
  }

  Widget _ligneEleve(int i) {
    final e = _eleves[i];
    final id = e.id!;
    final moyenne = _moyenne(id);
    final modifiee = _ligneModifiee(id);
    final erreur = _erreurClasse(id) ?? _erreurCompo(id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: modifiee ? AppTheme.warning.withValues(alpha: 0.05) : (i.isOdd ? AppTheme.background : AppTheme.surface),
        border: const Border(bottom: BorderSide(color: AppTheme.borderLight)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text("${i + 1}", style: const TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${e.nom} ${e.prenom}",
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5), overflow: TextOverflow.ellipsis),
                if ((e.matricule ?? '').isNotEmpty)
                  Text(e.matricule!, style: const TextStyle(color: AppTheme.textLight, fontSize: 11)),
              ],
            ),
          ),
          if (!_primaire)
            SizedBox(
              width: _largeurNote,
              child: _champ(
                ctrl: _classeCtrl[id]!,
                focus: _classeFocus[id]!,
                erreur: _erreurClasse(id),
                onSuivant: () => _suivant(i, depuisClasse: true),
              ),
            ),
          const SizedBox(width: 12),
          SizedBox(
            width: _largeurNote,
            child: _champ(
              ctrl: _compoCtrl[id]!,
              focus: _compoFocus[id]!,
              erreur: _erreurCompo(id),
              onSuivant: () => _suivant(i, depuisClasse: false),
            ),
          ),
          if (!_primaire) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: _largeurMoyenne,
              child: Text(
                moyenne != null ? formatNote(moyenne) : "—",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: moyenne == null
                      ? AppTheme.textLight
                      : (moyenne >= _bareme / 2 ? AppTheme.success : AppTheme.error),
                ),
              ),
            ),
          ],
          SizedBox(
            width: 36,
            child: erreur != null
                ? Tooltip(
                    message: erreur,
                    child: const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 18),
                  )
                : (modifiee
                    ? const Tooltip(
                        message: "Modifiée, pas encore enregistrée",
                        child: Icon(Icons.edit_rounded, color: AppTheme.warning, size: 16),
                      )
                    : null),
          ),
        ],
      ),
    );
  }
}
