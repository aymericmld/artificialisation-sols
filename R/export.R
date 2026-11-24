# export.R
# Écrit les résultats versionnés dans data/processed/.
# Lit   : les tables calculées par indicateurs.R et modele.R, le rapport de controles.R
# Produit : fichiers CSV (séparateur virgule, UTF-8) et rapport_qualite.json

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(jsonlite)
})

arrondir <- function(t, n = 3) mutate(t, across(where(is.double), \(x) round(x, n)))

ecrire <- function(t, nom) {
  chemin <- file.path(CONFIG$dossier_sorties, nom)
  write_csv(arrondir(t), chemin, na = "")
  message("  ", chemin, " (", nrow(t), " lignes)")
  invisible(chemin)
}

exporter <- function(res) {
  dir.create(CONFIG$dossier_sorties, showWarnings = FALSE, recursive = TRUE)

  cols_commune <- c(
    "code_commune", "commune", "code_epci", "epci", "code_departement", "departement",
    "code_region", "region", "densite", "categorie_aav", "littoral", "zone_abc", "surface_ha",
    "conso_reference_ha", "conso_rythme_ha", "conso_cumul_ha",
    "rythme_reference_ha_an", "rythme_actuel_ha_an", "evolution_rythme",
    "enveloppe_ha", "part_enveloppe_consommee", "statut",
    "conso_1122_ha", "conso_1122_habitat_ha", "gain_population", "gain_menages",
    "gain_emplois", "m2_habitat_par_menage"
  )

  ecrire(res$nationale, "synthese_nationale.csv")
  ecrire(res$serie, "serie_nationale.csv")
  ecrire(res$regions, "trajectoire_regions.csv")
  ecrire(res$departements, "trajectoire_departements.csv")
  ecrire(res$epci, "trajectoire_epci.csv")
  ecrire(select(res$communes, all_of(cols_commune)), "indicateurs_communes.csv")
  ecrire(res$densite, "efficacite_densite.csv")
  ecrire(res$sans_croissance, "consommation_selon_croissance.csv")
  ecrire(res$coefficients, "modele_coefficients.csv")
  ecrire(res$ecarts, "modele_ecarts_epci.csv")

  rapport <- res$rapport
  rapport$modele <- res$qualite_modele
  chemin <- file.path(CONFIG$dossier_sorties, "rapport_qualite.json")
  write_json(rapport, chemin, auto_unbox = TRUE, pretty = TRUE, digits = 4)
  message("  ", chemin)
}
