## =====================================================================
## STEP 1 of the HRFB analysis: build the analysis data set
##
## Run order (open "Data Analysis.Rproj" first, so the working folder is set):
##   01_data_pipeline.R         -> data/hrfb_data.RData (df, df_34)
##   02_eda.R                   -> data summaries in the console (skim, levels)
##   03_bivariate_chisq.R       -> output/chisq_summary.csv
##   04_group_lasso_selection.R -> output/group_bic_*.RData + plots
##   05_final_glmm.R            -> output/glmm_group_lasso_models.RData + CSVs
##   06_selection_table.R       -> output/tab_selection.tex
##   07_forest_plot.R           -> odds ratio forest plots
##
## Old scripts (foreign_ver.R, glmmlasso_*.R, ...) are kept in archive/.
## =====================================================================

library(foreign)
library(dplyr)

spss_data <- read.spss("ZAIR71SV/ZAIR71FL.SAV",
                       to.data.frame = TRUE, max.value.labels = Inf)

# Answers that count as media exposure
media_yes <- c("Less than once a week", "At least once a week", "Almost every day")

df <- spss_data %>%

  # ---- 1. Keep only the variables we use, and rename them straight away ----
  dplyr::select(
    # survey design
    cluster            = V001,  # cluster number
    wt                 = V005,  # women's sample weight (x 1,000,000)
    psu                = V021,  # primary sampling unit
    strata             = V023,  # stratification used in sample design

    # demographic
    dob_cmc            = V011,  # date of birth (CMC)
    age                = V012,  # current age
    age_group          = V013,  # age in 5-year groups
    province           = V024,  # region
    residence          = V025,  # urban / rural
    ethnicity          = V131,  # ethnicity
    hh_members         = V136,  # number of household members
    hh_head_sex        = V151,  # sex of household head

    # socio-economic
    education          = V106,  # highest educational level
    educ_years         = V133,  # education in single years
    literacy           = V155,  # literacy
    wealth_index       = V190,  # wealth index
    currently_working  = V714,  # currently working
    occupation         = V717,  # occupation (grouped)

    # media / information
    reads_newspaper    = V157,
    listens_radio      = V158,
    watches_tv         = V159,
    owns_mobile        = V169A,
    uses_internet      = V171A,
    heard_fp_radio     = V384A,
    heard_fp_tv        = V384B,
    heard_fp_paper     = V384C,

    # marriage / sexual debut
    marital_status     = V501,  # current marital status
    age_first_sex      = V531,  # age at first sex

    # family planning
    ever_used_fp       = V302A, # ever used anything to delay/avoid pregnancy
    unmet_need         = V626A, # unmet need for contraception

    # fertility history
    children_ever_born = V201,  # total children ever born
    age_at_first_birth = V212,  # age at first birth
    dob_most_recent    = B3.01, # date of birth of most recent child (CMC)
    starts_with("B11.")         # preceding birth intervals (months), one per child
  ) %>%

  # ---- 2. Shortest birth interval for each woman (row by row) ----
  # Women with fewer than 2 children have no intervals, so all B11 values are NA.
  rowwise() %>%
  mutate(
    min_birth_interval = if (all(is.na(c_across(starts_with("B11."))))) {
      NA_real_
    } else {
      min(c_across(starts_with("B11.")), na.rm = TRUE)
    }
  ) %>%
  ungroup() %>%

  # ---- 3. Outcome variables (1 = high-risk, 0 = not; missing counts as 0) ----
  mutate(
    age_at_most_recent_birth = floor((dob_most_recent - dob_cmc) / 12),

    hrfb_less_18    = ifelse(!is.na(age_at_first_birth) & age_at_first_birth < 18, 1, 0),
    hrfb_greater_34 = ifelse(!is.na(age_at_most_recent_birth) & age_at_most_recent_birth > 34, 1, 0),
    hrfb_sbi        = ifelse(!is.na(min_birth_interval) & min_birth_interval < 24, 1, 0),
    hrfb_parity     = ifelse(!is.na(children_ever_born) & children_ever_born > 3, 1, 0),

    n_hrfb        = hrfb_less_18 + hrfb_greater_34 + hrfb_sbi + hrfb_parity,
    hrfb_any      = ifelse(n_hrfb >= 1, 1, 0),  # at least one HRFB
    hrfb_multiple = ifelse(n_hrfb >= 2, 1, 0)   # more than one HRFB
  ) %>%

  # ---- 4. Survey design variables ----
  mutate(
    wt      = wt / 1e6,          # DHS stores weights multiplied by 1,000,000
    cluster = factor(cluster)
  ) %>%

  # ---- 5. Recode predictors (first level listed = reference category) ----
  mutate(
    age_group = case_when(
      age_group %in% c("15-19", "20-24")        ~ "less_than_24",
      age_group == "25-29"                      ~ "25_to_29",
      age_group == "30-34"                      ~ "30_to_34",
      age_group == "35-39"                      ~ "35_to_39",
      age_group %in% c("40-44", "45-49", "50+") ~ "40_and_higher"
    ),
    age_group = factor(age_group, levels = c("less_than_24", "25_to_29", "30_to_34",
                                             "35_to_39", "40_and_higher")),

    province = case_when(
      province == "Western Cape"  ~ "Western_Cape",
      province == "Eastern Cape"  ~ "Eastern_Cape",
      province == "Northern Cape" ~ "Northern_Cape",
      province == "Free State"    ~ "Free_State",
      province == "Kwazulu-Natal" ~ "Kwazulu_Natal",
      province == "North West"    ~ "North_West",
      province == "Gauteng"       ~ "Gauteng",
      province == "Mpumalanga"    ~ "Mpumalanga",
      province == "Limpopo"       ~ "Limpopo"
    ),
    province = factor(province, levels = c("Western_Cape", "Eastern_Cape", "Northern_Cape",
                                           "Free_State", "Kwazulu_Natal", "North_West",
                                           "Gauteng", "Mpumalanga", "Limpopo")),

    ethnicity = case_when(
      ethnicity == "Black/African"                          ~ "Black_or_African",
      ethnicity == "Coloured"                               ~ "Coloured",
      ethnicity %in% c("White", "Indian/Asian", "Other")    ~ "White_or_Other"
    ),
    ethnicity = factor(ethnicity, levels = c("Black_or_African", "Coloured", "White_or_Other")),

    education = case_when(
      education == "No education" ~ "No_education",
      education == "Primary"      ~ "Primary",
      education == "Secondary"    ~ "Secondary",
      education == "Higher"       ~ "Higher"
    ),
    education = factor(education, levels = c("No_education", "Primary", "Secondary", "Higher")),

    # "Inconsistent" becomes NA, the rest become numbers
    educ_years = as.numeric(ifelse(educ_years == "Inconsistent", NA, as.character(educ_years))),

    literacy = case_when(
      literacy %in% c("Cannot read at all", "Blind/visually impaired")                     ~ "Cannot_read",
      literacy %in% c("Able to read only parts of sentence", "No card with required language") ~ "Reads_partially",
      literacy == "Able to read whole sentence"                                            ~ "Reads_fully"
    ),
    literacy = factor(literacy, levels = c("Cannot_read", "Reads_partially", "Reads_fully")),

    wealth_index = case_when(
      wealth_index %in% c("Poorest", "Poorer") ~ "Poor",
      wealth_index == "Middle"                 ~ "Middle",
      wealth_index %in% c("Richer", "Richest") ~ "Rich"
    ),
    wealth_index = factor(wealth_index, levels = c("Poor", "Middle", "Rich")),

    marital_status = case_when(
      marital_status == "Never in union"      ~ "Never_in_union",
      marital_status == "Living with partner" ~ "Living_with_partner",
      marital_status == "Married"             ~ "Married",
      marital_status %in% c("Widowed", "Divorced",
                            "No longer living together/separated") ~ "Widowed_or_Divorced_or_Separated"
    ),
    marital_status = factor(marital_status, levels = c("Never_in_union", "Living_with_partner",
                                                       "Married", "Widowed_or_Divorced_or_Separated")),

    ever_used_fp = factor(ifelse(ever_used_fp == "No", "No", "Yes"), levels = c("No", "Yes")),

    unmet_need = case_when(
      unmet_need %in% c("No unmet need", "Not married and no sex in last 30 days",
                        "Never had sex", "Infecund, menopausal") ~ "No_unmet_need",
      unmet_need == "Using for spacing"       ~ "Using_for_spacing",
      unmet_need == "Using for limiting"      ~ "Using_for_limiting",
      unmet_need == "Unmet need for spacing"  ~ "Unmet_need_for_spacing",
      unmet_need == "Unmet need for limiting" ~ "Unmet_need_for_limiting"
    ),
    unmet_need = factor(unmet_need, levels = c("No_unmet_need", "Using_for_spacing",
                                               "Using_for_limiting", "Unmet_need_for_spacing",
                                               "Unmet_need_for_limiting")),

    # Any exposure to newspaper, radio or TV (anything other than "Not at all")
    consumes_media = ifelse(reads_newspaper %in% media_yes |
                            listens_radio   %in% media_yes |
                            watches_tv      %in% media_yes,
                            "Yes", "No"),
    consumes_media = factor(consumes_media, levels = c("No", "Yes")),

    # Heard about family planning on radio, TV or in a newspaper
    heard_fp_from_media = ifelse(heard_fp_radio == "Yes" | heard_fp_tv == "Yes" | heard_fp_paper == "Yes",
                                 "Yes", "No"),
    heard_fp_from_media = factor(heard_fp_from_media, levels = c("No", "Yes"))
  ) %>%

  # ---- 6. Final columns, in the order we want them ----
  # (this also drops helper columns such as B11.*, dob_cmc, min_birth_interval)
  dplyr::select(
    hrfb_less_18, hrfb_greater_34, hrfb_sbi, hrfb_parity, hrfb_any, hrfb_multiple,
    wt, cluster, psu, strata,
    age, age_group, hh_members, children_ever_born,
    province, residence, ethnicity, hh_head_sex,
    education, educ_years, literacy, wealth_index,
    currently_working, occupation, marital_status,
    ever_used_fp, unmet_need,
    reads_newspaper, listens_radio, watches_tv, owns_mobile, uses_internet,
    heard_fp_radio, heard_fp_tv, heard_fp_paper,
    age_first_sex,
    consumes_media, heard_fp_from_media
  ) %>%

  # ---- 7. Factor levels with zero / few women ----
  # "Agricultural - self employed" has only 5 women, so merge it with
  # "Agricultural - unskilled" (117 women) into one "Agricultural" level.
  mutate(
    occupation = ifelse(grepl("^Agricultural", occupation), "Agricultural",
                        as.character(occupation)),
    occupation = factor(occupation, levels = c("Not working",
                                               "Professional/technical/managerial",
                                               "Clerical", "Agricultural",
                                               "Household and domestic", "Services",
                                               "Skilled manual", "Unskilled manual",
                                               "Don't know"))
  ) %>%
  # Remove levels with 0 women, which make chi-square tests return NaN:
  # "Almost every day" (newspaper, radio, TV), "Yes, can't establish when"
  # (internet), "Don't know" (age at first sex), and the empty occupations.
  droplevels()

# Women aged 35+ only: hrfb_greater_34 (birth after 34) is only possible for them.
# age_group is left with two levels: 35_to_39 (reference) and 40_and_higher.
df_34 <- df %>%
  filter(age >= 35) %>%
  droplevels()

# Check the levels
lapply(df[sapply(df, is.factor)], levels)


# ---- 8. Report levels that are still small ----
# For each factor, lists the levels with fewer than min_n women, or fewer than
# min_cases women with the outcome (= 1). Such levels give unstable estimates
# and chi-square warnings. If new problems appear, add a fix to step 7 above.
check_sparse_levels <- function(data, outcomes, min_n = 30, min_cases = 5) {
  factor_vars <- setdiff(names(data)[sapply(data, is.factor)],
                         c("cluster", "strata", "age_first_sex"))
  out <- data.frame()
  for (var in factor_vars) {
    for (outcome in outcomes) {
      tab <- data %>%
        group_by(level = .data[[var]]) %>%
        summarise(n = n(), cases = sum(.data[[outcome]]), .groups = "drop") %>%
        filter(n < min_n | cases < min_cases)
      if (nrow(tab) > 0) {
        out <- rbind(out, data.frame(variable = var, outcome = outcome, tab))
      }
    }
  }
  out
}

outcomes_all <- c("hrfb_less_18", "hrfb_sbi", "hrfb_parity", "hrfb_any", "hrfb_multiple")

cat("\nSparse levels, all women (n =", nrow(df), "):\n")
print(check_sparse_levels(df, outcomes_all))

cat("\nSparse levels, women aged 35+ (n =", nrow(df_34), "):\n")
print(check_sparse_levels(df_34, "hrfb_greater_34"))


# ---- 9. Save for the next scripts ----
dir.create("data", showWarnings = FALSE)
save(df, df_34, file = "data/hrfb_data.RData")
