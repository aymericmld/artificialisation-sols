# controles.R
# Contrôles bloquants sur le fichier source et diagnostics non bloquants.
# Lit   : le fichier brut (lire_conso) et la table « communes »
# Produit, en mémoire : une liste « rapport » (écrite en JSON par export.R).
# Si un contrôle bloquant échoue, la chaîne s'arrête avant d'écrire les résultats.

suppressPackageStartupMessages(library(dplyr))

controler <- function(brut, communes, flux) {
  tol_m2 <- 1  # tolérance d'arrondi, en m², commune par commune

  annuel <- sapply(CONFIG$annees, col_flux)
  somme_annuelle <- rowSums(as.matrix(brut[, annuel]))

  ecart_destinations <- sapply(CONFIG$annees, function(a) {
    dest <- sapply(names(DESTINATIONS), function(d) col_flux(a, d))
    max(abs(brut[[col_flux(a)]] - rowSums(as.matrix(brut[, dest]))), na.rm = TRUE)
  })

  conso_totale <- somme_annuelle / CONFIG$m2_par_ha
  avec_surface <- !is.na(communes$surface_ha)

  bloquants <- list(
    list(
      nom = "Codes commune uniques et renseignés",
      ok = !anyNA(brut$idcom) && !anyDuplicated(brut$idcom),
      detail = sprintf("%d communes", nrow(brut))
    ),
    list(
      nom = "Département et EPCI renseignés",
      ok = !anyNA(communes$code_departement) && !anyNA(communes$code_epci),
      detail = sprintf("%d EPCI, %d départements",
                       n_distinct(communes$code_epci), n_distinct(communes$code_departement))
    ),
    list(
      nom = "Aucun flux négatif ou manquant",
      ok = !anyNA(as.matrix(brut[, annuel])) && all(as.matrix(brut[, annuel]) >= 0),
      detail = sprintf("%d colonnes annuelles", length(annuel))
    ),
    list(
      nom = "Somme des flux annuels égale au cumul 2011-2025 du Cerema",
      ok = max(abs(somme_annuelle - brut$naf11art25)) <= tol_m2,
      detail = sprintf("écart maximal %.1f m²", max(abs(somme_annuelle - brut$naf11art25)))
    ),
    list(
      nom = "Total égal à la somme des destinations, chaque année",
      ok = max(ecart_destinations) <= tol_m2,
      detail = sprintf("écart maximal %.1f m²", max(ecart_destinations))
    ),
    list(
      nom = "Consommation 2011-2024 inférieure à la surface communale",
      ok = all(conso_totale[avec_surface] <= communes$surface_ha[avec_surface]),
      detail = sprintf("%d communes avec surface connue", sum(avec_surface))
    ),
    list(
      nom = "Flux longs cohérents avec la table des communes",
      ok = abs(sum(flux$conso_ha) - sum(conso_totale)) < 1,
      detail = sprintf("%.0f ha au total", sum(flux$conso_ha))
    )
  )

  par_annee <- flux |> group_by(annee) |> summarise(ha = sum(conso_ha))
  diagnostics <- list(
    communes_sans_surface = sum(!avec_surface),
    communes_outre_mer = sum(communes$outre_mer),
    communes_sans_emplois_2011_ou_2022 = sum(is.na(brut$emp11) | is.na(brut$emp22)),
    communes_sans_consommation_2011_2024 = sum(conso_totale == 0),
    communes_avec_un_flux_annuel_superieur_a_20_ha = sum(apply(as.matrix(brut[, annuel]), 1, max) > 20e4),
    consommation_par_annee_ha = setNames(as.list(round(par_annee$ha)), par_annee$annee)
  )

  list(
    date_execution = format(Sys.time(), "%Y-%m-%d %H:%M"),
    fichier_source = basename(CONFIG$fichier_conso),
    controles_bloquants = bloquants,
    diagnostics = diagnostics
  )
}

verifier <- function(rapport) {
  echecs <- Filter(function(c) !isTRUE(c$ok), rapport$controles_bloquants)
  for (c in rapport$controles_bloquants) {
    message(if (isTRUE(c$ok)) "  [ok]    " else "  [ÉCHEC] ", c$nom, " (", c$detail, ")")
  }
  if (length(echecs) > 0) stop(length(echecs), " contrôle(s) bloquant(s) en échec : résultats non écrits.")
  invisible(TRUE)
}
