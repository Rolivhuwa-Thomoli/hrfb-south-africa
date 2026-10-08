## =====================================================================
## ORDINARY LASSO version: glmmLasso with BIC to choose lambda, for all four
## HRFB outcomes. Every dummy column is penalised on its own, so single
## levels can be dropped (no whole-factor grouping). Same lambda grid,
## start values and BIC rule as 04_group_lasso_selection.R, so the three
## penalised methods can be compared directly. Output files start with
## "ordinary_bic_" and "ordinary_paths_".
##
## Why BIC instead of CV: one fit per lambda on the full data, instead of
## 5 fits per lambda (one per fold) -> roughly 5x faster.
##
## STEP 4. Needs data/hrfb_data.RData from 01_data_pipeline.R.
## If a fit fails, R stops at that point so you can inspect it.
## =====================================================================

library(glmmLasso)
library(MASS)   # glmmPQL for starting values
library(nlme)   # VarCorr for starting values

load("data/hrfb_data.RData")   # df and df_34

## Predictors used for every outcome
predictors <- c("age_group", "province", "residence", "ethnicity",
                "hh_head_sex", "education", "literacy", "wealth_index",
                "marital_status", "currently_working", "ever_used_fp",
                "unmet_need", "consumes_media", "heard_fp_from_media")

## Lambda grid on the log scale, from large (everything shrunk to zero)
## down to small. The bottom was 1e-2 until the BIC optimum for three
## outcomes sat exactly at 1e-2 (no shrinkage), so the grid now goes to 1e-4
## with 40 values (similar spacing to before).
## The group penalty acts on whole factors, so the top of the grid is set
## higher than before to make sure every factor starts at zero.
lambda <- exp(seq(log(2000), log(1e-4), length.out = 40))

## Outcomes to refit in this run. Any outcome not listed is loaded from its
## saved output/ordinary_bic_*.RData file instead. Use all four to refit everything.
outcomes_to_run <- c("hrfb_less_18", "hrfb_greater_34", "hrfb_sbi", "hrfb_parity")


## ---------------------------------------------------------------------
## Plotting functions (can be re-run later from the saved results,
## e.g. load("output/ordinary_bic_18.RData"); plot_bic(gbic_18) - no refitting needed)
## ---------------------------------------------------------------------

## BIC against lambda, with the optimum marked in red
plot_bic <- function(res) {
  opt <- res$opt
  plot(res$lambda, res$BIC, type = "b", pch = 16, col = "grey40", log = "x",
       xlab = expression(lambda ~ "(log scale)"), ylab = "BIC",
       main = paste("Group lasso BIC path:", res$outcome))
  abline(v = res$lambda[opt], col = "red", lty = 2, lwd = 2)
  points(res$lambda[opt], res$BIC[opt], col = "red", pch = 19, cex = 1.8)
  legend("topright", bg = "white", text.col = "red",
         legend = c(paste0("optimal lambda = ", round(res$lambda[opt], 3)),
                    paste0("BIC = ", round(res$BIC[opt], 1))))
}

## Coefficient paths: how each coefficient shrinks as lambda grows
plot_paths <- function(res) {
  opt <- res$opt
  matplot(res$lambda, res$paths, type = "l", lty = 1, lwd = 1.5, log = "x",
          xlab = expression(lambda ~ "(log scale)"), ylab = expression(hat(beta)),
          main = paste("Group lasso coefficient paths:", res$outcome))
  abline(h = 0, lty = 3, col = "grey")
  abline(v = res$lambda[opt], col = "red", lty = 2, lwd = 2)
  legend("topright", bg = "white", text.col = "red",
         legend = paste0("optimal lambda = ", round(res$lambda[opt], 3)))
}

## Draw both plots on screen and save them as PNG files
make_plots <- function(res) {
  plot_bic(res)
  plot_paths(res)

  png(paste0("output/ordinary_bic_", res$outcome, ".png"), width = 900, height = 650, res = 110)
  plot_bic(res)
  dev.off()

  png(paste0("output/ordinary_paths_", res$outcome, ".png"), width = 900, height = 650, res = 110)
  plot_paths(res)
  dev.off()
}


## ---------------------------------------------------------------------
## Function that runs the whole BIC path for one outcome
## ---------------------------------------------------------------------
run_bic_lasso <- function(outcome, data) {

  cat("\n#############################################\n")
  cat("  Outcome:", outcome, "  (n =", nrow(data), ")\n")
  cat("#############################################\n")

  ## 1. Dummy-coded design matrix (glmmLasso needs numeric columns)
  X <- model.matrix(as.formula(paste("~", paste(predictors, collapse = " + "))),
                    data = data)

  ## GROUPS: the "assign" attribute says which variable each column belongs
  ## to (1 = age_group, 2 = province, ...). Columns with the same number are
  ## penalised together as one group.
  index <- seq_len(ncol(X) - 1)     # ORDINARY lasso: every dummy column is its own group (X still has the intercept here)

  X <- X[, -1]                        # drop the intercept column
  colnames(X) <- make.names(colnames(X))

  dat2 <- data.frame(y = data[[outcome]], cluster = data$cluster,
                     X, check.names = FALSE)

  fixform <- as.formula(paste("y ~", paste(colnames(X), collapse = " + ")))
  fam     <- binomial(link = "logit")
  p       <- ncol(X)

  ## 2. Starting values from an intercept-only PQL model
  PQL <- glmmPQL(y ~ 1, random = ~1 | cluster, family = fam, data = dat2)

  Delta.start <- matrix(c(as.numeric(PQL$coef$fixed), rep(0, p),
                          as.numeric(t(PQL$coef$random$cluster))), nrow = 1)
  Q.start <- as.numeric(VarCorr(PQL)[1, 1])

  ## 3. Loop over lambda (large -> small), using warm starts
  BIC_vec   <- rep(Inf, length(lambda))
  n_nonzero <- rep(NA, length(lambda))
  coef_path <- matrix(NA, length(lambda), p)   # converged coefficients at each lambda
  best_fit  <- NULL

  for (j in 1:length(lambda)) {

    fit <- glmmLasso(fixform, rnd = list(cluster = ~1),
                     family = fam, data = dat2, lambda = lambda[j],
                     switch.NR = FALSE, final.re = FALSE,
                     control = list(start = Delta.start[j, ], q_start = Q.start[j],
                                    index = index))

    BIC_vec[j]   <- fit$bic
    n_nonzero[j] <- sum(fit$coefficients[-1] != 0)
    coef_path[j, ] <- fit$coefficients[-1]

    cat(sprintf("lambda %2d of %d = %8.3f | BIC = %9.2f | non-zero coefs = %d\n",
                j, length(lambda), lambda[j], BIC_vec[j], n_nonzero[j]))

    ## keep the fit with the lowest BIC so far (no need to refit later)
    if (BIC_vec[j] == min(BIC_vec)) best_fit <- fit

    ## warm starts for the next lambda
    Delta.start <- rbind(Delta.start, fit$Deltamatrix[fit$conv.step, ])
    Q.start     <- c(Q.start, fit$Q_long[[fit$conv.step + 1]])
  }

  ## 4. Check the grid started high enough
  if (n_nonzero[1] > 0) {
    cat("WARNING: some coefficients were non-zero at the largest lambda.",
        "Increase the top of the lambda grid.\n")
  }

  opt <- which.min(BIC_vec)
  cat("\nOptimal lambda (BIC):", round(lambda[opt], 4),
      " | position", opt, "of", length(lambda), "\n")
  if (opt == length(lambda)) {
    cat("WARNING: optimum is at the smallest lambda - extend the grid downwards.\n")
  }

  ## 5. Which variables were selected? (a variable is kept if any of its
  ##    dummy columns has a non-zero coefficient)
  coefs    <- best_fit$coefficients[-1]
  selected <- c()
  for (v in predictors) {
    if (any(coefs[startsWith(names(coefs), v)] != 0)) selected <- c(selected, v)
  }
  cat("Selected variables:", length(selected), "of", length(predictors), "\n")
  print(selected)
  cat("Dropped variables:", setdiff(predictors, selected), "\n")

  ## 6. Collect results (coefficient path = fixed effects at each lambda).
  ## Check that the stored path at the optimum is the reported best fit.
  ## (Earlier versions read the paths from fit$Deltamatrix, which holds an
  ## early iterate, not the converged estimates.)
  stopifnot(isTRUE(all.equal(unname(coef_path[opt, ]),
                             unname(best_fit$coefficients[-1]))))
  paths <- coef_path
  res <- list(outcome   = outcome,
              lambda    = lambda,
              BIC       = BIC_vec,
              opt       = opt,
              best_fit  = best_fit,
              selected  = selected,
              paths     = paths,
              coef_path = coef_path)

  ## 7. Plots: BIC curve and coefficient paths, optimum marked in red
  make_plots(res)

  res
}


## ---------------------------------------------------------------------
## Run for each outcome in outcomes_to_run (saved after each one, so nothing
## is lost if a later outcome fails). Other outcomes are loaded from file.
## hrfb_greater_34 uses df_34.
## ---------------------------------------------------------------------
run_or_load <- function(outcome, data, file, obj_name) {
  if (outcome %in% outcomes_to_run) {
    res <- run_bic_lasso(outcome, data)
    assign(obj_name, res)
    save(list = obj_name, file = file)
  } else {
    load(file)   # restores the object called obj_name
    cat("\nLoaded saved fit for", outcome, "from", file, "\n")
  }
  get(obj_name)
}

gbic_18     <- run_or_load("hrfb_less_18", df, "output/ordinary_bic_18.RData", "gbic_18")
gbic_34     <- run_or_load("hrfb_greater_34", df_34, "output/ordinary_bic_34.RData", "gbic_34")
gbic_sbi    <- run_or_load("hrfb_sbi", df, "output/ordinary_bic_sbi.RData", "gbic_sbi")
gbic_parity <- run_or_load("hrfb_parity", df, "output/ordinary_bic_parity.RData", "gbic_parity")

## Summary of what BIC selected for each outcome
all_bic <- list(gbic_18, gbic_34, gbic_sbi, gbic_parity)

for (res in all_bic) {
  cat("\n", res$outcome, ": lambda =", round(res$lambda[res$opt], 3),
      "| kept", length(res$selected), "variables\n")
  cat("  dropped:", setdiff(predictors, res$selected), "\n")
}

## One figure with the four BIC curves side by side (for the dissertation)
png("output/ordinary_bic_all_outcomes.png", width = 1400, height = 1000, res = 120)
par(mfrow = c(2, 2))
for (res in all_bic) plot_bic(res)
dev.off()

png("output/ordinary_paths_all_outcomes.png", width = 1400, height = 1000, res = 120)
par(mfrow = c(2, 2))
for (res in all_bic) plot_paths(res)
dev.off()

par(mfrow = c(1, 1))
