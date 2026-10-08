## =====================================================================
## Final GLMMs for the four HRFB outcomes, using the variables selected
## by the GROUP LASSO (lambda chosen by BIC).
##
##   glmm_birth_before18 : hrfb_less_18    all 14 variables kept   (data = df)
##   glmm_birth_after34  : hrfb_greater_34 6 variables kept        (data = df_34, women 35+)
##   glmm_short_interval : hrfb_sbi        all 14 variables kept   (data = df)
##   glmm_high_parity    : hrfb_parity     all 14 variables kept   (data = df)
##
## Each model is a glmerMod object, so summary(glmm_...) gives the usual
## coefficient table (Estimate, Std. Error, z value, Pr(>|z|)). The odds
## ratio tables (or_...) add 95% Wald CIs. Coefficient names are the
## variable name followed by the level, e.g. provinceMpumalanga is
## Mpumalanga compared with the reference province (Western_Cape).
## Variables, levels and reference categories: output/variable_dictionary.csv
##
## STEP 5. Needs data/hrfb_data.RData from 01_data_pipeline.R.
## Takes about 5 minutes in total.
## =====================================================================

library(lme4)

load("data/hrfb_data.RData")   # df and df_34

# Same optimiser settings for every model (avoids convergence warnings)
ctrl <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))

# Helper: odds ratios, 95% Wald CIs and p-values in one table
or_table <- function(model) {
  OR <- exp(fixef(model))
  CI <- exp(confint(model, parm = "beta_", method = "Wald"))
  p  <- summary(model)$coefficients[, 4]
  data.frame(odds_ratio = round(OR, 3),
             ci_lower   = round(CI[, 1], 3),
             ci_upper   = round(CI[, 2], 3),
             p_value    = signif(p, 3))
}

# Helper: quick convergence check
check_fit <- function(model) {
  cat("Singular fit:", isSingular(model), "\n")
  cat("Convergence messages:",
      length(model@optinfo$conv$lme4$messages), "\n")
  print(VarCorr(model))
  # summary() must return the standard coefficient table with p-values
  stopifnot(ncol(coef(summary(model))) == 4)
}

## ---------------------------------------------------------------------
## 1. First birth before 18  (all women; group LASSO kept all 14)
## ---------------------------------------------------------------------
glmm_birth_before18 <- glmer(hrfb_less_18 ~ age_group + province + residence + ethnicity +
                               hh_head_sex + education + literacy + wealth_index +
                               marital_status + currently_working + ever_used_fp +
                               unmet_need + consumes_media + heard_fp_from_media +
                               (1 | cluster),
                             family = binomial(link = "logit"), data = df, control = ctrl,
                             nAGQ = 25)

check_fit(glmm_birth_before18)       # expect singular = TRUE (cluster variance ~ 0)
or_birth_before18 <- or_table(glmm_birth_before18)
print(or_birth_before18)

## ---------------------------------------------------------------------
## 2. Birth after 34  (women aged 35+ only; group LASSO kept 6 variables)
##    Dropped: province, ethnicity, hh_head_sex, education, literacy,
##             marital_status, consumes_media, heard_fp_from_media
## ---------------------------------------------------------------------
glmm_birth_after34 <- glmer(hrfb_greater_34 ~ age_group + residence + wealth_index +
                              currently_working + ever_used_fp + unmet_need +
                              (1 | cluster),
                            family = binomial(link = "logit"), data = df_34, control = ctrl,
                            nAGQ = 25)

check_fit(glmm_birth_after34)
or_birth_after34 <- or_table(glmm_birth_after34)
print(or_birth_after34)

## ---------------------------------------------------------------------
## 3. Short birth interval  (all women; group LASSO kept all 14)
## ---------------------------------------------------------------------
glmm_short_interval <- glmer(hrfb_sbi ~ age_group + province + residence + ethnicity +
                               hh_head_sex + education + literacy + wealth_index +
                               marital_status + currently_working + ever_used_fp +
                               unmet_need + consumes_media + heard_fp_from_media +
                               (1 | cluster),
                             family = binomial(link = "logit"), data = df, control = ctrl,
                             nAGQ = 25)

check_fit(glmm_short_interval)
or_short_interval <- or_table(glmm_short_interval)
print(or_short_interval)

## ---------------------------------------------------------------------
## 4. High parity  (all women; group LASSO kept all 14; nAGQ = 25 ~3 min)
## ---------------------------------------------------------------------
glmm_high_parity <- glmer(hrfb_parity ~ age_group + province + residence + ethnicity +
                            hh_head_sex + education + literacy + wealth_index +
                            marital_status + currently_working + ever_used_fp +
                            unmet_need + consumes_media + heard_fp_from_media +
                            (1 | cluster),
                          family = binomial(link = "logit"), data = df,
                          nAGQ = 25, control = ctrl)

check_fit(glmm_high_parity)
or_high_parity <- or_table(glmm_high_parity)
print(or_high_parity)

## ---------------------------------------------------------------------
## 5. Save everything
## ---------------------------------------------------------------------
save(glmm_birth_before18, glmm_birth_after34, glmm_short_interval, glmm_high_parity,
     or_birth_before18, or_birth_after34, or_short_interval, or_high_parity,
     file = "output/final_glmm_models.RData")

write.csv(or_birth_before18, "output/final_or_birth_before18.csv")
write.csv(or_birth_after34,  "output/final_or_birth_after34.csv")
write.csv(or_short_interval, "output/final_or_short_interval.csv")
write.csv(or_high_parity,    "output/final_or_high_parity.csv")
