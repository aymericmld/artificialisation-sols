# indicateurs.R
# Calcule les indicateurs de trajectoire et d'efficacité foncière,
# pour n'importe quel niveau : commune, EPCI, département, région, France.
# Lit   : la table « communes » produite par lecture.R
# Produit, en mémoire : une table d'indicateurs par territoire

suppressPackageStartupMessages(library(dplyr))

# Additionne les communes au niveau demandé (cles = colonnes de regroupement)
agreger <- function(communes, cles) {
  communes |>
    group_by(across(all_of(cles))) |>
    summarise(
      nb_communes = n(),
      surface_ha = sum(surface_ha, na.rm = TRUE),
      across(
        c(starts_with("conso_"), starts_with("population_"),
          starts_with("menages_"), starts_with("emplois_")),
        \(x) sum(x, na.rm = TRUE)
      ),
      .groups = "drop"
    )
}

# Trajectoire au regard de l'objectif de réduction de moitié
ajouter_trajectoire <- function(t) {
  n_ref <- length(CONFIG$annees_reference)
  n_rythme <- length(CONFIG$annees_rythme)
  annees_restantes <- CONFIG$fin_periode - max(CONFIG$annees_cumul)

  t |>
    mutate(
      rythme_reference_ha_an = conso_reference_ha / n_ref,
      rythme_actuel_ha_an = conso_rythme_ha / n_rythme,
      # Évolution non calculée sous 0,1 ha/an de référence (Paris, petites communes) :
      # un pourcentage sur une base quasi nulle n'a pas de sens
      evolution_rythme = if_else(
        rythme_reference_ha_an >= 0.1, rythme_actuel_ha_an / rythme_reference_ha_an - 1, NA_real_
      ),
      enveloppe_ha = conso_reference_ha * (1 - CONFIG$reduction_cible),
      part_enveloppe_consommee = if_else(enveloppe_ha > 0, conso_cumul_ha / enveloppe_ha, NA_real_),
      reste_enveloppe_ha = enveloppe_ha - conso_cumul_ha,
      rythme_requis_ha_an = pmax(reste_enveloppe_ha, 0) / annees_restantes,
      statut = classer_trajectoire(evolution_rythme, conso_reference_ha, conso_rythme_ha)
    )
}

classer_trajectoire <- function(evolution, reference, actuel) {
  case_when(
    is.na(evolution) & actuel == 0 ~ "Consommation quasi nulle",
    is.na(evolution) ~ "Consommation nouvelle",
    evolution <= -CONFIG$reduction_cible ~ "Baisse d'au moins 50 %",
    evolution < 0 ~ "Baisse de moins de 50 %",
    TRUE ~ "Stable ou en hausse"
  )
}

# Efficacité foncière sur 2011-2022 : surface consommée par ménage et par emploi accueillis
ajouter_efficacite <- function(t) {
  t |>
    mutate(
      gain_population = population_2022 - population_2011,
      gain_menages = menages_2022 - menages_2011,
      gain_emplois = emplois_2022 - emplois_2011,
      m2_habitat_par_menage = if_else(
        gain_menages > 0, conso_1122_habitat_ha * 1e4 / gain_menages, NA_real_
      ),
      m2_par_menage_ou_emploi = if_else(
        gain_menages + gain_emplois > 0,
        conso_1122_ha * 1e4 / (gain_menages + gain_emplois), NA_real_
      ),
      part_surface_consommee_1122 = if_else(surface_ha > 0, conso_1122_ha / surface_ha, NA_real_)
    )
}

indicateurs <- function(communes, cles) {
  agreger(communes, cles) |> ajouter_trajectoire() |> ajouter_efficacite()
}

# Série nationale annuelle avec les repères de l'objectif
serie_nationale <- function(flux) {
  par_annee <- flux |>
    group_by(annee, destination) |>
    summarise(conso_ha = sum(conso_ha), .groups = "drop")
  totaux <- par_annee |> group_by(annee) |> summarise(conso_ha = sum(conso_ha))
  ref <- mean(totaux$conso_ha[totaux$annee %in% CONFIG$annees_reference])
  totaux |>
    mutate(
      periode = case_when(
        annee %in% CONFIG$annees_reference ~ "Référence 2011-2020",
        annee %in% CONFIG$annees_rythme ~ "Période 2021-2030",
        TRUE ~ "Période 2021-2030 (année sous-estimée)"
      ),
      rythme_reference_ha_an = ref,
      rythme_cible_ha_an = ref * (1 - CONFIG$reduction_cible)
    ) |>
    left_join(
      par_annee |> tidyr::pivot_wider(names_from = destination, values_from = conso_ha,
                                      names_prefix = "conso_ha_"),
      by = "annee"
    )
}

# Consommation 2011-2022 selon que la commune a gagné ou perdu des habitants et des ménages
consommation_sans_croissance <- function(communes) {
  communes |>
    ajouter_efficacite() |>
    mutate(
      situation = case_when(
        gain_menages <= 0 ~ "Ménages en baisse ou stables",
        gain_population < 0 ~ "Population en baisse, ménages en hausse",
        TRUE ~ "Population et ménages en hausse"
      )
    ) |>
    group_by(situation) |>
    summarise(
      nb_communes = n(),
      conso_1122_ha = sum(conso_1122_ha),
      conso_1122_habitat_ha = sum(conso_1122_habitat_ha),
      .groups = "drop"
    ) |>
    mutate(part_conso = conso_1122_ha / sum(conso_1122_ha))
}

# Efficacité par type d'espace (grille de densité INSEE dans les aires d'attraction)
efficacite_par_densite <- function(communes) {
  ordre <- c("Urbain dense", "Urbain intermédiaire", "Rural périurbain", "Rural non périurbain")
  agreger(communes, "densite") |>
    ajouter_efficacite() |>
    mutate(
      part_conso_1122 = conso_1122_ha / sum(conso_1122_ha),
      part_gain_menages = gain_menages / sum(gain_menages),
      densite = factor(densite, levels = ordre)
    ) |>
    arrange(densite) |>
    select(densite, nb_communes, conso_1122_ha, part_conso_1122, gain_menages,
           part_gain_menages, m2_habitat_par_menage, m2_par_menage_ou_emploi)
}

# Un EPCI peut s'étendre sur deux départements : il est rattaché à celui
# qui compte le plus de ses communes
rattacher_epci <- function(communes) {
  principal <- communes |>
    count(code_epci, code_departement, departement, region) |>
    arrange(code_epci, desc(n)) |>
    distinct(code_epci, .keep_all = TRUE) |>
    select(-n)
  communes |>
    select(-code_departement, -departement, -region) |>
    left_join(principal, by = "code_epci")
}

