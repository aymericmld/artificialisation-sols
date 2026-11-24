test_that("la lecture convertit les m² en hectares et cumule les bonnes années", {
  brut <- lire_conso(fichier_synthetique())
  co <- preparer_communes(brut)
  expect_equal(co$conso_reference_ha, c(20, 10, 20))   # 2011-2020 : 10 ans
  expect_equal(co$conso_rythme_ha, c(1.5, 0, 9))       # 2021-2023 : 3 ans
  expect_equal(co$conso_cumul_ha, c(2, 0, 12))         # 2021-2024 : 4 ans
  expect_equal(co$surface_ha, c(4100, 8400, 1700))
})

test_that("les flux longs contiennent une ligne par commune, année et destination", {
  brut <- lire_conso(fichier_synthetique())
  flux <- preparer_flux(brut)
  expect_equal(nrow(flux), 3 * 14 * 6)
  expect_equal(sum(flux$conso_ha), sum(brut$naf11art25) / 1e4)
})

test_that("la trajectoire compare le rythme 2021-2023 à celui de 2011-2020", {
  co <- preparer_communes(lire_conso(fichier_synthetique())) |> ajouter_trajectoire()
  expect_equal(co$evolution_rythme, c(-0.75, -1, 0.5))
  expect_equal(co$statut, c("Baisse d'au moins 50 %", "Baisse d'au moins 50 %", "Stable ou en hausse"))
  expect_equal(co$enveloppe_ha, c(10, 5, 10))
  expect_equal(co$part_enveloppe_consommee, c(0.2, 0, 1.2))
  expect_equal(co$rythme_requis_ha_an, c(8 / 6, 5 / 6, 0))
})

test_that("une base de référence quasi nulle ne donne pas de pourcentage", {
  expect_equal(
    classer_trajectoire(c(NA, NA, -0.2), c(0, 0, 10), c(0, 3, 8)),
    c("Consommation quasi nulle", "Consommation nouvelle", "Baisse de moins de 50 %")
  )
})

test_that("l'agrégation additionne avant de calculer les taux", {
  co <- preparer_communes(lire_conso(fichier_synthetique()))
  dep <- indicateurs(co, "code_departement")
  finistere <- dep[dep$code_departement == "29", ]
  expect_equal(finistere$rythme_reference_ha_an, 3)
  expect_equal(finistere$rythme_actuel_ha_an, 0.5)
  expect_equal(finistere$evolution_rythme, 0.5 / 3 - 1)
})

test_that("l'efficacité n'est calculée que pour les territoires qui gagnent des ménages", {
  co <- preparer_communes(lire_conso(fichier_synthetique())) |> ajouter_efficacite()
  # Concarneau : 20,5 ha d'habitat 2011-2022 pour 500 ménages de plus
  expect_equal(co$m2_habitat_par_menage[1], 205000 / 500)
  expect_true(is.na(co$m2_habitat_par_menage[3]))
  res <- consommation_sans_croissance(co)
  expect_equal(sum(res$part_conso), 1)
  expect_equal(res$nb_communes[res$situation == "Ménages en baisse ou stables"], 1)
})

test_that("un EPCI à cheval sur deux départements est rattaché au principal", {
  co <- data.frame(code_epci = c("A", "A", "A"), code_departement = c("29", "29", "56"),
                   departement = c("Finistère", "Finistère", "Morbihan"), region = "Bretagne", x = 1:3)
  expect_equal(unique(rattacher_epci(co)$code_departement), "29")
})
