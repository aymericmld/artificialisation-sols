# Méthodologie

## Ce qui est mesuré

La loi Climat et résilience (2021) fixe deux objectifs : diviser par deux la consommation d'espaces naturels, agricoles et forestiers (ENAF) sur 2021-2031 par rapport à 2011-2021, puis atteindre le « zéro artificialisation nette » en 2050. Jusqu'en 2031, la mesure de référence est la **consommation d'espaces** : la création ou l'extension effective d'espaces urbanisés.

Le Cerema la calcule chaque année à partir des Fichiers fonciers, la base fiscale de la taxe foncière : une parcelle qui passe d'un usage naturel, agricole ou forestier à un usage urbanisé compte comme consommée, l'année où son aménagement commence. Ce sont les données officielles de suivi de l'objectif.

## Conventions

| Convention | Choix |
|---|---|
| Année | L'année N désigne le flux du 1er janvier N au 1er janvier N+1, comme dans les publications du Cerema |
| Décennie de référence | 2011 à 2020 (flux 2011-2021) |
| Rythme actuel | Moyenne 2021-2023 |
| Cumul consommé | 2021 à 2024, borne basse |
| Unités | Hectares, après conversion des m² du fichier |
| Géographie | Code officiel géographique 2025, sur toute la série |

### Pourquoi le rythme s'arrête en 2023

Le Cerema indique que les chiffres de 2024 sont structurellement sous-estimés : la date de construction, qui sert à dater la consommation, n'est connue qu'avec retard, et l'année ne sera stabilisée qu'après deux ou trois millésimes. Comparer 2024 aux années précédentes ferait apparaître une baisse artificielle. L'année entre donc dans le cumul consommé (qui ne peut qu'augmenter), mais pas dans le rythme.

## Indicateurs de trajectoire

Calculés pour chaque commune, EPCI, département, région et pour la France (`R/indicateurs.R`). Les territoires sont d'abord additionnés, puis les taux calculés : un taux départemental n'est pas une moyenne de taux communaux.

| Indicateur | Calcul |
|---|---|
| Rythme de référence | Consommation 2011-2020 / 10 |
| Rythme actuel | Consommation 2021-2023 / 3 |
| Évolution du rythme | Rythme actuel / rythme de référence - 1 |
| Enveloppe 2021-2030 | Consommation 2011-2020 × 50 % |
| Part de l'enveloppe consommée | Consommation 2021-2024 / enveloppe |
| Rythme requis | (Enveloppe - consommation 2021-2024) / 6 ans |

L'évolution n'est pas calculée quand le rythme de référence est inférieur à 0,1 ha/an (Paris, nombreuses petites communes) : un pourcentage sur une base quasi nulle ne veut rien dire. Ces territoires sont classés « Consommation quasi nulle » ou « Consommation nouvelle ».

Statuts retenus : baisse d'au moins 50 % ; baisse de moins de 50 % ; stable ou en hausse.

**L'enveloppe est un repère, pas une obligation.** La loi territorialise l'effort : les Sraddet répartissent l'objectif entre territoires, puis les Scot et PLU(i) le déclinent, et certains projets d'envergure nationale ou européenne sont décomptés à part. Appliquer -50 % partout permet de comparer les territoires entre eux, pas de dire si l'un d'eux respecte ses obligations.

Un EPCI qui s'étend sur deux départements est rattaché à celui où se trouvent le plus de ses communes.

## Indicateurs d'efficacité foncière

Sur 2011-2022, période couverte par les recensements du fichier :

| Indicateur | Calcul |
|---|---|
| m² d'habitat par ménage gagné | Consommation pour l'habitat 2011-2022 / gain de ménages, si le gain est positif |
| m² par ménage ou emploi gagné | Consommation totale 2011-2022 / (gain de ménages + gain d'emplois), si positif |

Les communes sont aussi classées selon l'évolution de leur population et de leurs ménages, pour mesurer la part de la consommation qui a lieu sans croissance démographique. Les types d'espaces suivent la grille de densité de l'INSEE dans les aires d'attraction des villes (urbain dense, urbain intermédiaire, rural périurbain, rural non périurbain), telle que fournie dans le fichier.

## Modèle de consommation attendue

Régression linéaire par moindres carrés (`R/modele.R`), une observation par commune de métropole ayant des habitants en 2011 et des emplois connus (34 727 communes) :

```text
consommation 2011-2022 (ha) = type d'espace
                            + type d'espace × centaines de ménages gagnés
                            + type d'espace × centaines d'emplois gagnés
                            + type d'espace × centaines de ménages perdus
                            + commune littorale + zone ABC + effet fixe département
```

Les gains et les pertes sont séparés parce qu'une commune qui perd des ménages ne « déconsomme » pas d'espace. Les interactions avec le type d'espace laissent à chaque type sa propre relation entre croissance et consommation. L'effet fixe département absorbe les écarts de pratiques et de documents d'urbanisme entre départements.

Le modèle explique 51 % de la variance (R² ajusté 0,513). La consommation attendue de chaque commune (bornée à zéro) est additionnée par EPCI et comparée à l'observée. Un ratio de 1,5 signifie qu'un EPCI a consommé 50 % de plus que des communes comparables, du même type d'espace, avec la même croissance et dans le même département.

Ce modèle est **descriptif** : il ne prend en compte ni le prix du foncier, ni les documents d'urbanisme, ni les grands projets, et ses résidus restent importants pour les petites communes. Le ratio est à lire à l'échelle des EPCI, et de préférence pour ceux dont la consommation attendue dépasse une vingtaine d'hectares.

## Contrôles

Sept contrôles bloquants (`R/controles.R`) arrêtent la chaîne avant toute écriture :

1. codes commune uniques et renseignés ;
2. département et EPCI renseignés ;
3. aucun flux annuel négatif ou manquant ;
4. somme des 14 flux annuels égale au cumul 2011-2025 fourni par le Cerema (à 1 m² près) ;
5. chaque année, total égal à la somme des six destinations (à 1 m² près) ;
6. consommation 2011-2024 inférieure à la surface communale ;
7. table longue des flux cohérente avec la table des communes.

Le rapport `data/processed/rapport_qualite.json` les reprend, avec des diagnostics : communes sans surface (9), communes d'outre-mer (112), communes sans emplois connus (11), communes sans aucune consommation (730), communes ayant consommé plus de 20 ha en une seule année (540), consommation nationale par année, qualité du modèle.

Les totaux nationaux sont cohérents avec les publications du Cerema : 15 119 ha pour 2024, et une part de l'habitat de 65 %.

## Limites

- **Fichiers fonciers.** Ils décrivent le cadastre fiscal : les équipements publics non soumis à la taxe foncière y sont mal couverts, et les infrastructures sont sans doute sous-estimées.
- **Datation.** La consommation est comptée au début de l'aménagement : une zone d'activité ouverte en une fois pèse entièrement sur une année.
- **Petits territoires.** Pour une commune, une seule opération peut faire varier le rythme de plusieurs centaines de pour cent. Les statuts communaux sont fournis, mais l'analyse s'appuie sur les EPCI et les départements.
- **Outre-mer.** Les quatre DROM présents (Guadeloupe, Martinique, Guyane, La Réunion) sont inclus dans les tables mais exclus du modèle et de la carte. Mayotte est absente du fichier.
- **Efficacité et période.** Les recensements disponibles s'arrêtent en 2022 : l'efficacité n'est mesurée que sur 2011-2022.
