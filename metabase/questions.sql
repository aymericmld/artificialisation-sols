-- questions.sql
-- Les questions du tableau de bord Metabase, en SQL natif.
-- Chaque bloc correspond à une carte ; docs/METABASE.md indique sa visualisation.
-- Les filtres du tableau de bord passent par les variables Metabase {{...}} :
-- un bloc [[ ... ]] disparaît quand le filtre est vide.

-- 1. Chiffres clés (quatre cartes « Nombre » sur la même requête)
SELECT * FROM artif.v_chiffres_cles;

-- 2. Consommation annuelle, filtrable par région, département et intercommunalité
--    Visualisation : barres empilées, x = annee, y = conso_ha, série = destination
SELECT annee, destination, round(sum(conso_ha)::numeric, 1) AS conso_ha
FROM artif.v_flux_annuel
WHERE 1 = 1
  [[AND region = {{region}}]]
  [[AND departement = {{departement}}]]
  [[AND epci = {{epci}}]]
GROUP BY annee, destination
ORDER BY annee, destination;

-- 3. Carte des départements
--    Visualisation : carte de région personnalisée (GeoJSON des départements, clé « code »),
--    valeur = evolution_rythme_pct
SELECT code_departement, departement, evolution_rythme_pct, part_enveloppe_consommee_pct
FROM artif.v_trajectoire_departement
WHERE 1 = 1 [[AND region = {{region}}]];

-- 4. Intercommunalités selon leur trajectoire
--    Visualisation : barres horizontales, x = statut, y = nb_epci
SELECT statut, count(*) AS nb_epci
FROM artif.v_trajectoire_epci
WHERE 1 = 1
  [[AND region = {{region}}]]
  [[AND departement = {{departement}}]]
GROUP BY statut
ORDER BY nb_epci DESC;

-- 5. Tableau des intercommunalités
--    Visualisation : tableau, mise en forme conditionnelle sur evolution_rythme_pct
--    (bleu si négatif, rouge si positif) et sur part_enveloppe_consommee_pct (rouge au-delà de 100)
SELECT epci, departement, rythme_2011_2020_ha_an, rythme_2021_2023_ha_an,
       evolution_rythme_pct, consomme_2021_2024_ha, enveloppe_2021_2030_ha,
       part_enveloppe_consommee_pct, m2_habitat_par_menage_2011_2022,
       ratio_observe_attendu_2011_2022
FROM artif.v_trajectoire_epci
WHERE 1 = 1
  [[AND region = {{region}}]]
  [[AND departement = {{departement}}]]
ORDER BY part_enveloppe_consommee_pct DESC NULLS LAST;

-- 6. Consommation et croissance des ménages, par commune
--    Visualisation : nuage de points, x = gain_menages_2011_2022, y = conso_2011_2022_ha,
--    série = densite
SELECT commune, epci, densite, gain_menages_2011_2022, conso_2011_2022_ha
FROM artif.v_communes
WHERE conso_2011_2022_ha > 0
  [[AND departement = {{departement}}]]
  [[AND epci = {{epci}}]];

-- 7. Surface d'habitat par ménage supplémentaire, selon la densité
--    Visualisation : barres horizontales
SELECT densite, round(m2_habitat_par_menage) AS m2_habitat_par_menage,
       round(100 * part_conso_1122) AS part_consommation_pct,
       round(100 * part_gain_menages) AS part_gain_menages_pct
FROM artif.efficacite_densite;
