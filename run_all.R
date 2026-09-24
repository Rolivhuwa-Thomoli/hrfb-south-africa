# Run the full pipeline from the repository root:  Rscript run_all.R
# Requires data/raw/ZAIR71FL.SAV (see data/README.md).
# Note: step 03 (cross-validated glmmLasso) takes 1-3 hours on a laptop.
for (step in c("R/01_prepare_data.R", "R/02_explore.R",
               "R/03_variable_selection.R", "R/04_multilevel_models.R")) {
  message("\n==== ", step, " ====")
  system2("Rscript", step)
}
