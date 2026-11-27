# installer.R
# Installe les paquets R utilisés par le projet. Usage : Rscript installer.R
paquets <- c("readr", "dplyr", "tidyr", "jsonlite", "DBI", "RPostgres", "testthat")
manquants <- setdiff(paquets, rownames(installed.packages()))
if (length(manquants) > 0) install.packages(manquants, repos = "https://cloud.r-project.org")
message("Paquets prêts : ", paste(paquets, collapse = ", "))
