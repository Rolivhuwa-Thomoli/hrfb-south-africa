## =====================================================================
## SPARSE GROUP LASSO (sparsegl package; Liang et al. 2024)
##
## Sparse group lasso penalty (per group g):
##   lambda * [ (1 - alpha) * sqrt(p_g) * ||beta_g||_2  +  alpha * ||beta_g||_1 ]
##   alpha = 0  -> ordinary group lasso (whole factor in or out)
##   alpha = 1  -> ordinary lasso (each dummy in or out on its own)
##   0 < alpha < 1 -> factor can enter, but single levels can still be zero
##
## sparsegl has NO random effects, so this is a fixed-effects logistic
## model on the same dummy design and the same factor groups as 04.
## alpha is fixed at 0.05 (the package default; closest to the group lasso).
## lambda is chosen by BIC, the same rule as 04 and 04c, so the three
## penalised methods are compared at their own BIC-optimal lambda.
##
## Only the final (BIC-optimal) estimates are kept. The lambda path used
## to find the optimum is not saved.
##
## Output: output/sgl_final_estimates.RData (object sgl_final)
##   a list with one named vector per outcome: intercept and terms, in the
##   same names as the glmmLasso fits.
## Compare the three methods with 10_compare_lasso_estimates.R.
##
## STEP 9. Needs data/hrfb_data.RData.
## =====================================================================

library(sparsegl)

load("data/hrfb_data.RData")   # df and df_34

predictors <- c("age_group", "province", "residence", "ethnicity",
                "hh_head_sex", "education", "literacy", "wealth_index",
                "marital_status", "currently_working", "ever_used_fp",
                "unmet_need", "consumes_media", "heard_fp_from_media")

alpha_use <- 0.05

set.seed(2024)


## ---------------------------------------------------------------------
## Fit one outcome; return the BIC-optimal estimates only
## ---------------------------------------------------------------------
run_sgl_final <- function(outcome, data) {

  X <- model.matrix(as.formula(paste("~", paste(predictors, collapse = " + "))),
                    data = data)
  group <- attr(X, "assign")[-1]          # same groups as step 4
  X <- X[, -1]
  colnames(X) <- make.names(colnames(X))
  y <- data[[outcome]]

  ## folds by cluster, so women from the same cluster stay together
  cl     <- as.integer(factor(data$cluster))
  fold_c <- sample(rep(1:5, length.out = max(cl)))
  foldid <- fold_c[cl]

  ## cv.sparsegl gives the lambda path; the BIC choice is made on that path
  cv  <- cv.sparsegl(X, y, group = group, family = "binomial",
                     asparse = alpha_use, foldid = foldid, nlambda = 50)
  fit <- cv$sparsegl.fit

  ## BIC along the path: deviance + log(n) * df, df = non-zero coefficients + intercept
  ## (estimate_risk() only works for the Gaussian family, so it is computed by hand)
  p_hat   <- predict(fit, X, type = "response")
  p_hat   <- pmin(pmax(p_hat, 1e-10), 1 - 1e-10)
  dev     <- -2 * colSums(y * log(p_hat) + (1 - y) * log(1 - p_hat))
  df_l    <- colSums(as.matrix(fit$beta) != 0) + 1
  bic     <- dev + log(length(y)) * df_l
  lam_bic <- fit$lambda[which.min(bic)]

  est <- as.numeric(coef(fit, s = lam_bic))   # intercept first
  names(est) <- c("(Intercept)", colnames(X))

  list(outcome = outcome, alpha = alpha_use, lambda_bic = lam_bic,
       BIC = min(bic), beta = est)
}


## ---------------------------------------------------------------------
## Run for the four outcomes (hrfb_greater_34 uses df_34)
## ---------------------------------------------------------------------
sgl_final <- list(
  hrfb_less_18    = run_sgl_final("hrfb_less_18", df),
  hrfb_greater_34 = run_sgl_final("hrfb_greater_34", df_34),
  hrfb_sbi        = run_sgl_final("hrfb_sbi", df),
  hrfb_parity     = run_sgl_final("hrfb_parity", df)
)

save(sgl_final, file = "output/sgl_final_estimates.RData")

for (o in names(sgl_final)) {
  b <- sgl_final[[o]]$beta
  cat(sprintf("%-16s lambda (BIC) = %.4f | non-zero = %d of %d\n",
              o, sgl_final[[o]]$lambda_bic, sum(b[-1] != 0), length(b) - 1))
}
