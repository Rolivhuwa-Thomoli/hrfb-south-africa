# =============================================================================
# 02_explore.R
# Missing-data audit, consistency checks, outcome prevalence and bivariate
# screening (chi-square / Cramer's V) of candidate predictors.
#
# Input : data/raw/ZAIR71FL.SAV, data/processed/hrfb_analysis.rds
# Output: figures/01-03_*.png, results/prevalence.csv, results/bivariate_screening.csv
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
source("R/03_variable_selection.R")   # for OUTCOMES and PREDICTORS

OUTCOME_LABELS <- c(
  hrfb_less_18    = "First birth before 18",
  hrfb_greater_34 = "Birth after age 34",
  hrfb_sbi        = "Birth interval < 24 months",
  hrfb_parity     = "More than 3 children",
  hrfb_any        = "Any HRFB",
  hrfb_multiple   = "Two or more HRFBs"
)

# ---- 1. Missing-data audit on the candidate variables ------------------------
# Variables about a partner, decision-making and access barriers are only
# asked of sub-groups (e.g. women in a union), so they are missing by design
# for most respondents rather than missing at random.
missing_audit <- function(raw) {
  candidates <- c(
    "Health insurance" = "V481", "Partner's education" = "V701", "Partner's age" = "V730",
    "Other wives" = "V505", "Age at first cohabitation" = "V511",
    "FP decision maker" = "V632", "Decides own health care" = "V743A",
    "Decides family visits" = "V743D", "Decides on money" = "V743F",
    "Barrier: permission" = "V467B", "Barrier: money" = "V467C",
    "Barrier: distance" = "V467D", "Barrier: going alone" = "V467F",
    "Education" = "V106", "Wealth index" = "V190", "Marital status" = "V501",
    "Currently working" = "V714", "Ever used FP" = "V302A", "Unmet need" = "V626A",
    "Media exposure" = "V159", "Province" = "V024", "Ethnicity" = "V131")
  data.frame(variable = names(candidates),
             pct_missing = sapply(candidates, function(v) 100 * mean(is.na(raw[[v]])))) %>%
    mutate(decision = ifelse(pct_missing > 20, "Dropped (structurally missing)", "Kept"))
}

plot_missing <- function(audit) {
  ggplot(audit, aes(reorder(variable, pct_missing), pct_missing, fill = decision)) +
    geom_col() + coord_flip() +
    geom_text(aes(label = sprintf("%.0f%%", pct_missing)), hjust = -0.15, size = 3) +
    expand_limits(y = 90) +
    scale_fill_manual(values = c("Dropped (structurally missing)" = "#C0392B", "Kept" = "#5B8BD0")) +
    labs(title = "Missing data in candidate predictors", x = NULL,
         y = "% of women with missing value", fill = NULL) +
    theme_minimal() + theme(legend.position = "bottom")
}

# ---- 2. Consistency checks ------------------------------------------------
consistency_checks <- function(df) {
  tibble::tribble(
    ~rule, ~violations,
    "Missing age at first birth only when no births",
      sum(is.na(df$age_at_first_birth) & df$children_ever_born > 0),
    "Missing age at most recent birth only when no births",
      sum(is.na(df$age_at_most_recent_birth) & df$children_ever_born > 0),
    "Missing birth interval only when fewer than 2 births",
      sum(is.na(df$min_birth_interval) & df$children_ever_born >= 2),
    "Age at first birth not greater than current age",
      sum(df$age_at_first_birth > df$age, na.rm = TRUE)
  )
}

# ---- 3. Weighted prevalence of each outcome --------------------------------
prevalence <- function(df) {
  outs <- names(OUTCOME_LABELS)
  data.frame(
    outcome = outs, label = unname(OUTCOME_LABELS[outs]),
    n_women = sapply(outs, function(o) sum(df[[o]])),
    pct_unweighted = sapply(outs, function(o) 100 * mean(df[[o]])),
    pct_weighted = sapply(outs, function(o) 100 * weighted.mean(df[[o]], df$wt)),
    row.names = NULL)
}

plot_prevalence <- function(prev) {
  prev %>%
    mutate(label = factor(label, levels = rev(label)),
           group = ifelse(outcome %in% c("hrfb_any", "hrfb_multiple"), "Summary", "Individual HRFB")) %>%
    ggplot(aes(label, pct_weighted, fill = group)) +
    geom_col(width = 0.7) +
    geom_text(aes(label = sprintf("%.1f%%", pct_weighted)), hjust = -0.15, size = 3.6) +
    coord_flip() + expand_limits(y = 38) +
    scale_fill_manual(values = c("Individual HRFB" = "#5B8BD0", "Summary" = "#1F3F77")) +
    labs(title = "High-risk fertility behaviour among South African women (15-49)",
         subtitle = "SADHS 2016, survey-weighted, n = 8,497 women", x = NULL,
         y = "% of women", fill = NULL) +
    theme_minimal() + theme(legend.position = "bottom")
}

# ---- 4. Bivariate screening: chi-square test + Cramer's V -----------------
cramers_v <- function(x, y) {
  tab <- table(x, y)
  chi <- suppressWarnings(chisq.test(tab, correct = FALSE))
  c(V = sqrt(unname(chi$statistic) / (sum(tab) * (min(dim(tab)) - 1))),
    p = chi$p.value,
    min_expected = min(chi$expected))      # check the chi-square assumption
}

bivariate_screening <- function(df, outcomes = OUTCOMES, predictors = PREDICTORS) {
  expand.grid(outcome = outcomes, predictor = predictors, stringsAsFactors = FALSE) %>%
    rowwise() %>%
    mutate(res = list(cramers_v(df[[predictor]], df[[outcome]])),
           cramers_v = res[["V"]], p_value = res[["p"]], min_expected = res[["min_expected"]]) %>%
    dplyr::select(-res) %>% ungroup()
}

plot_screening <- function(scr) {
  scr %>%
    mutate(outcome = factor(OUTCOME_LABELS[outcome], levels = OUTCOME_LABELS[OUTCOMES]),
           sig = ifelse(p_value < 0.05, sprintf("%.2f", cramers_v), sprintf("(%.2f)", cramers_v))) %>%
    ggplot(aes(outcome, reorder(predictor, cramers_v), fill = cramers_v)) +
    geom_tile(colour = "white") +
    geom_text(aes(label = sig), size = 3) +
    scale_fill_gradient(low = "#F2F6FC", high = "#1F3F77") +
    labs(title = "Bivariate association with each HRFB (Cramer's V)",
         subtitle = "Values in brackets: not significant at 5%", x = NULL, y = NULL,
         fill = "Cramer's V") +
    theme_minimal() + theme(axis.text.x = element_text(angle = 20, hjust = 1))
}

# ---- Run as a script ---------------------------------------------------------
if (sys.nframe() == 0) {
  dir.create("figures", showWarnings = FALSE); dir.create("results", showWarnings = FALSE)
  df <- readRDS("data/processed/hrfb_analysis.rds")

  if (file.exists("data/raw/ZAIR71FL.SAV")) {
    raw <- foreign::read.spss("data/raw/ZAIR71FL.SAV", to.data.frame = TRUE, max.value.labels = Inf)
    audit <- missing_audit(raw)
    write.csv(audit, "results/missing_audit.csv", row.names = FALSE)
    ggsave("figures/01_missing_data.png", plot_missing(audit), width = 8, height = 6, dpi = 150, bg = "white")
  }

  print(consistency_checks(df))

  prev <- prevalence(df)
  write.csv(prev, "results/prevalence.csv", row.names = FALSE)
  ggsave("figures/02_prevalence.png", plot_prevalence(prev), width = 8, height = 4.5, dpi = 150, bg = "white")

  scr <- bivariate_screening(df)
  write.csv(scr, "results/bivariate_screening.csv", row.names = FALSE)
  ggsave("figures/03_bivariate_screening.png", plot_screening(scr), width = 8, height = 6.5, dpi = 150, bg = "white")
}
