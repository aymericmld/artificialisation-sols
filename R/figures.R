# figures.R
# Graphiques du README, au format PNG.
# Lit   : les tables calculées (serie, departements, densite, epci)
#         et data/reference/departements.geojson (contours simplifiés)
# Produit : docs/images/*.png

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(sf)
  library(scales)
})

COULEURS <- list(
  reference = "#2a78d6", actuel = "#eb6834",
  texte = "#0b0b0b", texte_2 = "#52514e", grille = "#e4e3df", fond = "#fcfcfb"
)

theme_projet <- function() {
  theme_minimal(base_size = 12, base_family = "DejaVu Sans") +
    theme(
      plot.background = element_rect(fill = COULEURS$fond, colour = NA),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_line(colour = COULEURS$grille, linewidth = 0.4),
      axis.text = element_text(colour = COULEURS$texte_2),
      axis.title = element_text(colour = COULEURS$texte_2, size = 10),
      plot.title = element_text(colour = COULEURS$texte, face = "bold", size = 14),
      plot.subtitle = element_text(colour = COULEURS$texte_2, size = 10.5),
      plot.caption = element_text(colour = COULEURS$texte_2, size = 8.5, hjust = 0),
      plot.title.position = "plot", plot.caption.position = "plot",
      legend.position = "top", legend.justification = "left",
      legend.title = element_blank(),
      plot.margin = margin(14, 16, 10, 14)
    )
}

source_cerema <- "Source : Cerema, consommation d'espaces NAF 2011-2025 (Fichiers fonciers). Traitement : artificialisation-sols."
fmt_ha <- label_number(big.mark = " ", decimal.mark = ",")
fmt_pct <- function(x) paste0(format(round(100 * x), big.mark = " "), " %")

sauver <- function(g, nom, largeur = 9, hauteur = 5.5) {
  dir.create(CONFIG$dossier_figures, showWarnings = FALSE, recursive = TRUE)
  chemin <- file.path(CONFIG$dossier_figures, nom)
  ggsave(chemin, g, width = largeur, height = hauteur, dpi = 200, bg = COULEURS$fond)
  message("  ", chemin)
}

figure_serie <- function(serie) {
  ref <- serie$rythme_reference_ha_an[1]
  cible <- serie$rythme_cible_ha_an[1]
  evol <- mean(serie$conso_ha[serie$annee %in% CONFIG$annees_rythme]) / ref - 1
  d <- serie |>
    mutate(groupe = if_else(annee %in% CONFIG$annees_reference, "Décennie de référence 2011-2020",
                            "Depuis 2021"),
           sous_estimee = !annee %in% c(CONFIG$annees_reference, CONFIG$annees_rythme))
  g <- ggplot(d, aes(factor(annee), conso_ha, fill = groupe)) +
    geom_col(aes(alpha = sous_estimee), width = 0.72) +
    scale_alpha_manual(values = c(`FALSE` = 1, `TRUE` = 0.45), guide = "none") +
    geom_hline(yintercept = ref, colour = COULEURS$reference, linewidth = 0.6, linetype = "22") +
    geom_hline(yintercept = cible, colour = COULEURS$texte, linewidth = 0.6, linetype = "22") +
    annotate("label", x = 14.45, y = ref, vjust = -0.25, hjust = 1, size = 3.3, colour = COULEURS$reference,
             fill = COULEURS$fond, label.size = 0, label.padding = unit(2, "pt"),
             label = paste0("Rythme 2011-2020 : ", fmt_ha(round(ref, -1)), " ha/an")) +
    annotate("label", x = 14.45, y = cible, vjust = 1.25, hjust = 1, size = 3.3, colour = COULEURS$texte,
             fill = COULEURS$fond, label.size = 0, label.padding = unit(2, "pt"),
             label = paste0("Objectif -50 % : ", fmt_ha(round(cible, -1)), " ha/an")) +
    annotate("text", x = 14, y = d$conso_ha[d$annee == 2024], vjust = -0.5, size = 3,
             colour = COULEURS$texte_2, label = "sous-\nestimée") +
    scale_fill_manual(values = c(COULEURS$reference, COULEURS$actuel)) +
    scale_y_continuous(labels = fmt_ha, expand = expansion(mult = c(0, 0.08))) +
    labs(
      title = paste0("Depuis 2021 : ", round(100 * evol), " % de consommation d'espaces, pour un objectif de -50 %"),
      subtitle = "Espaces naturels, agricoles et forestiers consommés chaque année en France, en hectares",
      x = NULL, y = NULL, caption = paste0(source_cerema, "\n2024 est sous-estimée : le Cerema attend sa stabilisation dans 2 à 3 millésimes.")
    ) +
    theme_projet()
  sauver(g, "serie_nationale.png")
}

figure_carte <- function(departements) {
  contours <- st_read("data/reference/departements.geojson", quiet = TRUE)
  classes <- c("Baisse de 50 % ou plus", "Baisse de 25 à 50 %", "Baisse de moins de 25 %",
               "Hausse de moins de 25 %", "Hausse de 25 % ou plus")
  couleurs <- setNames(c("#184f95", "#5598e7", "#b7d3f6", "#f2a8a2", "#c23b3a"), classes)
  d <- departements |>
    mutate(classe = cut(evolution_rythme, c(-Inf, -0.5, -0.25, 0, 0.25, Inf),
                        labels = classes, right = FALSE))
  carte <- contours |>
    left_join(d, by = c("code" = "code_departement")) |>
    st_transform(2154)
  n_sur <- sum(d$evolution_rythme <= -0.5, na.rm = TRUE)
  g <- ggplot(carte) +
    geom_sf(aes(fill = classe), colour = COULEURS$fond, linewidth = 0.35) +
    scale_fill_manual(values = couleurs, drop = FALSE, na.value = "#d9d8d4") +
    labs(
      title = paste0("Seuls ", n_sur, " départements ont réduit leur rythme de moitié"),
      subtitle = "Rythme annuel 2021-2023 comparé à celui de 2011-2020",
      caption = paste0(source_cerema, "\nParis (consommation quasi nulle) en gris ; départements d'outre-mer dans les fichiers CSV.")
    ) +
    theme_void(base_size = 12, base_family = "DejaVu Sans") +
    theme(
      plot.background = element_rect(fill = COULEURS$fond, colour = NA),
      plot.title = element_text(colour = COULEURS$texte, face = "bold", size = 14),
      plot.subtitle = element_text(colour = COULEURS$texte_2, size = 10.5),
      plot.caption = element_text(colour = COULEURS$texte_2, size = 8.5, hjust = 0),
      plot.title.position = "plot", plot.caption.position = "plot",
      legend.title = element_blank(), legend.text = element_text(colour = COULEURS$texte_2),
      legend.position = "right", plot.margin = margin(14, 16, 10, 14)
    ) +
    guides(fill = guide_legend(byrow = TRUE))
  sauver(g, "carte_departements.png", largeur = 9, hauteur = 7.5)
}

figure_densite <- function(densite) {
  d <- densite |> filter(!is.na(densite)) |>
    mutate(densite = factor(densite, levels = rev(levels(densite))))
  g <- ggplot(d, aes(m2_habitat_par_menage, densite)) +
    geom_col(fill = COULEURS$reference, width = 0.62) +
    geom_text(aes(label = paste0(fmt_ha(round(m2_habitat_par_menage, -1)), " m²")),
              hjust = -0.12, size = 3.6, colour = COULEURS$texte) +
    scale_x_continuous(labels = fmt_ha, expand = expansion(mult = c(0, 0.15))) +
    labs(
      title = "Un ménage de plus consomme 30 fois plus de terres à la campagne qu'en ville",
      subtitle = "Surface consommée pour l'habitat par ménage supplémentaire, 2011-2022, selon la grille de densité de l'INSEE",
      x = "m² par ménage supplémentaire", y = NULL,
      caption = paste0(source_cerema, "\nMénages : INSEE, recensements 2011 et 2022.")
    ) +
    theme_projet() +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = COULEURS$grille, linewidth = 0.4))
  sauver(g, "efficacite_densite.png", hauteur = 4.2)
}

figure_epci <- function(epci) {
  ordre <- c("Baisse d'au moins 50 %", "Baisse de moins de 50 %", "Stable ou en hausse")
  d <- epci |> filter(statut %in% ordre) |> count(statut) |>
    mutate(statut = factor(statut, levels = rev(ordre)), part = n / sum(n))
  part_hausse <- d$part[d$statut == "Stable ou en hausse"]
  titre <- if (part_hausse >= 0.3) "Près d'un tiers des intercommunalités consomment autant ou plus qu'avant" else
    paste0(fmt_pct(part_hausse), " des intercommunalités consomment autant ou plus qu'avant")
  g <- ggplot(d, aes(n, statut)) +
    geom_col(fill = COULEURS$reference, width = 0.62) +
    geom_text(aes(label = paste0(n, " EPCI (", fmt_pct(part), ")")),
              hjust = -0.08, size = 3.6, colour = COULEURS$texte) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.3))) +
    labs(
      title = titre,
      subtitle = "Intercommunalités selon l'évolution de leur rythme annuel, 2021-2023 comparé à 2011-2020",
      x = "Nombre d'intercommunalités", y = NULL, caption = source_cerema
    ) +
    theme_projet() +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = COULEURS$grille, linewidth = 0.4))
  sauver(g, "statut_epci.png", hauteur = 3.8)
}

produire_figures <- function(res) {
  figure_serie(res$serie)
  figure_carte(res$departements)
  figure_densite(res$densite)
  figure_epci(res$epci)
}
