preparer <- function(brut) {
  list(brut = brut, communes = preparer_communes(brut), flux = preparer_flux(brut))
}

test_that("le fichier synthétique passe tous les contrôles bloquants", {
  d <- preparer(lire_conso(fichier_synthetique()))
  rapport <- controler(d$brut, d$communes, d$flux)
  expect_true(all(vapply(rapport$controles_bloquants, \(c) isTRUE(c$ok), logical(1))))
  expect_silent(suppressMessages(verifier(rapport)))
})

test_that("un flux négatif bloque la chaîne", {
  brut <- lire_conso(fichier_synthetique())
  brut$naf15art16[1] <- -1
  d <- preparer(brut)
  expect_error(suppressMessages(verifier(controler(d$brut, d$communes, d$flux))), "bloquant")
})

test_that("un cumul incohérent avec les flux annuels bloque la chaîne", {
  brut <- lire_conso(fichier_synthetique())
  brut$naf11art25[2] <- brut$naf11art25[2] + 5000
  d <- preparer(brut)
  rapport <- controler(d$brut, d$communes, d$flux)
  noms_echec <- vapply(Filter(\(c) !c$ok, rapport$controles_bloquants), \(c) c$nom, character(1))
  expect_equal(noms_echec, "Somme des flux annuels égale au cumul 2011-2025 du Cerema")
})

test_that("un code commune en double bloque la chaîne", {
  brut <- lire_conso(fichier_synthetique())
  brut$idcom[2] <- brut$idcom[1]
  d <- preparer(brut)
  expect_error(suppressMessages(verifier(controler(d$brut, d$communes, d$flux))), "bloquant")
})
