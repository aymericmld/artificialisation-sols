# lecture.R
# Lit le fichier communal du Cerema et le met au format du projet.
# Lit   : data/raw/conso-com.csv (une ligne par commune, COG 2025)
# Produit, en mémoire :
#   - communes : identifiants, zonages, recensements et cumuls de consommation (ha)
#   - flux     : consommation annuelle par commune, année et destination (ha), format long

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
})

lire_conso <- function(chemin = CONFIG$fichier_conso) {
  if (!file.exists(chemin)) {
    stop("Fichier introuvable : ", chemin, ". Voir docs/DONNEES.md pour le télécharger.")
  }
  brut <- read_csv(chemin, col_types = cols(.default = col_character()), progress = FALSE)
  colonnes_num <- grep("^(naf|art)[0-9]|^(pop|men|emp)[0-9]|^surfcom", names(brut), value = TRUE)
  brut |> mutate(across(all_of(colonnes_num), as.numeric))
}

# Table des communes : une ligne par commune, surfaces converties en hectares
preparer_communes <- function(brut) {
  ha <- function(x) x / CONFIG$m2_par_ha
  somme_flux <- function(annees, destination = "total") {
    cols <- vapply(annees, col_flux, character(1), destination = destination)
    rowSums(as.matrix(brut[, cols]))
  }

  brut |>
    transmute(
      code_commune = idcom,
      commune = idcomtxt,
      code_region = idreg, region = idregtxt,
      code_departement = iddep, departement = iddeptxt,
      code_epci = epci25, epci = epci25txt,
      scot = na_if(scot, ""),
      categorie_aav = cateaav2020,
      densite = libdens_aav,
      littoral = littoral == "C",
      zone_abc = abc,
      outre_mer = iddep %in% CONFIG$dom,
      surface_ha = ha(surfcom2025),

      # Consommation d'ENAF (ha)
      conso_reference_ha = ha(somme_flux(CONFIG$annees_reference)),
      conso_rythme_ha = ha(somme_flux(CONFIG$annees_rythme)),
      conso_cumul_ha = ha(somme_flux(CONFIG$annees_cumul)),
      conso_reference_habitat_ha = ha(somme_flux(CONFIG$annees_reference, "hab")),
      conso_cumul_habitat_ha = ha(somme_flux(CONFIG$annees_cumul, "hab")),
      conso_reference_activite_ha = ha(somme_flux(CONFIG$annees_reference, "act")),
      conso_cumul_activite_ha = ha(somme_flux(CONFIG$annees_cumul, "act")),

      # Période des recensements (2011-2022) : flux 2011 à 2021 inclus
      conso_1122_ha = ha(naf11art22),
      conso_1122_habitat_ha = ha(art11hab22),

      population_2011 = pop11, population_2022 = pop22,
      menages_2011 = men11, menages_2022 = men22,
      emplois_2011 = emp11, emplois_2022 = emp22
    )
}

# Flux annuels au format long : commune x année x destination
preparer_flux <- function(brut) {
  grille <- expand_grid(annee = CONFIG$annees, destination = names(DESTINATIONS))
  grille$colonne <- mapply(col_flux, grille$annee, grille$destination)

  brut |>
    select(code_commune = idcom, all_of(grille$colonne)) |>
    pivot_longer(-code_commune, names_to = "colonne", values_to = "m2") |>
    inner_join(grille, by = "colonne") |>
    transmute(
      code_commune, annee,
      destination = unname(DESTINATIONS[destination]),
      conso_ha = m2 / CONFIG$m2_par_ha
    )
}
