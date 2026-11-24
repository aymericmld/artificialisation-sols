// creer_tableau_de_bord.js
// Crée la connexion PostgreSQL, la carte des départements, les questions et le tableau de bord
// « Artificialisation des sols » via l'API de Metabase.
// À exécuter dans la console du navigateur, sur l'instance Metabase, une fois connecté en
// administrateur (Metabase 0.50 ou plus). Paramètres à adapter ci-dessous si besoin.

const CONFIG = {
  // Hôte : « postgis » avec docker-compose.yml (Metabase et PostgreSQL sur le même réseau Docker),
  // « localhost » si Metabase tourne hors Docker.
  base: { host: "postgis", port: 5432, dbname: "artificialisation", user: "postgres", password: "artif" },
  geojson: "https://raw.githubusercontent.com/aymericmld/artificialisation-sols/main/data/reference/departements.geojson",
  nomTableau: "Artificialisation des sols",
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

async function creer() {
  // 1. Base de données (réutilisée si elle existe déjà)
  const bases = (await api("GET", "/database")).data;
  let base = bases.find((b) => b.name === "Artificialisation");
  if (!base) {
    base = await api("POST", "/database", {
      engine: "postgres",
      name: "Artificialisation",
      details: {
        ...CONFIG.base, ssl: false,
        "schema-filters-type": "inclusion", "schema-filters-patterns": "artif",
      },
    });
  }
  // Attendre la synchronisation des vues
  let champs = {};
  for (let i = 0; i < 60; i++) {
    const meta = await api("GET", `/database/${base.id}/metadata?include_hidden=true`);
    const tables = Object.fromEntries(meta.tables.map((t) => [t.name, t]));
    const prets = ["v_flux_annuel", "v_trajectoire_epci", "v_trajectoire_departement", "epci"].every(
      (n) => tables[n] && tables[n].fields.length > 0
    );
    if (prets) {
      for (const t of meta.tables) for (const f of t.fields) champs[`${t.name}.${f.name}`] = f.id;
      break;
    }
    if (i === 0) await api("POST", `/database/${base.id}/sync_schema`);
    await pause(3000);
  }
  if (!champs["v_flux_annuel.region"]) throw new Error("Synchronisation des vues non terminée");

  // 2. Carte personnalisée des départements
  const reglages = await api("GET", "/setting/custom-geojson").catch(() => ({}));
  await api("PUT", "/setting/custom-geojson", {
    value: {
      ...(reglages || {}),
      departements: { name: "Départements", url: CONFIG.geojson, region_key: "code", region_name: "nom" },
    },
  });

  // 3. Collection
  const collection = await api("POST", "/collection", { name: CONFIG.nomTableau, color: "#2a78d6" });

  // Filtres de champ (listes déroulantes alimentées par Metabase)
  const filtre = (nom, libelle, champ) => ({
    id: uid(), name: nom, "display-name": libelle, type: "dimension",
    dimension: ["field", champs[champ], null], "widget-type": "string/=",
  });
  const question = (nom, sql, display, viz, tags = {}) =>
    api("POST", "/card", {
      name: nom, display, collection_id: collection.id, visualization_settings: viz,
      dataset_query: {
        type: "native", database: base.id,
        native: { query: sql, "template-tags": tags },
      },
    });

  // 4. Questions
  // Chiffres affichés en entier (pas de « 19,2k ») ; l'unité figure dans le titre
  const kpi = (nom, col, suffixe = "") =>
    question(nom, `SELECT ${col} FROM artif.v_chiffres_cles`, "scalar", {
      "scalar.compact_primary_number": false,
      ...(suffixe ? { column_settings: { [`["name","${col}"]`]: { suffix: suffixe } } } : {}),
    });

  const q = {};
  q.rythme = await kpi("Rythme 2021-2023 (ha/an)", "rythme_2021_2023_ha_an");
  q.evolution = await kpi("Évolution du rythme vs 2011-2020", "evolution_rythme_pct", " %");
  q.enveloppe = await kpi("Part de l'enveloppe 2021-2030 consommée (2021-2024)", "part_enveloppe_consommee_pct", " %");
  q.requis = await kpi("Rythme requis 2025-2030 (ha/an)", "rythme_requis_2025_2030_ha_an");

  q.serie = await question(
    "Consommation annuelle par destination (ha)",
    `SELECT annee::text AS annee, destination, round(sum(conso_ha)::numeric, 1) AS conso_ha
FROM artif.v_flux_annuel
WHERE {{region}} AND {{departement}} AND {{epci}}
GROUP BY annee, destination
ORDER BY annee, destination`,
    "bar",
    {
      "graph.dimensions": ["annee", "destination"], "graph.metrics": ["conso_ha"],
      "stackable.stack_type": "stacked", "graph.x_axis.title_text": "Année",
      "graph.y_axis.title_text": "Hectares",
    },
    {
      region: filtre("region", "Région", "v_flux_annuel.region"),
      departement: filtre("departement", "Département", "v_flux_annuel.departement"),
      epci: filtre("epci", "Intercommunalité", "v_flux_annuel.epci"),
    }
  );

  q.carte = await question(
    "Évolution du rythme par département (%)",
    `SELECT code_departement, departement, evolution_rythme_pct, part_enveloppe_consommee_pct
FROM artif.v_trajectoire_departement
WHERE {{region}}`,
    "map",
    {
      "map.type": "region", "map.region": "departements",
      "map.dimension": "code_departement", "map.metric": "evolution_rythme_pct",
    },
    { region: filtre("region", "Région", "v_trajectoire_departement.region") }
  );

  q.statut = await question(
    "Intercommunalités selon leur trajectoire",
    `SELECT statut, count(*) AS nb_epci
FROM artif.v_trajectoire_epci
WHERE statut IN ('Baisse d''au moins 50 %', 'Baisse de moins de 50 %', 'Stable ou en hausse')
  AND {{region}} AND {{departement}}
GROUP BY statut
ORDER BY statut`,
    "row",
    { "graph.dimensions": ["statut"], "graph.metrics": ["nb_epci"], "graph.show_values": true,
      "graph.x_axis.title_text": "", "graph.y_axis.title_text": "Intercommunalités" },
    {
      region: filtre("region", "Région", "v_trajectoire_epci.region"),
      departement: filtre("departement", "Département", "v_trajectoire_epci.departement"),
    }
  );

  q.tableau = await question(
    "Trajectoire des intercommunalités",
    `SELECT epci AS "Intercommunalité", departement AS "Département",
       rythme_2011_2020_ha_an AS "Rythme 2011-2020 (ha/an)",
       rythme_2021_2023_ha_an AS "Rythme 2021-2023 (ha/an)",
       evolution_rythme_pct AS "Évolution (%)",
       consomme_2021_2024_ha AS "Consommé 2021-2024 (ha)",
       part_enveloppe_consommee_pct AS "Enveloppe consommée (%)",
       m2_habitat_par_menage_2011_2022 AS "m² d'habitat par ménage gagné",
       ratio_observe_attendu_2011_2022 AS "Observé / attendu"
FROM artif.v_trajectoire_epci
WHERE {{region}} AND {{departement}} AND {{epci}}
ORDER BY part_enveloppe_consommee_pct DESC NULLS LAST`,
    "table",
    {
      "table.column_formatting": [
        { id: 0, columns: ["Évolution (%)"], type: "single", operator: ">=", value: 0,
          color: "#c23b3a", highlight_row: false },
        { id: 1, columns: ["Évolution (%)"], type: "single", operator: "<=", value: -50,
          color: "#2a78d6", highlight_row: false },
        { id: 2, columns: ["Enveloppe consommée (%)"], type: "single", operator: ">=", value: 100,
          color: "#c23b3a", highlight_row: false },
      ],
    },
    {
      region: filtre("region", "Région", "v_trajectoire_epci.region"),
      departement: filtre("departement", "Département", "v_trajectoire_epci.departement"),
      epci: filtre("epci", "Intercommunalité", "v_trajectoire_epci.epci"),
    }
  );

  q.nuage = await question(
    "Consommation 2011-2022 et ménages gagnés, par intercommunalité",
    `SELECT gain_menages AS "Ménages gagnés 2011-2022",
       round(conso_1122_ha::numeric, 1) AS "Consommation 2011-2022 (ha)",
       epci AS "Intercommunalité"
FROM artif.epci
WHERE {{region}} AND {{departement}}`,
    "scatter",
    {
      "graph.dimensions": ["Ménages gagnés 2011-2022"],
      "graph.metrics": ["Consommation 2011-2022 (ha)"],
    },
    {
      region: filtre("region", "Région", "epci.region"),
      departement: filtre("departement", "Département", "epci.departement"),
    }
  );

  q.densite = await question(
    "m² d'habitat par ménage gagné, selon la densité (2011-2022)",
    `SELECT densite AS "Type d'espace", round(m2_habitat_par_menage) AS "m² par ménage gagné"
FROM artif.efficacite_densite
ORDER BY m2_habitat_par_menage`,
    "row",
    { "graph.dimensions": ["Type d'espace"], "graph.metrics": ["m² par ménage gagné"], "graph.show_values": true,
      "graph.x_axis.title_text": "", "graph.y_axis.title_text": "m² par ménage gagné" }
  );

  // 5. Tableau de bord, grille de 24 colonnes
  const params = [
    { id: uid(), name: "Région", slug: "region", type: "string/=", sectionId: "string" },
    { id: uid(), name: "Département", slug: "departement", type: "string/=", sectionId: "string" },
    { id: uid(), name: "Intercommunalité", slug: "epci", type: "string/=", sectionId: "string" },
  ];
  const parSlug = Object.fromEntries(params.map((p) => [p.slug, p.id]));
  const lier = (carte, slugs) =>
    slugs.map((s) => ({ parameter_id: parSlug[s], card_id: carte.id, target: ["dimension", ["template-tag", s]] }));

  const tableau = await api("POST", "/dashboard", {
    name: CONFIG.nomTableau, collection_id: collection.id, parameters: params,
    description: "Consommation d'espaces naturels, agricoles et forestiers (Cerema, 2011-2025) au regard de l'objectif de réduction de moitié. Projet github.com/aymericmld/artificialisation-sols.",
  });

  let n = -1;
  const place = (carte, col, row, x, y, liens = []) =>
    ({ id: n--, card_id: carte.id, col, row, size_x: x, size_y: y, parameter_mappings: lier(carte, liens), visualization_settings: {} });
  const texte = (txt, col, row, x, y) => ({
    id: n--, card_id: null, col, row, size_x: x, size_y: y, parameter_mappings: [],
    visualization_settings: { virtual_card: { name: null, display: "text", visualization_settings: {}, dataset_query: {}, archived: false }, text: txt },
  });

  const cartes = [
    texte("## Où en est la trajectoire du « zéro artificialisation nette » ?\nRythme 2021-2023 comparé à 2011-2020. L'année 2024, sous-estimée par le Cerema, n'entre que dans le cumul consommé. Les chiffres clés portent sur la France entière.", 0, 0, 24, 3),
    place(q.rythme, 0, 3, 6, 3),
    place(q.evolution, 6, 3, 6, 3),
    place(q.enveloppe, 12, 3, 6, 3),
    place(q.requis, 18, 3, 6, 3),
    place(q.serie, 0, 6, 14, 7, ["region", "departement", "epci"]),
    place(q.carte, 14, 6, 10, 7, ["region"]),
    place(q.tableau, 0, 13, 16, 8, ["region", "departement", "epci"]),
    place(q.statut, 16, 13, 8, 8, ["region", "departement"]),
    place(q.nuage, 0, 21, 14, 7, ["region", "departement"]),
    place(q.densite, 14, 21, 10, 7),
  ];
  await api("PUT", `/dashboard/${tableau.id}`, { dashcards: cartes, parameters: params, width: "full" });

  // Nombres au format français (virgule décimale, espace pour les milliers)
  const formats = (await api("GET", "/setting/custom-formatting").catch(() => ({}))) || {};
  await api("PUT", "/setting/custom-formatting", {
    value: { ...formats, "type/Number": { ...(formats["type/Number"] || {}), number_separators: ", " } },
  });
  return { tableau: tableau.id, url: `${location.origin}/dashboard/${tableau.id}` };
}

creer();
