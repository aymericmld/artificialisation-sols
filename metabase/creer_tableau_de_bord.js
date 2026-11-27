// creer_tableau_de_bord.js
// Crée le tableau de bord « Artificialisation des sols » via l'API de Metabase :
// connexion PostgreSQL, carte des départements, questions, tableau de bord et filtres.
// À exécuter dans la console du navigateur, sur l'instance Metabase, une fois connecté en
// administrateur (Metabase 0.50 ou plus). Si une collection du même nom existe, elle est archivée
// et recréée. Paramètres à adapter ci-dessous si besoin.

const CONFIG = {
  // Hôte : « postgis » avec docker-compose.yml (Metabase et PostgreSQL sur le même réseau Docker),
  // « localhost » si Metabase tourne hors Docker.
  base: { host: "postgis", port: 5432, dbname: "artificialisation", user: "postgres", password: "artif" },
  geojson: "https://raw.githubusercontent.com/aymericmld/artificialisation-sols/main/data/reference/departements.geojson",
  nomTableau: "Artificialisation des sols",
  couleurs: { reference: "#2a78d6", actuel: "#eb6834", objectif: "#1f8a4c", tendance: "#a3a29e" },
};

const api = async (methode, chemin, corps) => {
  const r = await fetch("/api" + chemin, {
    method: methode,
    headers: { "Content-Type": "application/json" },
    body: corps ? JSON.stringify(corps) : undefined,
  });
  const texte = await r.text();
  if (!r.ok) throw new Error(`${methode} ${chemin} : ${r.status} ${texte.slice(0, 300)}`);
  return texte ? JSON.parse(texte) : null;
};
const pause = (ms) => new Promise((ok) => setTimeout(ok, ms));
const uid = () => crypto.randomUUID();

// Ordre de la grille de densité de l'INSEE
const ordreDensite = (col) => `CASE ${col} WHEN 'Urbain dense' THEN 1 WHEN 'Urbain intermédiaire' THEN 2
  WHEN 'Rural périurbain' THEN 3 ELSE 4 END`;

// Mise en forme conditionnelle commune aux deux tableaux
const miseEnForme = () => ({
  "table.column_formatting": [
    { id: 0, columns: ["Évolution (%)"], type: "single", operator: ">=", value: 0, color: "#c23b3a", highlight_row: false },
    { id: 1, columns: ["Évolution (%)"], type: "single", operator: "<=", value: -50, color: "#2a78d6", highlight_row: false },
    { id: 2, columns: ["Enveloppe consommée (%)"], type: "single", operator: ">=", value: 100, color: "#c23b3a", highlight_row: false },
  ],
});

async function creer() {
  // 1. Base de données (réutilisée si elle existe déjà), puis synchronisation
  const bases = (await api("GET", "/database")).data;
  let base = bases.find((b) => b.name === "Artificialisation");
  if (!base) {
    base = await api("POST", "/database", {
      engine: "postgres", name: "Artificialisation",
      details: { ...CONFIG.base, ssl: false, "schema-filters-type": "inclusion", "schema-filters-patterns": "artif" },
    });
  }
  const champs = {};
  for (let i = 0; i < 60; i++) {
    const meta = await api("GET", `/database/${base.id}/metadata?include_hidden=true`);
    const tables = Object.fromEntries(meta.tables.map((t) => [t.name, t]));
    if (["v_flux_annuel", "v_trajectoire_epci", "departement", "commune"].every((n) => tables[n]?.fields.length)) {
      for (const t of meta.tables) for (const f of t.fields) champs[`${t.name}.${f.name}`] = f.id;
      break;
    }
    if (i === 0) await api("POST", `/database/${base.id}/sync_schema`);
    await pause(3000);
  }
  if (!champs["v_flux_annuel.region"]) throw new Error("Synchronisation des vues non terminée");

  // 2. Réglages : carte des départements, nombres au format français
  const geo = (await api("GET", "/setting/custom-geojson").catch(() => ({}))) || {};
  await api("PUT", "/setting/custom-geojson", {
    value: { ...geo, departements: { name: "Départements", url: CONFIG.geojson, region_key: "code", region_name: "nom" } },
  });
  const formats = (await api("GET", "/setting/custom-formatting").catch(() => ({}))) || {};
  await api("PUT", "/setting/custom-formatting", {
    value: { ...formats, "type/Number": { ...(formats["type/Number"] || {}), number_separators: ", " } },
  });

  // 3. Collection (l'ancienne version est archivée)
  const collections = await api("GET", "/collection");
  for (const c of collections.filter((c) => c.name === CONFIG.nomTableau && !c.archived)) {
    await api("PUT", `/collection/${c.id}`, { archived: true });
  }
  const collection = await api("POST", "/collection", { name: CONFIG.nomTableau, color: "#2a78d6" });

  // Filtres de champ : chaque question filtre sur les colonnes de sa propre table
  const libelles = { region: "Région", departement: "Département", epci: "Intercommunalité" };
  const TOUS = ["region", "departement", "epci"];
  const filtres = (table, slugs = TOUS) => Object.fromEntries(slugs.map((s) => [s, {
    id: uid(), name: s, "display-name": libelles[s], type: "dimension",
    dimension: ["field", champs[`${table}.${s}`], null], "widget-type": "string/=",
  }]));
  const where = (slugs = TOUS) => slugs.map((s) => `{{${s}}}`).join(" AND ");
  const question = (nom, description, sql, display, viz, tags = {}) =>
    api("POST", "/card", {
      name: nom, description, display, collection_id: collection.id, visualization_settings: viz,
      dataset_query: { type: "native", database: base.id, native: { query: sql, "template-tags": tags } },
    });

  // 4. Questions
  const q = {};
  const kpi = (nom, description, expression, suffixe = "") =>
    question(nom, description,
      `SELECT ${expression} AS valeur FROM artif.commune WHERE ${where()}`,
      "scalar",
      { "scalar.compact_primary_number": false, column_settings: { '["name","valeur"]': { suffix: suffixe } } },
      filtres("commune"));

  q.ref = await kpi("Rythme 2011-2020 (ha/an)",
    "Consommation annuelle moyenne de la décennie de référence de la loi.",
    "round(sum(conso_reference_ha) / 10)");
  q.objectif = await kpi("Objectif 2021-2030 (ha/an)",
    "Rythme annuel moyen à ne pas dépasser sur 2021-2030 : la moitié du rythme 2011-2020.",
    "round(sum(conso_reference_ha) / 20)");
  q.actuel = await kpi("Rythme 2021-2023 (ha/an)",
    "Consommation annuelle moyenne depuis la loi (2024, sous-estimée, est exclue).",
    "round(sum(conso_rythme_ha) / 3)");
  q.enveloppe = await kpi("Enveloppe 2021-2030 déjà consommée",
    "Consommation 2021-2024 rapportée à l'enveloppe de la décennie (moitié de la consommation 2011-2020). Borne basse : 2024 est sous-estimée.",
    "round(100 * sum(conso_cumul_ha) / nullif(sum(conso_reference_ha) / 2, 0))", " %");
  q.requis = await kpi("À ne pas dépasser en 2025-2030 (ha/an)",
    "Rythme annuel maximal sur 2025-2030 pour respecter l'enveloppe : ce qui en reste après 2021-2024, réparti sur six ans.",
    "round(greatest(sum(conso_reference_ha) / 2 - sum(conso_cumul_ha), 0) / 6)");

  q.trajectoire = await question(
    "Trajectoire depuis 2021 : consommation cumulée et objectif (ha)",
    "Hectares consommés depuis le 1er janvier 2021, à la fin de chaque année, comparés à la trajectoire de l'objectif (-50 %) et à la poursuite du rythme 2011-2020.",
    `WITH f AS (
  SELECT annee, sum(conso_ha) AS ha FROM artif.v_flux_annuel
  WHERE ${where()} GROUP BY annee
),
r AS (SELECT sum(ha) FILTER (WHERE annee BETWEEN 2011 AND 2020) / 10 AS rythme FROM f),
a AS (SELECT annee, sum(ha) OVER (ORDER BY annee) AS cumul FROM f WHERE annee >= 2021)
SELECT y.annee::text AS "Année", s.serie AS "Série", round(s.ha::numeric) AS "Hectares cumulés depuis 2021"
FROM generate_series(2021, 2030) AS y(annee)
CROSS JOIN r
CROSS JOIN LATERAL (VALUES
  ('Consommation observée', (SELECT cumul FROM a WHERE a.annee = y.annee)),
  ('Objectif de la loi (-50 %)', r.rythme * 0.5 * (y.annee - 2020)),
  ('Si le rythme 2011-2020 continuait', r.rythme * (y.annee - 2020))
) AS s(serie, ha)
WHERE s.ha IS NOT NULL
ORDER BY 1, 2`,
    "line",
    {
      "graph.dimensions": ["Année", "Série"], "graph.metrics": ["Hectares cumulés depuis 2021"],
      "graph.x_axis.title_text": "Fin d'année", "graph.y_axis.title_text": "Hectares cumulés depuis 2021",
      series_settings: {
        "Consommation observée": { color: CONFIG.couleurs.actuel, "line.marker_enabled": true },
        "Objectif de la loi (-50 %)": { color: CONFIG.couleurs.objectif, "line.style": "dashed" },
        "Si le rythme 2011-2020 continuait": { color: CONFIG.couleurs.tendance, "line.style": "dotted" },
      },
    },
    filtres("v_flux_annuel"));

  q.carte = await question(
    "Part de l'enveloppe 2021-2030 déjà consommée, par département (%)",
    "Consommation 2021-2024 rapportée à la moitié de la consommation 2011-2020. Au-delà de 100 %, le département a déjà dépassé son enveloppe repère.",
    `SELECT code_departement, departement, part_enveloppe_consommee_pct AS "Enveloppe consommée (%)"
FROM artif.v_trajectoire_departement
WHERE {{region}}`,
    "map",
    { "map.type": "region", "map.region": "departements", "map.dimension": "code_departement",
      "map.metric": "Enveloppe consommée (%)" },
    filtres("v_trajectoire_departement", ["region"]));

  q.departements = await question(
    "Trajectoire par département",
    "Cliquer sur un département pour filtrer le tableau de bord, puis sur une intercommunalité.",
    `SELECT departement AS "Département", region AS "Région",
       round(rythme_reference_ha_an) AS "2011-2020 (ha/an)",
       round(rythme_reference_ha_an / 2) AS "Objectif (ha/an)",
       round(rythme_actuel_ha_an) AS "2021-2023 (ha/an)",
       round(100 * evolution_rythme) AS "Évolution (%)",
       round(100 * part_enveloppe_consommee) AS "Enveloppe consommée (%)",
       round(rythme_requis_ha_an) AS "À tenir 2025-2030 (ha/an)"
FROM artif.departement
WHERE {{region}}
ORDER BY part_enveloppe_consommee DESC NULLS LAST`,
    "table", miseEnForme(),
    filtres("departement", ["region"]));

  q.epci = await question(
    "Trajectoire par intercommunalité",
    "Cliquer sur une intercommunalité pour filtrer les graphiques.",
    `SELECT epci AS "Intercommunalité", departement AS "Département",
       rythme_2011_2020_ha_an AS "2011-2020 (ha/an)",
       round(rythme_2011_2020_ha_an / 2, 1) AS "Objectif (ha/an)",
       rythme_2021_2023_ha_an AS "2021-2023 (ha/an)",
       evolution_rythme_pct AS "Évolution (%)",
       part_enveloppe_consommee_pct AS "Enveloppe consommée (%)",
       statut AS "Trajectoire"
FROM artif.v_trajectoire_epci
WHERE ${where()}
ORDER BY part_enveloppe_consommee_pct DESC NULLS LAST`,
    "table", miseEnForme(),
    filtres("v_trajectoire_epci"));

  q.destinations = await question(
    "Rythme annuel par usage : avant et depuis la loi (ha/an)",
    "Consommation annuelle moyenne par destination, 2011-2020 et 2021-2023. Entre parenthèses : l'évolution.",
    `WITH f AS (
  SELECT destination,
         sum(conso_ha) FILTER (WHERE annee BETWEEN 2011 AND 2020) / 10 AS ref,
         sum(conso_ha) FILTER (WHERE annee BETWEEN 2021 AND 2023) / 3 AS actuel
  FROM artif.v_flux_annuel
  WHERE ${where()}
  GROUP BY destination
)
SELECT destination || CASE WHEN ref > 0
         THEN ' (' || CASE WHEN round(100 * (actuel / ref - 1)) > 0 THEN '+' ELSE '' END
                   || (round(100 * (actuel / ref - 1)) + 0) || ' %)'
         ELSE '' END AS "Usage",
       p.periode AS "Période", round(p.ha::numeric) AS "Hectares par an"
FROM f CROSS JOIN LATERAL (VALUES ('2011-2020', ref), ('2021-2023', actuel)) AS p(periode, ha)
ORDER BY f.ref DESC, p.periode`,
    "bar",
    {
      "graph.dimensions": ["Usage", "Période"], "graph.metrics": ["Hectares par an"],
      "graph.show_values": true, "graph.label_value_formatting": "full",
      "graph.x_axis.title_text": "", "graph.y_axis.title_text": "Hectares par an",
      series_settings: { "2011-2020": { color: CONFIG.couleurs.reference }, "2021-2023": { color: CONFIG.couleurs.actuel } },
    },
    filtres("v_flux_annuel"));

  q.serie = await question(
    "Consommation annuelle par usage (ha)",
    "Hectares consommés chaque année. 2024 est sous-estimée : le Cerema attend sa stabilisation dans 2 à 3 millésimes.",
    `SELECT annee::text AS "Année", destination AS "Usage", round(sum(conso_ha)::numeric, 1) AS "Hectares"
FROM artif.v_flux_annuel
WHERE ${where()}
GROUP BY annee, destination
ORDER BY annee, destination`,
    "bar",
    { "graph.dimensions": ["Année", "Usage"], "graph.metrics": ["Hectares"], "stackable.stack_type": "stacked",
      "graph.x_axis.title_text": "", "graph.y_axis.title_text": "Hectares" },
    filtres("v_flux_annuel"));

  q.repartition = await question(
    "Nouveaux ménages et terres consommées pour l'habitat, par type d'espace (2011-2022, %)",
    "Pour chaque type d'espace : sa part des ménages supplémentaires et sa part des terres consommées pour l'habitat.",
    `WITH t AS (
  SELECT densite, sum(gain_menages) AS menages, sum(conso_1122_habitat_ha) AS habitat
  FROM artif.commune
  WHERE densite IS NOT NULL AND ${where()}
  GROUP BY densite
),
x AS (
  SELECT densite,
         100 * greatest(menages, 0) / nullif(sum(greatest(menages, 0)) OVER (), 0) AS p_men,
         100 * habitat / nullif(sum(habitat) OVER (), 0) AS p_hab
  FROM t
)
SELECT x.densite AS "Type d'espace", v.serie AS "Part", round(v.pct::numeric) AS "%"
FROM x CROSS JOIN LATERAL (VALUES ('Part des ménages supplémentaires', x.p_men),
                                  ('Part des terres consommées pour l''habitat', x.p_hab)) AS v(serie, pct)
ORDER BY ${ordreDensite("x.densite")}, v.serie DESC`,
    "bar",
    {
      "graph.dimensions": ["Type d'espace", "Part"], "graph.metrics": ["%"], "graph.show_values": true,
      "graph.x_axis.title_text": "", "graph.y_axis.title_text": "%",
      series_settings: {
        "Part des ménages supplémentaires": { color: CONFIG.couleurs.reference },
        "Part des terres consommées pour l'habitat": { color: CONFIG.couleurs.actuel },
      },
    },
    filtres("commune"));

  q.surface = await question(
    "Terres consommées pour loger un ménage de plus (m², 2011-2022)",
    "Hectares consommés pour l'habitat entre 2011 et 2022, divisés par le nombre de ménages supplémentaires, convertis en m². Non calculé si le nombre de ménages n'a pas augmenté.",
    `SELECT densite AS "Type d'espace",
       CASE WHEN sum(gain_menages) > 0
            THEN round(sum(conso_1122_habitat_ha) * 10000 / sum(gain_menages)) END AS "m² par ménage supplémentaire"
FROM artif.commune
WHERE densite IS NOT NULL AND ${where()}
GROUP BY densite
ORDER BY ${ordreDensite("densite")}`,
    "row",
    { "graph.dimensions": ["Type d'espace"], "graph.metrics": ["m² par ménage supplémentaire"],
      "graph.show_values": true, "graph.x_axis.title_text": "", "graph.y_axis.title_text": "m² par ménage supplémentaire",
      series_settings: { "m² par ménage supplémentaire": { color: CONFIG.couleurs.reference } } },
    filtres("commune"));

  // 5. Tableau de bord, grille de 24 colonnes
  const params = TOUS.map((slug) => ({ id: uid(), name: libelles[slug], slug, type: "string/=", sectionId: "string" }));
  const p = Object.fromEntries(params.map((x) => [x.slug, x.id]));
  const tableau = await api("POST", "/dashboard", {
    name: CONFIG.nomTableau, collection_id: collection.id, parameters: params,
    description: "Consommation d'espaces naturels, agricoles et forestiers (Cerema, millésime 2011-2025) au regard de l'objectif de la loi Climat et résilience. Projet github.com/aymericmld/artificialisation-sols.",
  });

  let n = -1;
  const place = (carte, col, row, x, y, liens = TOUS, viz = {}) => ({
    id: n--, card_id: carte.id, col, row, size_x: x, size_y: y, visualization_settings: viz,
    parameter_mappings: liens.map((s) => ({ parameter_id: p[s], card_id: carte.id, target: ["dimension", ["template-tag", s]] })),
  });
  const texte = (txt, col, row, x, y) => ({
    id: n--, card_id: null, col, row, size_x: x, size_y: y, parameter_mappings: [],
    visualization_settings: { virtual_card: { name: null, display: "text", visualization_settings: {}, dataset_query: {}, archived: false }, text: txt },
  });
  // Clic sur une ligne : renseigne le filtre du tableau de bord
  const filtrerAuClic = (colonne, slug) => ({
    click_behavior: {
      type: "crossfilter",
      parameterMapping: { [p[slug]]: { id: p[slug], source: { type: "column", id: colonne, name: colonne }, target: { type: "parameter", id: p[slug] } } },
    },
  });

  const dashcards = [
    texte(`# Artificialisation des sols : où en est l'objectif de la loi ?
Consommation d'espaces naturels, agricoles et forestiers par les nouvelles constructions et infrastructures, d'après les données officielles du Cerema (2011-2025). Les filtres en haut de page s'appliquent à toutes les cartes.`, 0, 0, 24, 3),
    texte(`## L'objectif politique
**La loi Climat et résilience du 22 août 2021** impose de **diviser par deux la consommation d'espaces entre 2021 et 2031** par rapport à 2011-2021, puis d'atteindre le **« zéro artificialisation nette » (ZAN) en 2050** : chaque hectare artificialisé devra alors être compensé par un hectare renaturé.
L'effort est réparti entre régions par les Sraddet, puis décliné dans les Scot et les PLU(i). Ici, chaque territoire reçoit le même repère : **une enveloppe 2021-2030 égale à la moitié de sa consommation 2011-2020**. Le dispositif fait l'objet de débats et de propositions d'assouplissement au Parlement.

Chiffres clés en **hectares par an**, sauf l'enveloppe utilisée (consommation 2021-2024 rapportée à l'enveloppe 2021-2030). L'icône ⓘ d'une carte donne sa définition.`, 0, 3, 24, 5),
    place(q.ref, 0, 8, 5, 3, TOUS, { "card.title": "Rythme 2011-2020" }),
    place(q.objectif, 5, 8, 4, 3, TOUS, { "card.title": "Objectif" }),
    place(q.actuel, 9, 8, 5, 3, TOUS, { "card.title": "Rythme 2021-2023" }),
    place(q.enveloppe, 14, 8, 5, 3, TOUS, { "card.title": "Enveloppe utilisée" }),
    place(q.requis, 19, 8, 5, 3, TOUS, { "card.title": "Rythme à tenir" }),
    place(q.trajectoire, 0, 11, 14, 9),
    place(q.carte, 14, 11, 10, 9, ["region"], { "card.title": "Enveloppe 2021-2030 déjà consommée (%)" }),
    texte(`## Par territoire
Cliquer sur un **département** pour afficher ses intercommunalités, puis sur une **intercommunalité** pour filtrer tous les graphiques. En rouge : consommation en hausse depuis 2021, ou enveloppe repère déjà dépassée.`, 0, 20, 24, 3),
    place(q.departements, 0, 23, 24, 8, ["region"], filtrerAuClic("Département", "departement")),
    place(q.epci, 0, 31, 24, 8, TOUS, filtrerAuClic("Intercommunalité", "epci")),
    texte(`## Par usage
L'habitat représente les deux tiers de la consommation. Comparer le rythme de chaque usage avant et depuis la loi montre où la baisse a lieu.`, 0, 39, 24, 2),
    place(q.destinations, 0, 41, 12, 8),
    place(q.serie, 12, 41, 12, 8),
    texte(`## Où s'installent les nouveaux ménages, et à quel coût en terres ?
Entre 2011 et 2022, on rapporte les terres consommées pour l'habitat au nombre de **ménages supplémentaires** (recensements de l'INSEE). En France, l'**urbain dense** a accueilli 35 % des nouveaux ménages pour 4 % des terres consommées pour l'habitat, soit **66 m² par ménage** ; le **rural non périurbain** en a accueilli 8 % pour 31 % de ces terres, soit **2 086 m² par ménage**.`, 0, 49, 24, 4),
    place(q.repartition, 0, 53, 14, 8, TOUS, { "card.title": "Part des nouveaux ménages et des terres consommées pour l'habitat (%)" }),
    place(q.surface, 14, 53, 10, 8, TOUS, { "card.title": "Terres consommées par ménage en plus (m²)" }),
    texte(`Source : Cerema, consommation d'espaces NAF 2011-2025 (Fichiers fonciers) ; INSEE, recensements 2011 et 2022. L'année 2024 est sous-estimée et n'entre que dans le cumul consommé. Méthode et code : [github.com/aymericmld/artificialisation-sols](https://github.com/aymericmld/artificialisation-sols).`, 0, 61, 24, 2),
  ];
  await api("PUT", `/dashboard/${tableau.id}`, { dashcards, parameters: params, width: "full" });
  return { tableau: tableau.id, url: `${location.origin}/dashboard/${tableau.id}`,
           cartes: Object.fromEntries(Object.entries(q).map(([k, v]) => [k, v.id])) };
}

creer();
