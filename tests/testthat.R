# Lance les tests : Rscript tests/testthat.R (depuis la racine du dépôt)
invisible(Sys.setlocale("LC_ALL", "C.UTF-8"))
library(testthat)
test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
