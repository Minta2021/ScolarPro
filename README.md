# ScolarPro — Bulletin automatique

Application de bureau (Flutter + SQLite) pour la gestion scolaire d'un établissement : bulletins, statistiques et comptabilité.

## Fonctionnalités

- Paramètres de l'établissement (nom, adresse, téléphone, logo, années scolaires)
- Classes, matières et coefficients ; frais d'inscription et de scolarité par classe
- Élèves : saisie manuelle (avec téléphone du parent) ou **assistant d'import Excel/CSV**
  - toute l'école en une fois : colonne « Classe » ou une feuille par classe
  - colonnes reconnues automatiquement (et modifiables), nom complet dans une seule colonne
  - création automatique des classes manquantes, détection des doublons, aperçu avant import
- Saisie des notes par trimestre
- Bulletins avec moyenne, mention et rang (gestion des ex aequo), export PDF / impression
- Statistiques, export Excel, passage de classe en fin d'année
- **Comptabilité** : encaissements (inscription / scolarité), remises, reçus PDF numérotés
  avec montant en lettres, tableau de bord (nombre d'élèves en règle, partiels, impayés,
  taux de recouvrement), journal des encaissements, listes imprimables, export Excel
- **Paiement combiné** : inscription et scolarité encaissées ensemble sur un même reçu
- **Cartes scolaires** : cartes au format carte bancaire (85,6 × 54 mm) avec photo et **QR code**,
  8 par feuille A4 (2 × 4) avec traits de coupe, verso en option aligné au millimètre derrière chaque recto
  (recto et verso de mêmes dimensions et même gabarit), 6 couleurs au choix
- **Sauvegarde / restauration** complète (base + logo + photos) dans un fichier .zip
- Police Inter embarquée : affichage identique avec ou sans Internet

## Calcul des moyennes

- Note de classe sur 20, note de composition sur 40
- Moyenne du cours = (note de classe + note de composition) / 3
  (équivaut à `(classe + compo/20 × 2) / 3`)
- Moyenne générale = Σ(moyenne du cours × coefficient) / Σ(coefficients)
- Primaire : note de composition sur 10, moyenne sans coefficient

## Développement

Prérequis : Flutter (canal stable) avec le support Windows desktop, Visual Studio 2022+ (charge « Développement Desktop en C++»).

```bash
flutter pub get
flutter run -d windows
```

Tests et analyse :

```bash
flutter test
flutter analyze
```

## Créer l'installateur Windows

1. `flutter build windows --release` (produit `build\windows\x64\runner\Release\ScolarPro.exe`)
2. Compiler `installer.iss` avec Inno Setup → `installer\scolarpro_installer.exe`
