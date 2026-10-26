import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../providers/app_state_provider.dart';
import '../services/carte_scolaire_service.dart';
import '../services/text_utils.dart';
import '../theme/app_theme.dart';

/// Génération des cartes scolaires (avec QR code) des élèves de l'année sélectionnée.
class CartesScolairesScreen extends StatefulWidget {
  const CartesScolairesScreen({super.key});

  @override
  State<CartesScolairesScreen> createState() => _CartesScolairesScreenState();
}

class _CartesScolairesScreenState extends State<CartesScolairesScreen> {
  bool _chargement = true;
  int? _anneeChargee;
  List<CarteEleve> _cartes = [];
  final Set<int> _selection = {};
  int? _classeFiltre;
  final TextEditingController _rechercheCtrl = TextEditingController();

  // Options
  CouleurCarte _couleur = OptionsCarte.couleurs.first;
  bool _photo = true;
  bool _verso = false;
  final TextEditingController _signataireCtrl = TextEditingController(text: 'Le Directeur');

  // Aperçu
  int? _eleveApercu;
  Uint8List? _apercuRecto;
  Uint8List? _apercuVerso;
  int _jetonApercu = 0;
  bool _generation = false;

  @override
  void initState() {
    super.initState();
    _rechercheCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    _signataireCtrl.dispose();
    super.dispose();
  }

  OptionsCarte get _options => OptionsCarte(
        couleur: _couleur,
        afficherPhoto: _photo,
        verso: _verso,
        signataire: _signataireCtrl.text.trim().isEmpty ? 'Le Directeur' : _signataireCtrl.text.trim(),
      );

  Future<void> _charger() async {
    final state = context.read<AppStateProvider>();
    final annee = state.selectedAnneeScolaire;
    setState(() => _chargement = true);
    final eleves = await state.getElevesAnnee();
    if (!mounted) return;
    final noms = {for (final c in state.classes) c.id!: c.nom};
    final cartes = eleves.map((e) => CarteEleve(e, noms[e.classeId] ?? '')).toList()
      ..sort((a, b) {
        final c = a.classeNom.compareTo(b.classeNom);
        if (c != 0) return c;
        final n = a.eleve.nom.compareTo(b.eleve.nom);
        return n != 0 ? n : a.eleve.prenom.compareTo(b.eleve.prenom);
      });
    setState(() {
      _cartes = cartes;
      _anneeChargee = annee?.id;
      _selection
        ..clear()
        ..addAll(cartes.map((c) => c.eleve.id!));
      _eleveApercu = cartes.isNotEmpty ? cartes.first.eleve.id : null;
      if (_classeFiltre != null && !state.classes.any((c) => c.id == _classeFiltre)) _classeFiltre = null;
      _chargement = false;
    });
    _rafraichirApercu();
  }

  List<CarteEleve> get _filtrees {
    final q = normaliser(_rechercheCtrl.text);
    return _cartes.where((c) {
      if (_classeFiltre != null && c.eleve.classeId != _classeFiltre) return false;
      if (q.isEmpty) return true;
      final e = c.eleve;
      return normaliser('${e.nom} ${e.prenom} ${e.prenom} ${e.nom} ${e.matricule ?? ''}').contains(q);
    }).toList();
  }

  CarteEleve? get _carteApercu {
    for (final c in _cartes) {
      if (c.eleve.id == _eleveApercu) return c;
    }
    return _cartes.isNotEmpty ? _cartes.first : null;
  }

  Future<void> _rafraichirApercu() async {
    final state = context.read<AppStateProvider>();
    final etab = state.etablissement;
    final carte = _carteApercu;
    final annee = state.selectedAnneeScolaire?.libelle ?? etab?.anneeScolaire ?? '';
    if (etab == null || carte == null) {
      setState(() {
        _apercuRecto = null;
        _apercuVerso = null;
      });
      return;
    }
    final jeton = ++_jetonApercu;
    try {
      Future<Uint8List?> image(bool verso) async {
        final pdf = await CarteScolaireService.genererApercu(
          etablissement: etab,
          anneeScolaire: annee,
          carte: carte,
          options: _options,
          verso: verso,
        );
        await for (final page in Printing.raster(pdf, pages: [0], dpi: 220)) {
          return page.toPng();
        }
        return null;
      }

      final recto = await image(false);
      final verso = _verso ? await image(true) : null;
      if (!mounted || jeton != _jetonApercu) return; // un aperçu plus récent est en cours
      setState(() {
        _apercuRecto = recto;
        _apercuVerso = verso;
      });
    } catch (_) {
      // L'aperçu est facultatif : en cas d'erreur, on garde l'ancien
    }
  }

  Future<void> _generer(List<CarteEleve> cartes) async {
    final state = context.read<AppStateProvider>();
    final etab = state.etablissement;
    if (etab == null || etab.nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Configurez d'abord les paramètres de l'établissement (nom, logo) dans Paramètres."),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    if (cartes.isEmpty) return;
    setState(() => _generation = true);
    try {
      final annee = state.selectedAnneeScolaire?.libelle ?? etab.anneeScolaire;
      final bytes = await CarteScolaireService.genererPlanches(
        etablissement: etab,
        anneeScolaire: annee,
        cartes: cartes,
        options: _options,
      );
      if (!mounted) return;
      setState(() => _generation = false);
      await showDialog(
        context: context,
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text("Cartes scolaires — ${cartes.length} carte(s)"),
            leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(ctx).pop()),
          ),
          body: PdfPreview(
            build: (_) async => bytes,
            pdfFileName: 'cartes_scolaires_${annee.replaceAll(' ', '_')}.pdf',
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de la génération des cartes : $e"), backgroundColor: AppTheme.error),
      );
    }
  }

  // ════════════════════════════════════════════════════════════════
  // INTERFACE
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final annee = state.selectedAnneeScolaire;
    if (!_chargement && annee?.id != _anneeChargee) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _charger();
      });
    }
    final etabConfigure = state.etablissement != null && state.etablissement!.nom.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text("Cartes scolaires${annee != null ? ' — ${annee.libelle}' : ''}"),
        actions: [
          IconButton(
            tooltip: "Actualiser la liste des élèves",
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (!etabConfigure)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        "Renseignez le nom, l'adresse et le logo de l'établissement dans Paramètres : ils apparaissent sur chaque carte.",
                        style: TextStyle(color: Colors.amber.shade900),
                      ),
                    ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: _buildListe(state)),
                        const SizedBox(width: 20),
                        SizedBox(width: 430, child: _buildApercuEtOptions()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildListe(AppStateProvider state) {
    final liste = _filtrees;
    final toutesSelectionnees = liste.isNotEmpty && liste.every((c) => _selection.contains(c.eleve.id));
    final selectionnees = _cartes.where((c) => _selection.contains(c.eleve.id)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rechercheCtrl,
                    decoration: const InputDecoration(
                      hintText: "Rechercher un élève",
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey('classe-cartes-$_classeFiltre'),
                    initialValue: _classeFiltre,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(labelText: "Classe", isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text("Toutes les classes")),
                      for (final c in state.classes) DropdownMenuItem<int?>(value: c.id, child: Text(c.nom)),
                    ],
                    onChanged: (v) => setState(() => _classeFiltre = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: toutesSelectionnees,
                  onChanged: liste.isEmpty
                      ? null
                      : (v) => setState(() {
                            for (final c in liste) {
                              if (v == true) {
                                _selection.add(c.eleve.id!);
                              } else {
                                _selection.remove(c.eleve.id);
                              }
                            }
                          }),
                ),
                Text("Tout sélectionner (${liste.length})", style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text("${selectionnees.length} carte(s) sélectionnée(s)",
                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
              ],
            ),
            const Divider(),
            Expanded(
              child: liste.isEmpty
                  ? const Center(
                      child: Text("Aucun élève pour cette sélection.", style: TextStyle(color: AppTheme.textLight)))
                  : ListView.builder(
                      itemCount: liste.length,
                      itemBuilder: (context, i) => _ligneEleve(liste[i]),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Format carte bancaire (85,6 × 54 mm) — 10 cartes par feuille A4, traits de coupe inclus."
                    "${_verso ? ' Verso sur la page suivante (recto-verso, bord long).' : ''}",
                    style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: (selectionnees.isEmpty || _generation) ? null : () => _generer(selectionnees),
                  icon: _generation
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.badge_rounded, size: 18),
                  label: Text("Générer ${selectionnees.length} carte(s) (PDF)"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneEleve(CarteEleve c) {
    final e = c.eleve;
    final aPhoto = e.photoPath != null && e.photoPath!.isNotEmpty && File(e.photoPath!).existsSync();
    final enApercu = e.id == _eleveApercu;
    return Material(
      color: enApercu ? AppTheme.primary.withValues(alpha: 0.06) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() => _eleveApercu = e.id);
          _rafraichirApercu();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: _selection.contains(e.id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selection.add(e.id!);
                  } else {
                    _selection.remove(e.id);
                  }
                }),
              ),
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                backgroundImage: aPhoto ? FileImage(File(e.photoPath!)) : null,
                child: aPhoto
                    ? null
                    : Text(
                        "${e.nom.isNotEmpty ? e.nom[0] : ''}${e.prenom.isNotEmpty ? e.prenom[0] : ''}",
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${e.prenom} ${e.nom}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    Text(
                      "${c.classeNom}${(e.matricule ?? '').isNotEmpty ? ' · ${e.matricule}' : ''}",
                      style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!aPhoto)
                const Tooltip(
                  message: "Pas de photo : les initiales seront affichées",
                  child: Icon(Icons.no_photography_outlined, size: 18, color: AppTheme.textLight),
                ),
              IconButton(
                tooltip: "Imprimer la carte de cet élève",
                onPressed: _generation ? null : () => _generer([c]),
                icon: const Icon(Icons.print_rounded, size: 18, color: AppTheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApercuEtOptions() {
    final carte = _carteApercu;
    return SingleChildScrollView(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Aperçu", style: Theme.of(context).textTheme.titleMedium),
              if (carte != null)
                Text("${carte.eleve.prenom} ${carte.eleve.nom} — cliquez sur un élève pour voir sa carte",
                    style: const TextStyle(color: AppTheme.textLight, fontSize: 12)),
              const SizedBox(height: 12),
              _imageCarte(_apercuRecto),
              if (_verso) ...[
                const SizedBox(height: 10),
                _imageCarte(_apercuVerso),
              ],
              const SizedBox(height: 20),
              const Text("Couleur de la carte", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final c in OptionsCarte.couleurs)
                    Tooltip(
                      message: c.nom,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          setState(() => _couleur = c);
                          _rafraichirApercu();
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c.argb),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _couleur == c ? AppTheme.textDark : Colors.white,
                              width: _couleur == c ? 3 : 2,
                            ),
                          ),
                          child: _couleur == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Afficher la photo de l'élève"),
                subtitle: const Text("Sans photo, les initiales sont affichées."),
                value: _photo,
                onChanged: (v) {
                  setState(() => _photo = v);
                  _rafraichirApercu();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Imprimer aussi le verso"),
                subtitle: const Text("Règles d'usage et contact de l'école au dos de la carte."),
                value: _verso,
                onChanged: (v) {
                  setState(() => _verso = v);
                  _rafraichirApercu();
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _signataireCtrl,
                decoration: const InputDecoration(labelText: "Signataire", hintText: "Le Directeur", isDense: true),
                onSubmitted: (_) => _rafraichirApercu(),
                onEditingComplete: _rafraichirApercu,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: AppTheme.primary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Le QR code de chaque carte contient l'école, l'année, le nom, la classe, le matricule, "
                        "la date de naissance et le contact du parent. Il se lit avec n'importe quel téléphone "
                        "(appareil photo ou application de scan), sans Internet.",
                        style: TextStyle(fontSize: 12, color: AppTheme.textMedium),
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

  Widget _imageCarte(Uint8List? png) {
    return AspectRatio(
      aspectRatio: CarteScolaireService.largeurMm / CarteScolaireService.hauteurMm,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: png == null
            ? const Center(child: Text("Aperçu indisponible", style: TextStyle(color: AppTheme.textLight)))
            : Image.memory(png, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }
}
