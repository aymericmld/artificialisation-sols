# Tableau de bord Metabase

Le tableau de bord lit les vues que `Rscript run.R base` crée dans PostgreSQL. Toutes les requêtes sont dans [`metabase/questions.sql`](../metabase/questions.sql).

## 1. Démarrer PostgreSQL et Metabase

```bash
docker compose up -d
```

PostgreSQL écoute sur `localhost:5432` (base `artificialisation`, utilisateur `postgres`, mot de passe `artif`) et Metabase sur <http://localhost:3000>. La configuration de Metabase (comptes, questions, tableaux de bord) est conservée dans `metabase/donnees/`, qui n'est pas versionné.

## 2. Charger les données

```bash
cp .Renviron.example .Renviron
Rscript run.R base
```

L'étape recalcule tout, puis écrit huit tables et cinq vues dans le schéma `artif`, dont 2,9 millions de lignes de flux annuels (commune × année × destination). Compter une à deux minutes.

| Vue | Contenu |
|---|---|
| `v_chiffres_cles` | Une ligne : rythmes, enveloppe, part consommée, rythme requis |
| `v_flux_annuel` | Flux annuels par commune et destination, avec région, département, EPCI et période |
| `v_trajectoire_epci` | Trajectoire, efficacité et écart au modèle par intercommunalité |
| `v_trajectoire_departement` | Trajectoire par département, pour la carte |
| `v_communes` | Trajectoire et croissance par commune |

## 3. Connecter Metabase

Au premier lancement, Metabase demande de créer un compte, puis d'ajouter une base :

| Champ | Valeur |
|---|---|
| Type | PostgreSQL |
| Hôte | `postgis` (nom du service Docker ; `localhost` si Metabase tourne hors Docker) |
| Port | `5432` |
| Base | `artificialisation` |
| Utilisateur / mot de passe | `postgres` / `artif` |
| Schémas | `artif` uniquement |

## 4. Ajouter la carte des départements

Administration → Paramètres → Cartes → Ajouter une carte :

- URL : `https://raw.githubusercontent.com/aymericmld/artificialisation-sols/main/data/reference/departements.geojson`
- Identifiant de région : `code` ; nom affiché : `nom`.

## 5. Monter le tableau de bord

Créer chaque question en SQL natif depuis `metabase/questions.sql`, avec la visualisation indiquée en commentaire, puis les placer sur un tableau de bord « Artificialisation des sols ». Disposition proposée :

```text
┌───────────────┬───────────────┬───────────────┬───────────────┐
│ Rythme        │ Évolution     │ Enveloppe     │ Rythme requis │   1. chiffres clés
│ 2021-2023     │ du rythme     │ consommée     │ 2025-2030     │
├───────────────┴───────────────┴───────┬───────┴───────────────┤
│ 2. Consommation annuelle par          │ 3. Carte des          │
│    destination                        │    départements       │
├───────────────────────────────────────┼───────────────────────┤
│ 5. Tableau des intercommunalités      │ 4. EPCI par           │
│                                       │    trajectoire        │
├───────────────────────────────────────┼───────────────────────┤
│ 6. Consommation et ménages gagnés     │ 7. m² par ménage      │
│    par commune                        │    selon la densité   │
└───────────────────────────────────────┴───────────────────────┘
```

Ajouter trois filtres « Texte ou catégorie » (Région, Département, Intercommunalité) et les relier aux variables `{{region}}`, `{{departement}}` et `{{epci}}` des questions qui les utilisent. Choisir un département met alors à jour la série annuelle, la carte, la répartition des EPCI et le tableau.

## 6. Mettre à jour

À chaque nouveau millésime du Cerema : remplacer `data/raw/conso-com.csv`, ajuster les années dans `R/config.R` si besoin, relancer `Rscript run.R base`. Les questions Metabase n'ont pas à être modifiées.
