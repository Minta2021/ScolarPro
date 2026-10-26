/// Un versement d'argent enregistré pour un élève (frais d'inscription ou de scolarité).
class Paiement {
  static const String typeInscription = 'inscription';
  static const String typeScolarite = 'scolarite';

  static const List<String> modes = [
    'Espèces',
    'Orange Money',
    'Moov Money',
    'Wave',
    'Chèque',
    'Virement bancaire',
    'Autre',
  ];

  static String libelleType(String type) =>
      type == typeInscription ? "Frais d'inscription" : 'Frais de scolarité';

  final int? id;
  final int eleveId;
  final String type; // 'inscription' | 'scolarite'
  final double montant;
  final String datePaiement; // format ISO aaaa-MM-jj
  final String? mode;
  final String? numeroRecu;
  final String? observation;

  // Champs joints (remplis par les requêtes du journal)
  final String? eleveNom;
  final String? elevePrenom;
  final String? eleveMatricule;
  final String? classeNom;
  final int? classeId;

  Paiement({
    this.id,
    required this.eleveId,
    required this.type,
    required this.montant,
    required this.datePaiement,
    this.mode,
    this.numeroRecu,
    this.observation,
    this.eleveNom,
    this.elevePrenom,
    this.eleveMatricule,
    this.classeNom,
    this.classeId,
  });

  String get libelle => libelleType(type);

  DateTime get date => DateTime.tryParse(datePaiement) ?? DateTime.now();

  String get eleveNomComplet => '${elevePrenom ?? ''} ${eleveNom ?? ''}'.trim();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'eleve_id': eleveId,
      'type': type,
      'montant': montant,
      'date_paiement': datePaiement,
      'mode': mode,
      'numero_recu': numeroRecu,
      'observation': observation,
    };
  }

  factory Paiement.fromMap(Map<String, dynamic> map) {
    return Paiement(
      id: map['id'] as int?,
      eleveId: map['eleve_id'] as int,
      type: map['type'] as String,
      montant: (map['montant'] as num).toDouble(),
      datePaiement: map['date_paiement'] as String,
      mode: map['mode'] as String?,
      numeroRecu: map['numero_recu'] as String?,
      observation: map['observation'] as String?,
      eleveNom: map['eleve_nom'] as String?,
      elevePrenom: map['eleve_prenom'] as String?,
      eleveMatricule: map['eleve_matricule'] as String?,
      classeNom: map['classe_nom'] as String?,
      classeId: map['classe_id'] as int?,
    );
  }
}
