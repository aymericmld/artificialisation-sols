-- 01_vues_metabase.sql
-- Vues lues par le tableau de bord Metabase (voir docs/METABASE.md).
-- Lit   : les tables écrites par R/base.R dans le schéma {schema}
-- Produit : des vues prêtes à filtrer par région, département et intercommunalité.
-- {schema} est remplacé par R/base.R (par défaut : artif).

CREATE INDEX ON {schema}.flux_annuel (code_commune);
CREATE INDEX ON {schema}.commune (code_commune);
CREATE INDEX ON {schema}.commune (code_epci);

-- Chiffres clés nationaux (une ligne)
CREATE VIEW {schema}.v_chiffres_cles AS
SELECT
    round(sum(conso_reference_ha) / 10)                             AS rythme_2011_2020_ha_an,
    round(sum(conso_rythme_ha) / 3)                                 AS rythme_2021_2023_ha_an,
    round(100 * ((sum(conso_rythme_ha) / 3) / (sum(conso_reference_ha) / 10) - 1)) AS evolution_rythme_pct,
    round(sum(conso_reference_ha) / 2)                              AS enveloppe_2021_2030_ha,
    round(sum(conso_cumul_ha))                                      AS consomme_2021_2024_ha,
    round(100 * sum(conso_cumul_ha) / (sum(conso_reference_ha) / 2)) AS part_enveloppe_consommee_pct,
    round((sum(conso_reference_ha) / 2 - sum(conso_cumul_ha)) / 6)  AS rythme_requis_2025_2030_ha_an
FROM {schema}.commune;

-- Consommation annuelle par destination, avec les clés géographiques pour filtrer
CREATE VIEW {schema}.v_flux_annuel AS
SELECT
    f.annee,
    make_date(f.annee, 1, 1)  AS date_annee,
    f.destination,
    f.conso_ha,
    c.code_commune, c.commune,
    c.code_epci, c.epci,
    c.code_departement, c.departement,
    c.region,
    c.densite,
    CASE WHEN f.annee <= 2020 THEN 'Référence 2011-2020'
         WHEN f.annee <= 2023 THEN '2021-2023'
         ELSE '2024 (sous-estimée)' END AS periode
FROM {schema}.flux_annuel f
JOIN {schema}.commune c USING (code_commune);

-- Trajectoire par intercommunalité
CREATE VIEW {schema}.v_trajectoire_epci AS
SELECT
    e.code_epci, e.epci, e.code_departement, e.departement, e.region,
    e.nb_communes,
    round(e.rythme_reference_ha_an::numeric, 1)            AS rythme_2011_2020_ha_an,
    round(e.rythme_actuel_ha_an::numeric, 1)               AS rythme_2021_2023_ha_an,
    round(100 * e.evolution_rythme::numeric)               AS evolution_rythme_pct,
    round(e.enveloppe_ha::numeric, 1)                      AS enveloppe_2021_2030_ha,
    round(e.conso_cumul_ha::numeric, 1)                    AS consomme_2021_2024_ha,
    round(100 * e.part_enveloppe_consommee::numeric)       AS part_enveloppe_consommee_pct,
    e.statut,
    round(e.m2_habitat_par_menage::numeric)                AS m2_habitat_par_menage_2011_2022,
    round(m.ratio_observe_attendu::numeric, 2)             AS ratio_observe_attendu_2011_2022
FROM {schema}.epci e
LEFT JOIN {schema}.modele_ecarts_epci m USING (code_epci);

-- Trajectoire par département (carte : code_departement correspond à la propriété « code » du GeoJSON)
CREATE VIEW {schema}.v_trajectoire_departement AS
SELECT
    code_departement, departement, region,
    round(rythme_reference_ha_an::numeric)          AS rythme_2011_2020_ha_an,
    round(rythme_actuel_ha_an::numeric)             AS rythme_2021_2023_ha_an,
    round(100 * evolution_rythme::numeric)          AS evolution_rythme_pct,
    round(100 * part_enveloppe_consommee::numeric)  AS part_enveloppe_consommee_pct,
    statut,
    round(m2_habitat_par_menage::numeric)           AS m2_habitat_par_menage_2011_2022
FROM {schema}.departement;

-- Communes : trajectoire et croissance, pour le détail d'une intercommunalité
CREATE VIEW {schema}.v_communes AS
SELECT
    code_commune, commune, code_epci, epci, code_departement, departement, region, densite,
    round(conso_reference_ha::numeric, 2)   AS conso_2011_2020_ha,
    round(conso_cumul_ha::numeric, 2)       AS conso_2021_2024_ha,
    round(100 * evolution_rythme::numeric)  AS evolution_rythme_pct,
    statut,
    gain_menages AS gain_menages_2011_2022,
    gain_population AS gain_population_2011_2022,
    round(conso_1122_ha::numeric, 2)        AS conso_2011_2022_ha,
    (gain_menages <= 0 AND conso_1122_ha > 0) AS consomme_sans_gain_de_menages
FROM {schema}.commune;
