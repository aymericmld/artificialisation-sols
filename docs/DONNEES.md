# Récupérer les données

Le projet n'a besoin que d'un fichier : la consommation d'espaces par commune publiée par le Cerema. Il contient aussi la population, les ménages et les emplois des recensements de l'INSEE. Les données brutes ne sont pas versionnées (`data/raw/` est exclu par `.gitignore`).

## Consommation d'espaces naturels, agricoles et forestiers 2011-2025

| | |
|---|---|
| Page | [data.gouv.fr : Consommation d'espaces naturels, agricoles et forestiers du 1er janvier 2011 au 1er janvier 2025](https://www.data.gouv.fr/datasets/consommation-despaces-naturels-agricoles-et-forestiers-du-1er-janvier-2011-au-1er-janvier-2025) |
| Ressource | `conso_com.csv` (31 Mo), une ligne par commune |
| Producteur | Cerema pour la DGALN, à partir des Fichiers fonciers (DGFiP) |
| Licence | Licence Ouverte 2.0 |
| Documentation | [Dictionnaire des champs (Cerema)](https://doc-datafoncier.cerema.fr/doc/export/504) |
| Déposer dans | `data/raw/conso-com.csv` |

Un autre emplacement peut être indiqué par la variable d'environnement `ARTIF_FICHIER_CONSO`.

### Ce que contient le fichier

- **Identifiants** au code officiel géographique 2025 : commune, EPCI, département, région, Scot.
- **Zonages** : aire d'attraction des villes, grille de densité, loi Littoral, zone ABC.
- **Flux annuels** de consommation, du 1er janvier 2011 au 1er janvier 2025, total (`naf11art12`, …) et par destination (`art11hab12` pour l'habitat, `act` activité, `mix` mixte, `rou` routes, `fer` voies ferrées, `inc` inconnue).
- **Cumuls** sur 2011-2021, 2021-2025, 2011-2025 et 2011-2022.
- **Recensements** 2011, 2016 et 2022 : population (`pop`), ménages (`men`), emplois (`emp`).
- **Surface communale** (`surfcom2025`, en m²).

### Point d'attention : les unités

La documentation du Cerema annonce des flux en hectares. Dans le fichier, ils sont en **m²** : la somme nationale de 2011 vaut 294,7 millions, soit 29 470 ha, et celle de 2024 donne exactement les 15 119 ha publiés par le Cerema pour cette année. La conversion est faite à la lecture (`R/lecture.R`).

## Contours des départements

`data/reference/departements.geojson` est versionné : c'est la version simplifiée des contours de [france-geojson](https://github.com/gregoiredavid/france-geojson), elle-même dérivée d'Admin Express (IGN). Il sert à la carte personnalisée de Metabase (propriété `code`).

## Pour aller plus loin

D'autres sources se raccordent par le code commune ou le code EPCI :

| Source | Intérêt | Lien |
|---|---|---|
| DVF+ (Cerema) | Prix des terrains à bâtir | [data.gouv.fr](https://www.data.gouv.fr/datasets/dvf-open-data) |
| OCS GE (IGN) | Artificialisation au sens strict, par département et par millésime | [data.gouv.fr](https://www.data.gouv.fr/datasets/ocs-ge-artificialisation) |
| Base du comparateur de territoires (INSEE) | Logements, revenus, emploi par commune | [insee.fr](https://www.insee.fr/fr/statistiques/2521169) |
