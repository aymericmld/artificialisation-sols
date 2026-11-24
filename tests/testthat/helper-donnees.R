# Charge le code du projet et fabrique un petit fichier synthétique
# au format du Cerema (trois communes, deux EPCI, deux départements).

racine <- normalizePath(file.path("..", ".."))
for (f in c("config", "lecture", "controles", "indicateurs", "modele")) {
  source(file.path(racine, "R", paste0(f, ".R")), encoding = "UTF-8")
}

fichier_synthetique <- function(dossier = tempdir()) {
  communes <- data.frame(
    idcom = c("29039", "29232", "56121"),
    idcomtxt = c("Concarneau", "Quimper", "Lorient"),
    idreg = "53", idregtxt = "Bretagne",
    iddep = c("29", "29", "56"), iddeptxt = c("Finistère", "Finistère", "Morbihan"),
    epci25 = c("242900645", "242900314", "200042174"),
    epci25txt = c("Concarneau Cornouaille", "Quimper Bretagne Occidentale", "Lorient Agglomération"),
    scot = "", aav2020 = "001", libaav2020 = "Aire", cateaav2020 = "11",
    taav2017 = "1", tdaav2017 = "1", littoral = c("C", "NC", "C"), montagne_urba = "NC",
    abc = "B2", libdens_aav = c("Urbain intermédiaire", "Urbain dense", "Rural périurbain"),
    stringsAsFactors = FALSE
  )
  # Flux en m² : 2 ha par an et par destination « hab » de 2011 à 2020,
  # puis 0,5 ha par an pour la première commune, 3 ha pour la troisième.
  rythme_avant <- c(2, 1, 2) * 1e4
  rythme_apres <- c(0.5, 0, 3) * 1e4
  for (a in 2011:2024) {
    hab <- if (a <= 2020) rythme_avant else rythme_apres
    communes[[col_flux(a, "hab")]] <- hab
    for (d in c("act", "inc", "mix", "fer", "rou")) communes[[col_flux(a, d)]] <- 0
    communes[[col_flux(a)]] <- hab
  }
  somme <- function(annees) Reduce(`+`, lapply(annees, function(a) communes[[col_flux(a)]]))
  communes$naf11art25 <- somme(2011:2024)
  communes$naf11art21 <- somme(2011:2020)
  communes$naf21art25 <- somme(2021:2024)
  communes$naf11art22 <- somme(2011:2021)
  communes$art11hab22 <- somme(2011:2021)
  communes$pop11 <- c(19000, 63000, 57000); communes$pop22 <- c(20000, 64000, 56000)
  communes$men11 <- c(9000, 30000, 27000);  communes$men22 <- c(9500, 31000, 26500)
  communes$emp11 <- c(9000, 40000, 35000);  communes$emp22 <- c(9200, 40500, 34000)
  communes$surfcom2025 <- c(41e6, 84e6, 17e6)

  chemin <- file.path(dossier, "conso-com-test.csv")
  write.csv(communes, chemin, row.names = FALSE, fileEncoding = "UTF-8")
  chemin
}
