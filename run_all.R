# Run the full analysis from the repository root:  Rscript run_all.R
# Requires ZAIR71SV/ZAIR71FL.SAV (see data/README.md).
# Steps 04, 04c and 08 are slow (08 takes about 25-30 minutes on a laptop).
steps <- c("R/01_data_pipeline.R",          # analysis data set -> data/hrfb_data.RData
           "R/02_eda.R",                    # summaries in the console
           "R/02b_outlier_analysis.R",      # outlier screening + sensitivity refit
           "R/03_bivariate_chisq.R",        # chi-square screening
           "R/04_group_lasso_selection.R",  # group LASSO, lambda by BIC
           "R/04c_ordinary_glmmlasso.R",    # ordinary LASSO, for comparison
           "R/05_final_glmm.R",             # final two-level logistic models
           "R/06_selection_table.R",        # LaTeX table of the selection
           "R/07_forest_plot.R",            # forest plots
           "R/08_model_evaluation.R",       # discrimination, calibration, validation
           "R/09_sparse_group_lasso.R",     # sparse group LASSO, for comparison
           "R/10_compare_lasso_estimates.R",# the three penalised methods side by side
           "R/11_portfolio_figures.R")      # figures in this README
for (step in steps) {
  message("\n==== ", step, " ====")
  status <- system2("Rscript", step)
  if (status != 0) stop(step, " failed")
}
