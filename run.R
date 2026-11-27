#!/usr/bin/env Rscript
# run.R
# Point d'entrée de la chaîne. Usage :
#   Rscript run.R resultats  lecture, contrôles, indicateurs, modèle, exports CSV
#   Rscript run.R base       idem, puis chargement dans PostgreSQL pour Metabase
# Les graphiques sont produits par Metabase (voir docs/METABASE.md).
# Le fichier source est lu dans data/raw/conso-com.csv (voir docs/DONNEES.md).

invisible(Sys.setlocale("LC_ALL", "C.UTF-8"))
for (f in c("config", "lecture", "controles", "indicateurs", "modele", "export", "base")) {
  source(file.path("R", paste0(f, ".R")), encoding = "UTF-8")
}

calculer <- function() {
  message("Lecture de ", CONFIG$fichier_conso)
  brut <- lire_conso()
  communes <- preparer_communes(brut) |> ajouter_trajectoire() |> ajouter_efficacite()
  flux <- preparer_flux(brut)

  message("Contrôles")
  rapport <- controler(brut, communes, flux)
  verifier(rapport)

  message("Indicateurs")
  geo_epci <- c("code_epci", "epci", "code_departement", "departement", "region")
  donnees_modele <- preparer_modele(communes)
  modele <- estimer_modele(donnees_modele)

  list(
    communes = communes,
    flux = flux,
    nationale = indicateurs(dplyr::mutate(communes, territoire = "France"), "territoire"),
    serie = serie_nationale(flux),
    regions = indicateurs(communes, c("code_region", "region")),
    departements = indicateurs(communes, c("code_departement", "departement", "region")),
    epci = indicateurs(rattacher_epci(communes), geo_epci),
    densite = efficacite_par_densite(communes),
    sans_croissance = consommation_sans_croissance(communes),
    coefficients = coefficients_modele(modele),
    ecarts = ecarts_epci(donnees_modele, modele),
    qualite_modele = qualite_modele(modele),
    rapport = rapport
  )
}

main <- function(etape) {
  etapes <- c("resultats", "base")
  if (!etape %in% etapes) stop("Étape inconnue : ", etape, ". Choix : ", paste(etapes, collapse = ", "))
  res <- calculer()
  message("Exports")
  exporter(res)
  if (etape == "base") {
    message("Chargement PostgreSQL")
    charger_base(res)
  }
  message("Terminé.")
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  main(if (length(args) == 0) "resultats" else args[1])
}
