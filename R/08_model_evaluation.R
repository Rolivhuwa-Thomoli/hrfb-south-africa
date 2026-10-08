## =====================================================================
## Model evaluation for the four final HRFB GLMMs (from 05_final_glmm.R).
##
## For each outcome this script reports:
##   1. Fit vs the null model (Model 0): log-likelihood, deviance, AIC, BIC,
##      likelihood-ratio test
##   2. Cluster variation: ICC, MOR, PCV, and an LR test of the random
##      intercept (GLMM vs ordinary logistic regression)
##   3. R2 (Nakagawa marginal/conditional, Tjur)
##   4. Multicollinearity: generalised VIF
##   5. Discrimination: AUC (fixed effects only, and with cluster effects)
##   6. Calibration: slope, calibration-in-the-large, Brier, Hosmer-Lemeshow
##   7. Residuals: DHARMa simulated residuals (individual and cluster level)
##   8. Overfitting: bootstrap optimism (Harrell, B = 200) and 5-fold
##      cross-validation with whole clusters held out
##   9. Sensitivity: survey-weighted logistic regression (wt, psu, strata)
##
## STEP 8. Needs data/hrfb_data.RData (01) and
## output/final_glmm_models.RData (05). Takes about 25-30 minutes.
##
## Packages: lme4, pROC, performance, DHARMa, car, ResourceSelection, survey
##
## Output (new files only, nothing earlier is overwritten):
##   output/eval_summary_table.csv
##   output/eval_roc_all_outcomes.png
##   output/eval_calibration_all_outcomes.png
## =====================================================================

library(lme4)
library(pROC)
library(performance)
library(DHARMa)
library(car)
library(ResourceSelection)
library(survey)

set.seed(2026)   # same seed -> same bootstrap, CV folds and DHARMa results

load("data/hrfb_data.RData")                    # df and df_34
load("output/final_glmm_models.RData")          # glmm_birth_before18, glmm_birth_after34, glmm_short_interval, glmm_high_parity

ctrl <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
options(survey.lonely.psu = "adjust")

models <- list(less_18    = list(m = glmm_birth_before18, data = df),
               greater_34 = list(m = glmm_birth_after34,  data = df_34),
               sbi        = list(m = glmm_short_interval, data = df),
               parity     = list(m = glmm_high_parity,    data = df))


## ---------------------------------------------------------------------
## Helper functions
## ---------------------------------------------------------------------

## ICC and MOR from the cluster variance (latent-variable scale)
icc <- function(v) v / (v + pi^2 / 3)
mor <- function(v) exp(sqrt(2 * v) * qnorm(0.75))

## Calibration slope (ideal 1) and calibration-in-the-large (ideal 0)
calib <- function(y, p) {
  lp <- qlogis(pmin(pmax(p, 1e-8), 1 - 1e-8))
  c(slope = unname(coef(glm(y ~ lp, family = binomial))[2]),
    citl  = unname(coef(glm(y ~ offset(lp), family = binomial))[1]))
}

## Area under the ROC curve
auc_ <- function(y, p) as.numeric(auc(roc(y, p, quiet = TRUE)))


## ---------------------------------------------------------------------
## Function that runs every check for one outcome
## ---------------------------------------------------------------------
evaluate_model <- function(name, m, data) {

  fx <- formula(m, fixed.only = TRUE)
  yv <- all.vars(fx)[1]
  dat <- data[complete.cases(data[, c(all.vars(formula(m)), "wt", "psu", "strata")]), ]
  y <- getME(m, "y")

  cat("\n==========", name, "(n =", length(y), ") ==========\n")

  ## 1. Null model and fit statistics
  m0 <- glmer(as.formula(paste(yv, "~ 1 + (1 | cluster)")), family = binomial,
              data = dat, nAGQ = 25, control = ctrl)
  stopifnot(nobs(m0) == nobs(m))
  v0 <- VarCorr(m0)$cluster[1]
  v1 <- VarCorr(m)$cluster[1]
  lr    <- as.numeric(2 * (logLik(m) - logLik(m0)))
  lr_df <- attr(logLik(m), "df") - attr(logLik(m0), "df")

  ## 2. Is the random intercept needed? (boundary test, so the p-value is halved)
  g <- glm(fx, family = binomial, data = dat)
  lr_re <- as.numeric(2 * (logLik(m) - logLik(g)))
  if (isSingular(m)) cat("NOTE: singular fit (cluster variance = 0)\n")

  ## 3. R2
  r2 <- tryCatch(suppressWarnings(r2_nakagawa(m)), error = function(e) NULL)

  ## 4. Multicollinearity (GVIF^(1/(2df)) squared, comparable to an ordinary VIF)
  gv <- vif(g)
  gv <- if (is.matrix(gv)) gv[, 3]^2 else gv

  ## 5-6. Discrimination and calibration (apparent)
  p_marg <- predict(m, type = "response", re.form = NA)   # fixed effects only
  p_cond <- fitted(m)                                      # with cluster effects
  roc_m  <- roc(y, p_marg, quiet = TRUE)
  auc_ci <- ci.auc(roc_m)
  cal    <- calib(y, p_marg)
  hl     <- hoslem.test(y, p_marg, g = 10)

  ## 7. DHARMa simulated residuals
  sr  <- simulateResiduals(m, n = 250)
  ks  <- testUniformity(sr, plot = FALSE)$p.value
  dsp <- testDispersion(sr, plot = FALSE)
  out <- testOutliers(sr, type = "bootstrap", plot = FALSE)$p.value
  srg <- recalculateResiduals(sr, group = dat$cluster)
  ks_cl  <- testUniformity(srg, plot = FALSE)$p.value
  dsp_cl <- testDispersion(srg, plot = FALSE)$p.value

  ## 8a. Bootstrap optimism (ordinary logistic regression with the same predictors)
  B <- 200
  optim <- matrix(NA, B, 2)
  for (b in 1:B) {
    i  <- sample(nrow(dat), replace = TRUE)
    gb <- suppressWarnings(glm(fx, family = binomial, data = dat[i, ]))
    pb <- predict(gb, type = "response")
    po <- predict(gb, newdata = dat, type = "response")
    optim[b, ] <- c(auc_(dat[[yv]][i], pb) - auc_(dat[[yv]], po),
                    calib(dat[[yv]][i], pb)[1] - calib(dat[[yv]], po)[1])
  }
  auc_glm <- auc_(dat[[yv]], fitted(g))

  ## 8b. 5-fold CV with whole clusters held out (predicting new communities)
  cl   <- unique(dat$cluster)
  fold <- sample(rep(1:5, length.out = length(cl)))
  names(fold) <- cl
  p_cv <- rep(NA, nrow(dat))
  for (k in 1:5) {
    tr <- fold[as.character(dat$cluster)] != k
    mk <- suppressMessages(suppressWarnings(
      glmer(formula(m), family = binomial, data = dat[tr, ], nAGQ = 1, control = ctrl)))
    p_cv[!tr] <- predict(mk, newdata = dat[!tr, ], type = "response",
                         re.form = NA, allow.new.levels = TRUE)
  }
  cal_cv <- calib(dat[[yv]], p_cv)

  ## 9. Survey-weighted sensitivity analysis
  des <- svydesign(ids = ~psu, strata = ~strata, weights = ~wt, data = dat, nest = TRUE)
  sv  <- suppressWarnings(svyglm(fx, design = des, family = quasibinomial))
  b1  <- fixef(m)[-1]
  b2  <- coef(sv)[names(b1)]
  p1  <- summary(m)$coefficients[names(b1), 4]
  p2  <- summary(sv)$coefficients[names(b1), 4]
  changed <- names(b1)[(p1 < 0.05) != (p2 < 0.05)]
  if (length(changed)) {
    cat("Significance changes when weighted:\n")
    print(data.frame(term = changed, p_glmm = signif(p1[changed], 3),
                     p_weighted = signif(p2[changed], 3)), row.names = FALSE)
  }

  ## Collect everything in one row
  res <- data.frame(
    outcome = name, n = length(y), events = sum(y),
    logLik_null = logLik(m0), AIC_null = AIC(m0), BIC_null = BIC(m0),
    logLik = logLik(m), deviance = -2 * logLik(m), AIC = AIC(m), BIC = BIC(m),
    LR_chisq = lr, LR_df = lr_df, LR_p = pchisq(lr, lr_df, lower.tail = FALSE),
    var_null = v0, ICC_null = icc(v0), MOR_null = mor(v0),
    var = v1, ICC = icc(v1), MOR = mor(v1), PCV = (v0 - v1) / v0,
    RE_LR_chisq = lr_re, RE_LR_p = 0.5 * pchisq(lr_re, 1, lower.tail = FALSE),
    singular = isSingular(m),
    R2_marginal = if (is.null(r2)) NA else r2$R2_marginal,
    R2_conditional = if (is.null(r2) || is.null(r2$R2_conditional)) NA else r2$R2_conditional,
    R2_Tjur = r2_tjur(g), max_GVIF = max(gv), max_GVIF_var = names(which.max(gv)),
    AUC_marginal = auc_(y, p_marg), AUC_lower = auc_ci[1], AUC_upper = auc_ci[3],
    AUC_conditional = auc_(y, p_cond),
    Brier = mean((y - p_marg)^2), Brier_null = mean((y - mean(y))^2),
    calib_slope = cal["slope"], calib_citl = cal["citl"],
    HL_chisq = hl$statistic, HL_p = hl$p.value,
    HL_cond_p = hoslem.test(y, p_cond, g = 10)$p.value,
    DHARMa_KS_p = ks, DHARMa_disp = dsp$statistic, DHARMa_disp_p = dsp$p.value,
    DHARMa_outlier_p = out, DHARMa_cluster_KS_p = ks_cl, DHARMa_cluster_disp_p = dsp_cl,
    boot_optimism_AUC = mean(optim[, 1]), boot_corrected_AUC = auc_glm - mean(optim[, 1]),
    boot_corrected_slope = 1 - mean(optim[, 2]),
    cv_AUC = auc_(dat[[yv]], p_cv), cv_Brier = mean((dat[[yv]] - p_cv)^2),
    cv_calib_slope = cal_cv["slope"], cv_calib_citl = cal_cv["citl"],
    wt_median_logOR_diff = median(abs(b1 - b2)), wt_max_logOR_diff = max(abs(b1 - b2)),
    wt_sig_agree = paste0(sum((p1 < 0.05) == (p2 < 0.05)), "/", length(b1)),
    row.names = NULL)

  print(t(res))

  list(summary = res, y = y, p = p_marg, roc = roc_m)
}


## ---------------------------------------------------------------------
## Run for each outcome
## ---------------------------------------------------------------------
eval_results <- list()
for (nm in names(models)) {
  eval_results[[nm]] <- evaluate_model(nm, models[[nm]]$m, models[[nm]]$data)
}

eval_table <- do.call(rbind, lapply(eval_results, `[[`, "summary"))
write.csv(eval_table, "output/eval_summary_table.csv", row.names = FALSE)


## ---------------------------------------------------------------------
## Plots for the dissertation
## ---------------------------------------------------------------------
titles <- c(less_18 = "First birth before 18", greater_34 = "Birth after 34",
            sbi = "Short birth interval", parity = "High parity")

## ROC curves (fixed-effect predictions), one panel per outcome
png("output/eval_roc_all_outcomes.png", width = 1400, height = 1000, res = 120)
par(mfrow = c(2, 2))
for (nm in names(eval_results)) {
  r <- eval_results[[nm]]
  plot(r$roc, legacy.axes = TRUE, col = "steelblue", lwd = 2, main = titles[nm])
  legend("bottomright", bty = "n",
         legend = sprintf("AUC = %.3f (%.3f-%.3f)", r$summary$AUC_marginal,
                          r$summary$AUC_lower, r$summary$AUC_upper))
}
dev.off()

## Calibration plots: observed vs predicted by decile of predicted risk
png("output/eval_calibration_all_outcomes.png", width = 1400, height = 1000, res = 120)
par(mfrow = c(2, 2))
for (nm in names(eval_results)) {
  r   <- eval_results[[nm]]
  grp <- cut(r$p, unique(quantile(r$p, seq(0, 1, 0.1))), include.lowest = TRUE)
  pred <- tapply(r$p, grp, mean)
  obs  <- tapply(r$y, grp, mean)
  lim  <- c(0, max(pred, obs) * 1.05)
  plot(pred, obs, pch = 19, col = "steelblue", xlim = lim, ylim = lim,
       xlab = "Predicted probability", ylab = "Observed proportion", main = titles[nm])
  abline(0, 1, lty = 2, col = "grey40")
  legend("topleft", bty = "n",
         legend = c(sprintf("Calibration slope = %.3f", r$summary$calib_slope),
                    sprintf("Hosmer-Lemeshow p = %.3f", r$summary$HL_p)))
}
dev.off()

par(mfrow = c(1, 1))
