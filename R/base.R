# base.R
# Charge les résultats dans PostgreSQL pour le tableau de bord Metabase.
# Lit   : les tables calculées en mémoire, sql/01_vues_metabase.sql
# Produit : schéma « artif » (par défaut) avec les tables et les vues lues par Metabase
#
# Pilote : RPostgres s'il est installé, sinon RPostgreSQL.

suppressPackageStartupMessages(library(DBI))

connecter <- function(cfg = CONFIG$pg) {
  pilote <- if (requireNamespace("RPostgres", quietly = TRUE)) {
    RPostgres::Postgres()
  } else if (requireNamespace("RPostgreSQL", quietly = TRUE)) {
    RPostgreSQL::PostgreSQL()
  } else {
    stop("Installer RPostgres (ou RPostgreSQL) pour l'étape « base ».")
  }
  dbConnect(pilote, host = cfg$host, port = cfg$port, dbname = cfg$dbname,
            user = cfg$user, password = cfg$password)
}

executer_sql <- function(con, chemin, schema) {
  sql <- paste(readLines(chemin, encoding = "UTF-8"), collapse = "\n")
  sql <- gsub("{schema}", schema, sql, fixed = TRUE)
  # Découpe sur les points-virgules en fin de ligne (pas de fonction plpgsql ici)
  for (requete in strsplit(sql, ";\\s*\n")[[1]]) {
    requete <- trimws(gsub("--[^\n]*", "", requete))
    if (nzchar(requete)) dbExecute(con, requete)
  }
}

charger_base <- function(res) {
  schema <- CONFIG$pg$schema
  con <- connecter()
  on.exit(dbDisconnect(con))

  dbExecute(con, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
  dbExecute(con, sprintf("CREATE SCHEMA %s", schema))
  # Écriture par le search_path : fonctionne avec RPostgres comme avec RPostgreSQL
  dbExecute(con, sprintf("SET search_path TO %s, public", schema))

  tables <- list(
    commune = res$communes,
    flux_annuel = res$flux,
    epci = res$epci,
    departement = res$departements,
    region = res$regions,
    serie_nationale = res$serie,
    efficacite_densite = transform(res$densite, densite = as.character(densite)),
    modele_ecarts_epci = res$ecarts
  )
  for (nom in names(tables)) {
    dbWriteTable(con, nom, as.data.frame(tables[[nom]]), overwrite = TRUE, row.names = FALSE)
    message("  ", schema, ".", nom, " (", nrow(tables[[nom]]), " lignes)")
  }
  executer_sql(con, "sql/01_vues_metabase.sql", schema)
  message("  vues Metabase créées")
}
