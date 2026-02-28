# Elections-Backend

Backend API pour l'application de suivi de dépouillement électoral.

Développé avec **Vapor 4** (Swift), **Fluent** et **SQLite**.

## Prérequis

- Swift 5.9+
- macOS 13+ ou Linux (Ubuntu 22.04+)

## Installation et démarrage

```bash
# Cloner le repo
git clone https://github.com/VOTRE_USERNAME/Elections-Backend.git
cd Elections-Backend

# Compiler et lancer
swift run

# L'API est disponible sur http://localhost:8080
```

## Variables d'environnement

| Variable | Description | Défaut |
|----------|-------------|--------|
| `JWT_SECRET` | Clé secrète pour signer les JWT | `elections-secret-key-change-in-production` |
| `PORT` | Port d'écoute | `8080` |

**⚠️ Changez `JWT_SECRET` en production !**

## Compte admin par défaut

- Email : `admin@elections.local`
- Mot de passe : `admin123`

**Changez ce mot de passe immédiatement après le premier login !**

## API Reference

### Publique (sans authentification)

| Méthode | Route | Description |
|---------|-------|-------------|
| GET | `/api/v1/synthese` | Synthèse globale de la commune |
| GET | `/api/v1/bureaux` | Liste de tous les bureaux |
| GET | `/api/v1/bureaux/:id` | Détail d'un bureau |
| GET | `/api/v1/candidats` | Liste des candidats |

### Authentification

| Méthode | Route | Description |
|---------|-------|-------------|
| POST | `/api/v1/auth/login` | Connexion (retourne JWT) |

### Scrutateurs (JWT requis)

| Méthode | Route | Description |
|---------|-------|-------------|
| PUT | `/api/v1/bureaux/:id` | Mettre à jour les infos du bureau |
| POST | `/api/v1/bureaux/:id/participations` | Saisir/mettre à jour la participation |
| POST | `/api/v1/bureaux/:id/resultats` | Saisir/mettre à jour les résultats |

### Administration (JWT admin requis)

| Méthode | Route | Description |
|---------|-------|-------------|
| POST | `/api/v1/bureaux` | Créer un bureau |
| DELETE | `/api/v1/bureaux/:id` | Supprimer un bureau |
| POST | `/api/v1/bureaux/:id/scrutateurs/:userId` | Assigner un scrutateur |
| DELETE | `/api/v1/bureaux/:id/scrutateurs/:userId` | Retirer un scrutateur |
| GET | `/api/v1/users` | Liste des utilisateurs |
| POST | `/api/v1/users` | Créer un utilisateur |
| DELETE | `/api/v1/users/:id` | Supprimer un utilisateur |
| POST | `/api/v1/candidats` | Créer un candidat |
| PUT | `/api/v1/candidats/:id` | Modifier un candidat |
| DELETE | `/api/v1/candidats/:id` | Supprimer un candidat |
| DELETE | `/api/v1/reset` | Réinitialiser toutes les données de vote |

## Exemple de requête login

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@elections.local", "password": "admin123"}'
```

## Déploiement

### Docker

```dockerfile
FROM swift:5.9-focal AS builder
WORKDIR /app
COPY . .
RUN swift build -c release

FROM swift:5.9-focal-slim
WORKDIR /app
COPY --from=builder /app/.build/release/Run .
EXPOSE 8080
CMD ["./Run", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
```
