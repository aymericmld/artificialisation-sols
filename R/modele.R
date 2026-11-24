# modele.R
# Estime la consommation « attendue » de chaque commune compte tenu de sa croissance,
# puis compare consommation observée et attendue par EPCI.
# Lit   : la table « communes » (lecture.R) enrichie par ajouter_efficacite()
# Produit, en mémoire :
#   - coefficients : hectares consommés pour 100 ménages ou 100 emplois de plus, par type d'espace
#   - ecarts_epci  : consommation observée, attendue et ratio par EPCI
#
# Modèle linéaire, commune par commune, sur la France métropolitaine (2011-2022) :
#   conso = type d'espace
#         + type d'espace x ménages gagnés + type d'espace x emplois gagnés
#         + type d'espace x ménages perdus
#         + littoral + zone ABC + effet fixe département
# Les gains sont exprimés en centaines. Le modèle décrit une relation moyenne,
# il ne dit pas ce qu'une commune « aurait dû » consommer.

suppressPackageStartupMessages(library(dplyr))

preparer_modele <- function(communes) {
  communes |>
    filter(!outre_mer, population_2011 > 0, !is.na(gain_emplois)) |>
    mutate(
      densite = relevel(factor(densite), ref = "Urbain dense"),
      menages_gagnes = pmax(gain_menages, 0) / 100,
      menages_perdus = pmax(-gain_menages, 0) / 100,
      emplois_gagnes = pmax(gain_emplois, 0) / 100,
      code_departement = factor(code_departement),
      zone_abc = factor(zone_abc)
    )
}

estimer_modele <- function(donnees) {
  lm(
    conso_1122_ha ~ densite + densite:menages_gagnes + densite:emplois_gagnes +
      densite:menages_perdus + littoral + zone_abc + code_departement,
    data = donnees
  )
}

coefficients_modele <- function(modele) {
  co <- summary(modele)$coefficients
  co <- data.frame(terme = rownames(co), co, row.names = NULL, check.names = FALSE)
  names(co) <- c("terme", "estimation", "erreur_type", "t", "p_valeur")
  co |>
    filter(grepl(":(menages|emplois)_", terme) | terme %in% c("littoralTRUE")) |>
    mutate(
      type_espace = sub("^densite(.*):.*$", "\\1", terme),
      variable = case_when(
        grepl("menages_gagnes", terme) ~ "Ha pour 100 ménages de plus",
        grepl("emplois_gagnes", terme) ~ "Ha pour 100 emplois de plus",
        grepl("menages_perdus", terme) ~ "Ha pour 100 ménages de moins",
        TRUE ~ "Commune littorale (ha)"
      ),
      type_espace = if_else(terme == "littoralTRUE", "Toutes", type_espace)
    ) |>
    select(variable, type_espace, estimation, erreur_type, p_valeur)
}

ecarts_epci <- function(donnees, modele) {
  # Prédiction avec le département de chaque commune, puis rattachement de l'EPCI
  # à son département principal
  donnees |>
    mutate(conso_attendue_ha = pmax(predict(modele, newdata = donnees), 0),
           code_departement = as.character(code_departement)) |>
    rattacher_epci() |>
    group_by(code_epci, epci, code_departement, departement, region) |>
    summarise(
      nb_communes = n(),
      conso_1122_ha = sum(conso_1122_ha),
      conso_attendue_ha = sum(conso_attendue_ha),
      gain_menages = sum(gain_menages),
      gain_emplois = sum(gain_emplois),
      .groups = "drop"
    ) |>
    mutate(
      ratio_observe_attendu = if_else(conso_attendue_ha > 0, conso_1122_ha / conso_attendue_ha, NA_real_),
      ecart_ha = conso_1122_ha - conso_attendue_ha
    )
}

qualite_modele <- function(modele) {
  s <- summary(modele)
  list(
    observations = length(s$residuals),
    r2 = s$r.squared,
    r2_ajuste = s$adj.r.squared,
    erreur_residuelle_ha = s$sigma
  )
}
