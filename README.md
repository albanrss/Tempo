# Tempo

Application Android développée en Flutter permettant de limiter le temps d'utilisation des applications par heure.

## Fonctionnalités

- **Limites de temps par application** — Définir une durée maximale d'utilisation (0 à 60 minutes par heure) pour chaque application individuellement.
- **Blocage automatique** — Les applications sont bloquées lorsque le temps autorisé est écoulé, via un service d'accessibilité Android.
- **Notifications** — Alertes quand une limite est atteinte ou sur le point de l'être.
- **Protection par code PIN** — Un code PIN à 4 chiffres protège l'accès aux réglages.
- **Suivi en temps réel** — Visualisation du temps d'utilisation actuel de chaque application limitée.

## Prérequis

- Flutter SDK `^3.10.0`
- Android SDK
- [just](https://github.com/casey/just) (optionnel, pour les commandes de build)

## Installation

```bash
git clone <repo-url>
cd Tempo
flutter pub get
```

## Commandes

| Commande | Description |
|---|---|
| `just clean` | Nettoyage du projet |
| `just test` | Lancement des tests |
| `just run-debug` | Lancement en mode debug |
| `just build-apk` | Build APK release |
| `just run-release` | Lancement en mode release |

Ou directement via Flutter :

```bash
flutter run            # debug
flutter build apk      # release APK
```

## Architecture

```
lib/
├── main.dart                    # Point d'entrée
├── constants/
│   ├── app_constants.dart       # Constantes de l'application
│   └── app_theme.dart           # Thème (noir & blanc minimaliste)
├── screens/
│   ├── spinning_logo_screen.dart  # Écran de démarrage animé
│   ├── pin_screen.dart            # Vérification / configuration du PIN
│   ├── app_lister_screen.dart     # Liste des applications installées
│   ├── app_limit_screen.dart      # Réglage de la limite de temps
│   ├── active_limits_screen.dart  # Limites actives et usage en cours
│   └── setup_screen.dart          # Configuration initiale
└── services/
    ├── app_cache.dart             # Cache disque des applications
    ├── native_bridge.dart         # Communication avec le code natif Android
    ├── password_service.dart      # Gestion du code PIN
    └── time_limit_manager.dart    # CRUD des limites de temps
```

Côté Android natif (Kotlin) :

- **`AppBlockerAccessibilityService`** — Service d'accessibilité qui surveille l'application au premier plan, calcule le temps d'utilisation horaire via l'API UsageStats, et bloque l'accès quand la limite est dépassée.
- **`MainActivity`** — Point d'entrée Flutter avec MethodChannel pour la communication Flutter ↔ Android.

## Permissions requises

L'application demande les permissions suivantes à l'utilisateur lors de la configuration :

- **Accès aux statistiques d'utilisation** — Pour mesurer le temps passé sur chaque application.
- **Service d'accessibilité** — Pour détecter et bloquer les applications en temps réel.
- **Notifications** — Pour les alertes de limite atteinte.

## Stack technique

| Composant | Technologie |
|---|---|
| UI | Flutter / Dart |
| Blocage applicatif | Kotlin (AccessibilityService) |
| Stockage | SharedPreferences |
| Suivi d'usage | Android UsageStats API |