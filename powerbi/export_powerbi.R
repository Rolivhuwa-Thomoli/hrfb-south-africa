# =============================================================
# export_powerbi.R
# Builds the tables for the Power BI portfolio dashboard.
#
# Reads the analysis outputs (data/hrfb_data.RData, output/*.csv)
# and writes clean CSVs to powerbi/data/. Nothing in the
# dissertation scripts is changed.
#
# Only aggregated tables are written. DHS terms do not allow the
# respondent-level data to be shared, so no row in these files
# describes a single woman.
# =============================================================

library(dplyr)
library(tidyr)

out_dir <- "powerbi/data"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

load("data/hrfb_data.RData")   # df (all women), df_34 (women aged 35+)
dict <- read.csv("output/variable_dictionary.csv", stringsAsFactors = FALSE)

pretty <- function(x) gsub("_", " ", as.character(x))

# -------------------------------------------------------------
# 1. Dimension: outcomes
# -------------------------------------------------------------
dim_outcome <- tibble(
  outcome_key   = c("birth_before18", "birth_after34", "short_interval", "high_parity"),
  outcome_var   = c("hrfb_less_18", "hrfb_greater_34", "hrfb_sbi", "hrfb_parity"),
  outcome_label = c("First birth before 18", "Birth after age 34",
                    "Short birth interval (<24 months)", "High parity (>3 children)"),
  population    = c("All women 15-49", "Women aged 35+", "All women 15-49", "All women 15-49"),
  sort_order    = 1:4
)
write.csv(dim_outcome, file.path(out_dir, "dim_outcome.csv"), row.names = FALSE, na = "")

# -------------------------------------------------------------
# 2. Dimension: provinces (ISO 3166-2 codes and centroids for maps)
# -------------------------------------------------------------
dim_province <- tibble(
  province      = c("Western_Cape", "Eastern_Cape", "Northern_Cape", "Free_State",
                    "Kwazulu_Natal", "North_West", "Gauteng", "Mpumalanga", "Limpopo"),
  province_name = c("Western Cape", "Eastern Cape", "Northern Cape", "Free State",
                    "KwaZulu-Natal", "North West", "Gauteng", "Mpumalanga", "Limpopo"),
  iso_code      = c("ZA-WC", "ZA-EC", "ZA-NC", "ZA-FS", "ZA-KZN",
                    "ZA-NW", "ZA-GP", "ZA-MP", "ZA-LP"),
  latitude      = c(-33.23, -32.30, -29.05, -28.45, -28.53, -26.66, -26.27, -25.57, -23.40),
  longitude     = c( 21.86,  26.42,  21.86,  26.80,  30.90,  25.28,  28.11,  30.53,  29.42),
  country       = "South Africa"
)
write.csv(dim_province, file.path(out_dir, "dim_province.csv"), row.names = FALSE, na = "")

# -------------------------------------------------------------
# 3. Fact: weighted prevalence
#    One row per outcome x province x level of ONE breakdown
#    dimension, plus an "overall" row per province. Crossing every
#    dimension at once left cells with a single woman in them,
#    which is too fine to publish.
#    Weighted sums let DAX compute weighted prevalence for any
#    slicer combination: SUM(w_events) / SUM(w_women).
# -------------------------------------------------------------
cube_dims <- c("residence", "wealth_index", "age_group", "education",
               "marital_status", "ever_used_fp")

summarise_hrfb <- function(data, var) {
  summarise(data,
    n_women  = n(),
    n_events = sum(.data[[var]] == 1, na.rm = TRUE),
    w_women  = sum(wt),
    w_events = sum(wt * (.data[[var]] == 1), na.rm = TRUE),
    .groups  = "drop")
}

make_cube <- function(data, var, key) {
  overall <- data |> group_by(province) |> summarise_hrfb(var) |>
    mutate(dimension = "overall", level = "All women")
  by_dim <- bind_rows(lapply(cube_dims, function(d) {
    data |> group_by(province, level = .data[[d]]) |> summarise_hrfb(var) |>
      mutate(dimension = d, level = as.character(level))
  }))
  bind_rows(overall, by_dim) |>
    mutate(outcome_key = key, province = as.character(province))
}

fact_prevalence <- bind_rows(
  make_cube(df,    "hrfb_less_18",    "birth_before18"),
  make_cube(df_34, "hrfb_greater_34", "birth_after34"),
  make_cube(df,    "hrfb_sbi",        "short_interval"),
  make_cube(df,    "hrfb_parity",     "high_parity")
) |>
  mutate(category_key = paste(dimension, level, sep = "|"),
         across(c(w_women, w_events), \(x) round(x, 4))) |>
  select(outcome_key, province, category_key, dimension, level,
         n_women, n_events, w_women, w_events)
write.csv(fact_prevalence, file.path(out_dir, "fact_prevalence.csv"), row.names = FALSE, na = "")

# Breakdown dimension: labels and sort orders so slicers are not alphabetical
dim_labels <- c(overall = "Overall", residence = "Residence", wealth_index = "Wealth",
                age_group = "Age group", education = "Education",
                marital_status = "Marital status", ever_used_fp = "Ever used family planning")
dim_category <- bind_rows(
  tibble(dimension = "overall", level = "All women", level_label = "All women", level_order = 1L),
  bind_rows(lapply(cube_dims, function(v) {
    tibble(dimension = v, level = levels(df[[v]]),
           level_label = pretty(levels(df[[v]])), level_order = seq_along(levels(df[[v]])))
  }))
) |>
  mutate(category_key    = paste(dimension, level, sep = "|"),
         dimension_label = unname(dim_labels[dimension]),
         dimension_order = match(dimension, names(dim_labels)),
         .before = 1)
write.csv(dim_category, file.path(out_dir, "dim_category.csv"), row.names = FALSE, na = "")

# -------------------------------------------------------------
# 4. Fact: adjusted odds ratios from the final GLMMs (05_final_glmm.R)
# -------------------------------------------------------------
predictors <- dict$variable[dict$role == "predictor"]

split_term <- function(term) {
  v <- vapply(term, function(t) {
    hit <- predictors[startsWith(t, predictors)]
    if (length(hit)) hit[which.max(nchar(hit))] else NA_character_
  }, character(1))
  tibble(variable = v, level = ifelse(is.na(v), NA, substring(term, nchar(v) + 1)))
}

fact_or <- bind_rows(lapply(dim_outcome$outcome_key, function(k) {
  read.csv(sprintf("output/final_or_%s.csv", k), stringsAsFactors = FALSE) |>
    rename(term = 1) |>
    mutate(outcome_key = k, .before = 1)
})) |>
  filter(term != "(Intercept)")
fact_or <- bind_cols(fact_or, split_term(fact_or$term)) |>
  left_join(dict |> select(variable, variable_label = label, reference_level), by = "variable") |>
  mutate(level_label  = pretty(level),
         significant  = if_else(p_value < 0.05, "Yes", "No"),
         direction    = case_when(p_value >= 0.05 ~ "Not significant",
                                  odds_ratio > 1   ~ "Higher risk",
                                  TRUE             ~ "Lower risk"),
         log_or       = round(log(odds_ratio), 4),
         reference_level = case_when(variable == "age_group" & outcome_key == "birth_after34" ~ "35_to_39",
                                     variable == "age_group" ~ "less_than_24",
                                     TRUE ~ reference_level)) |>
  select(outcome_key, variable, variable_label, level, level_label, reference_level,
         odds_ratio, ci_lower, ci_upper, p_value, log_or, significant, direction)
write.csv(fact_or, file.path(out_dir, "fact_odds_ratios.csv"), row.names = FALSE, na = "")

# -------------------------------------------------------------
# 5. Fact: chi-square screening (03_bivariate_chisq.R)
# -------------------------------------------------------------
chisq_key <- c(hrfb_less_18 = "birth_before18", hrfb_greater_34 = "birth_after34",
               hrfb_sbi = "short_interval", hrfb_parity = "high_parity")
fact_chisq <- read.csv("output/chisq_summary.csv", stringsAsFactors = FALSE) |>
  filter(outcome %in% names(chisq_key)) |>   # drop hrfb_any / hrfb_multiple (not modelled)
  mutate(outcome_key = chisq_key[outcome], .before = 1) |>
  select(-outcome) |>
  left_join(dict |> select(variable, variable_label = label), by = "variable")
write.csv(fact_chisq, file.path(out_dir, "fact_chisq.csv"), row.names = FALSE, na = "")

# -------------------------------------------------------------
# 6. Fact: model performance (08_model_evaluation.R)
# -------------------------------------------------------------
eval_key <- c(less_18 = "birth_before18", greater_34 = "birth_after34",
              sbi = "short_interval", parity = "high_parity")
fact_model <- read.csv("output/eval_summary_table.csv", stringsAsFactors = FALSE) |>
  transmute(outcome_key = eval_key[outcome], n, events,
            auc = AUC_marginal, auc_lower = AUC_lower, auc_upper = AUC_upper,
            auc_cv = cv_AUC, brier = Brier, brier_null = Brier_null,
            calib_slope_cv = cv_calib_slope, icc_null = ICC_null, mor_null = MOR_null,
            icc = ICC, mor = MOR, r2_marginal = R2_marginal, r2_tjur = R2_Tjur)
write.csv(fact_model, file.path(out_dir, "fact_model_performance.csv"), row.names = FALSE, na = "")

# -------------------------------------------------------------
# 7. Dimension: variables (for tooltips and the data dictionary page)
# -------------------------------------------------------------
write.csv(dict |> filter(role %in% c("outcome", "predictor")), file.path(out_dir, "dim_variable.csv"), row.names = FALSE, na = "")

cat("Wrote", length(list.files(out_dir)), "files to", out_dir, "\n")
cat("Prevalence rows:", nrow(fact_prevalence),
    " | smallest cell n:", min(fact_prevalence$n_women), "\n")
