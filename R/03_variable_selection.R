# =============================================================================
# 03_variable_selection.R
# LASSO variable selection for a multilevel logistic model (glmmLasso),
# with the penalty chosen by 5-fold cross-validation. One function, run for
# each of the four HRFB outcomes (replaces four near-identical scripts).
#
# Input : data/processed/hrfb_analysis.rds
# Output: figures/cv_<outcome>.png, results/lasso_selection_<outcome>.csv
# =============================================================================

suppressPackageStartupMessages({
  library(glmmLasso)
  library(MASS)   # glmmPQL: starting values
  library(nlme)   # VarCorr
})

OUTCOMES <- c("hrfb_less_18", "hrfb_greater_34", "hrfb_sbi", "hrfb_parity")
PREDICTORS <- c("age_group", "province", "residence", "ethnicity", "hh_head_sex",
                "education", "literacy", "wealth_index", "marital_status",
                "currently_working", "ever_used_fp", "unmet_need",
                "consumes_media", "heard_fp_from_media")

run_glmmlasso_cv <- function(df, outcome, predictors = PREDICTORS, k = 5,
                             lambda = exp(seq(log(500), log(1e-4), length.out = 20)),
                             seed = 123) {

  # glmmLasso needs a numeric design matrix: dummy-code every factor.
  # Reference level = first factor level (set in 01_prepare_data.R).
  X <- model.matrix(reformulate(predictors), data = df)[, -1]
  colnames(X) <- make.names(colnames(X))
  dat <- data.frame(y = df[[outcome]], cluster = df$cluster, X)
  form <- as.formula(paste("y ~", paste(colnames(X), collapse = " + ")))
  fam <- binomial(link = "logit")

  # Starting values from an intercept-only PQL fit
  pql <- glmmPQL(y ~ 1, random = ~ 1 | cluster, family = fam, data = dat, verbose = FALSE)
  delta_start <- c(as.numeric(pql$coef$fixed), rep(0, ncol(X)),
                   as.numeric(t(pql$coef$random$cluster)))
  q_start <- as.numeric(VarCorr(pql)[1, 1])

  fit_one <- function(data, lam, start, q) {
    try(glmmLasso(form, rnd = list(cluster = ~ 1), family = fam, data = data,
                  lambda = lam, switch.NR = FALSE, final.re = FALSE,
                  control = list(start = start, q_start = q)), silent = TRUE)
  }

  # ---- k-fold CV over a decreasing lambda path, with warm starts ------------
  # Starting at a large lambda (all coefficients shrunk to 0) and re-using each
  # solution as the start for the next, smaller lambda is much faster and more
  # stable than fitting every lambda from scratch.
  set.seed(seed)
  fold <- sample(rep(seq_len(k), length.out = nrow(dat)))
  cv_dev <- matrix(NA_real_, nrow = length(lambda), ncol = k)

  for (i in seq_len(k)) {
    message(sprintf("[%s] fold %d/%d", outcome, i, k))
    train <- dat[fold != i, ]; test <- dat[fold == i, ]
    start <- delta_start; q <- q_start
    for (j in seq_along(lambda)) {
      fit <- fit_one(train, lambda[j], start, q)
      if (inherits(fit, "try-error")) next
      p_hat <- predict(fit, test)
      cv_dev[j, i] <- sum(fam$dev.resids(test$y, p_hat, wt = rep(1, nrow(test))))
      start <- fit$Deltamatrix[fit$conv.step, ]
      q     <- as.numeric(fit$Q_long[[fit$conv.step + 1]])   # 1x1 matrix -> scalar
    }
  }

  total_dev <- rowSums(cv_dev)             # NA if any fold failed at that lambda
  opt <- which.min(total_dev)

  # ---- Final penalised fit on all data at the chosen lambda -----------------
  final <- fit_one(dat, lambda[opt], delta_start, q_start)
  coefs <- final$coefficients[-1]
  selection <- data.frame(term = names(coefs), coefficient = round(coefs, 4),
                          selected = abs(coefs) > 1e-6, row.names = NULL)

  list(outcome = outcome, lambda = lambda, cv_deviance = total_dev,
       lambda_opt = lambda[opt], selection = selection)
}

plot_cv <- function(res, file) {
  png(file, width = 1000, height = 650, res = 150)
  par(mar = c(4.5, 4.5, 3, 1))
  plot(res$lambda, res$cv_deviance, type = "b", log = "x", pch = 19, cex = 0.7,
       xlab = expression(lambda ~ "(penalty strength, log scale)"),
       ylab = "CV deviance (5-fold)", main = paste("glmmLasso CV:", res$outcome))
  abline(v = res$lambda_opt, col = "#C0392B", lty = 2)
  legend("topleft", bty = "n",
         legend = sprintf("optimal lambda = %.2f  |  %d of %d terms kept",
                          res$lambda_opt, sum(res$selection$selected), nrow(res$selection)))
  dev.off()
}

# ---- Run as a script ---------------------------------------------------------
if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  outcomes <- if (length(args)) args else OUTCOMES
  df <- readRDS("data/processed/hrfb_analysis.rds")
  dir.create("figures", showWarnings = FALSE); dir.create("results", showWarnings = FALSE)
  for (o in outcomes) {
    res <- run_glmmlasso_cv(df, o)
    saveRDS(res, file.path("results", paste0("lasso_cv_", o, ".rds")))
    write.csv(res$selection, file.path("results", paste0("lasso_selection_", o, ".csv")),
              row.names = FALSE)
    plot_cv(res, file.path("figures", paste0("cv_", o, ".png")))
    message(sprintf("[%s] optimal lambda %.3f, %d/%d terms kept", o, res$lambda_opt,
                    sum(res$selection$selected), nrow(res$selection)))
  }
}
