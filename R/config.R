# config.R
# Paramètres du projet : chemins, périodes, objectif de réduction.
# Lu par tous les autres scripts ; ne produit rien.

CONFIG <- list(
  # Fichier communal du Cerema (consommation d'ENAF 2011-2025), voir docs/DONNEES.md
  fichier_conso = Sys.getenv("ARTIF_FICHIER_CONSO", "data/raw/conso-com.csv"),
  dossier_sorties = "data/processed",
  dossier_figures = "docs/images",

  # Les flux du fichier sont en m² malgré la mention « hectares » de la documentation :
  # 294,7 millions de m² en 2011, soit 29 470 ha, conforme aux publications du Cerema.
  m2_par_ha = 1e4,

  # Années de flux : l'année N désigne le flux du 1er janvier N au 1er janvier N+1,
  # comme dans les publications du Cerema.
  annees = 2011:2024,

  # Décennie de référence de la loi Climat et résilience : 2011 à 2020 (flux 2011-2021).
  annees_reference = 2011:2020,

  # Rythme actuel : 2021 à 2023. L'année 2024 est connue mais sous-estimée
  # (le Cerema annonce sa stabilisation dans 2 à 3 millésimes) : elle entre dans
  # le cumul consommé, présenté comme une borne basse, pas dans le rythme.
  annees_rythme = 2021:2023,
  annees_cumul = 2021:2024,

  # Objectif national : diviser par deux la consommation 2021-2031 par rapport à 2011-2021.
  # Le même taux est appliqué à chaque territoire, à titre de repère : les enveloppes
  # réellement opposables sont fixées par les Sraddet, Scot et PLU(i).
  reduction_cible = 0.5,
  fin_periode = 2030,

  # Recensements disponibles dans le fichier (efficacité foncière)
  periode_efficacite = "2011-2022",

  # Codes des départements d'outre-mer présents dans le fichier
  dom = c("971", "972", "973", "974", "976"),

  # Connexion PostgreSQL (étape « base » uniquement), lue dans l'environnement ou .Renviron
  pg = list(
    host = Sys.getenv("PGHOST", "localhost"),
    port = as.integer(Sys.getenv("PGPORT", "5432")),
    dbname = Sys.getenv("PGDATABASE", "artificialisation"),
    user = Sys.getenv("PGUSER", "postgres"),
    password = Sys.getenv("PGPASSWORD", ""),
    schema = Sys.getenv("ARTIF_SCHEMA", "artif")
  )
)

# Nom de la colonne de flux total pour l'année N (ex. 2011 -> "naf11art12")
col_flux <- function(annee, destination = "total") {
  a <- sprintf("%02d", annee %% 100)
  b <- sprintf("%02d", (annee + 1) %% 100)
  if (destination == "total") paste0("naf", a, "art", b) else paste0("art", a, destination, b)
}

DESTINATIONS <- c(
  hab = "Habitat", act = "Activité", mix = "Mixte",
  rou = "Routes", fer = "Voies ferrées", inc = "Inconnue"
)
