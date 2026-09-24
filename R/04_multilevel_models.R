# =============================================================================
# 04_multilevel_models.R
# Unpenalised two-level logistic models (women nested in survey clusters) for
# each HRFB outcome, refitted on the predictors kept by glmmLasso. glmmLasso
# gives selection but no valid standard errors, so inference comes from glmer.
#
# Input : data/processed/hrfb_analysis.rds, results/lasso_selection_<outcome>.csv
# Output: results/odds_ratios_<outcome>.csv, results/model_summary.csv,
#         figures/05_odds_ratios.png
# =============================================================================

suppressPackageStartupMessages({
  library(lme4)
  library(dplyr)
  library(ggplot2)
})
source("R/03_variable_selection.R")   # OUTCOMES, PREDICTORS
source("R/02_explore.R")              # OUTCOME_LABELS

# A factor is kept if glmmLasso kept ANY of its dummy terms
kept_predictors <- function(outcome, predictors = PREDICTORS) {
  f <- file.path("results", paste0("lasso_selection_", outcome, ".csv"))
  if (!file.exists(f)) return(predictors)
  sel <- read.csv(f)
  kept_terms <- sel$term[sel$selected]
  predictors[sapply(predictors, function(p) any(startsWith(kept_terms, p)))]
}

fit_hrfb_glmm <- function(df, outcome, predictors) {
  form <- reformulate(c(predictors, "(1 | cluster)"), response = outcome)
  glmer(form, data = df, family = binomial(link = "logit"),
        control = glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5)))
}

odds_ratio_table <- function(fit, outcome) {
  est <- fixef(fit); se <- sqrt(diag(vcov(fit)))
  data.frame(outcome = outcome, term = names(est),
             OR = exp(est), lower = exp(est - 1.96 * se), upper = exp(est + 1.96 * se),
             p_value = 2 * pnorm(-abs(est / se)), row.names = NULL) %>%
    filter(term != "(Intercept)")
}

model_summary <- function(fit, outcome, n_pred) {
  tau2 <- as.numeric(VarCorr(fit)$cluster)
  data.frame(outcome = outcome, n = nobs(fit), predictors_kept = n_pred,
             cluster_variance = tau2,
             icc = tau2 / (tau2 + pi^2 / 3),          # latent-variable ICC for logit
             singular = isSingular(fit), AIC = AIC(fit))
}

plot_odds_ratios <- function(or_all) {
  or_all %>%
    filter(!startsWith(term, "age_group")) %>%   # age mostly reflects exposure time; shown in tables
    mutate(outcome = factor(OUTCOME_LABELS[outcome], levels = OUTCOME_LABELS[OUTCOMES]),
           sig = p_value < 0.05) %>%
    ggplot(aes(OR, term, colour = sig)) +
    geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +
    geom_errorbarh(aes(xmin = lower, xmax = upper), height = 0.25) +
    geom_point(size = 1.8) +
    scale_x_log10() +
    scale_colour_manual(values = c(`TRUE` = "#1F3F77", `FALSE` = "grey65"),
                        labels = c(`TRUE` = "p < 0.05", `FALSE` = "not significant")) +
    facet_wrap(~ outcome, nrow = 1) +
    labs(title = "Adjusted odds ratios from two-level logistic models (preliminary)",
         subtitle = "95% Wald intervals, log scale. Age group omitted from the plot (see tables).",
         x = "Odds ratio", y = NULL, colour = NULL) +
    theme_minimal(base_size = 10) + theme(legend.position = "bottom")
}

# ---- Run as a script ---------------------------------------------------------
if (sys.nframe() == 0) {
  df <- readRDS("data/processed/hrfb_analysis.rds")
  or_all <- list(); summ <- list()
  for (o in OUTCOMES) {
    preds <- kept_predictors(o)
    fit <- fit_hrfb_glmm(df, o, preds)
    or_tab <- odds_ratio_table(fit, o)
    write.csv(or_tab, file.path("results", paste0("odds_ratios_", o, ".csv")), row.names = FALSE)
    or_all[[o]] <- or_tab
    summ[[o]] <- model_summary(fit, o, length(preds))
  }
  summ <- bind_rows(summ); print(summ)
  write.csv(summ, "results/model_summary.csv", row.names = FALSE)
  ggsave("figures/05_odds_ratios.png", plot_odds_ratios(bind_rows(or_all)),
         width = 13, height = 8, dpi = 150, bg = "white")
}
