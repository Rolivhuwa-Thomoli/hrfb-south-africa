# =============================================================================
# 01_prepare_data.R
# Build the analysis dataset from the 2016 South Africa DHS Individual Recode.
#
# Input : data/raw/ZAIR71FL.SAV  (not included - see data/README.md)
# Output: data/processed/hrfb_analysis.rds  (git-ignored)
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

# Outcome thresholds (WHO / DHS definitions of high-risk fertility behaviour)
HRFB_YOUNG_AGE  <- 18   # first birth before age 18
HRFB_OLD_AGE    <- 34   # a birth after age 34
HRFB_SHORT_INT  <- 24   # a birth interval shorter than 24 months
HRFB_HIGH_PAR   <- 3    # more than 3 children ever born

# Age at first birth below this is treated as a data-entry error
MIN_PLAUSIBLE_FIRST_BIRTH_AGE <- 12

prepare_hrfb_data <- function(raw) {

  # ---- 1. Derive fertility-history quantities --------------------------------
  b11 <- as.matrix(raw[, grep("^B11\\.", names(raw))])      # preceding birth intervals (months)
  min_interval <- suppressWarnings(apply(b11, 1, min, na.rm = TRUE))
  min_interval[!is.finite(min_interval) | is.na(raw$V201) | raw$V201 < 2] <- NA

  df <- raw %>%
    transmute(
      # survey design
      cluster  = factor(V001),
      psu      = V021,
      strata   = V023,
      wt       = V005 / 1e6,                       # DHS weights are stored x 1,000,000

      # fertility history
      children_ever_born       = V201,
      age_at_first_birth       = V212,
      age_at_most_recent_birth = floor((B3.01 - V011) / 12),   # CMC dates -> years
      min_birth_interval       = min_interval,

      # demographic
      age = V012, age_group = V013, province = V024, residence = V025,
      ethnicity = V131, hh_members = V136, hh_head_sex = V151,

      # socio-economic
      education = V106, educ_years = V133, literacy = V155, wealth_index = V190,
      currently_working = V714, occupation = V717, marital_status = V501,

      # family planning
      ever_used_fp = V302A, unmet_need = V626A,

      # media
      reads_newspaper = V157, listens_radio = V158, watches_tv = V159,
      heard_fp_radio = V384A, heard_fp_tv = V384B, heard_fp_paper = V384C
    )

  # ---- 2. Remove implausible records ----------------------------------------
  # e.g. a respondent recorded as giving birth at age 3: almost certainly a
  # date-of-birth entry error. Only the implausibly LOW tail is removed;
  # late first births (30+) are genuine and kept.
  n_before <- nrow(df)
  df <- df %>%
    filter(is.na(age_at_first_birth) | age_at_first_birth >= MIN_PLAUSIBLE_FIRST_BIRTH_AGE)
  message(sprintf("Removed %d record(s) with age at first birth < %d",
                  n_before - nrow(df), MIN_PLAUSIBLE_FIRST_BIRTH_AGE))

  # ---- 3. Outcome variables --------------------------------------------------
  # Women with no births cannot exhibit any HRFB and are coded 0 (not missing).
  flag <- function(cond) as.integer(!is.na(cond) & cond)

  df <- df %>%
    mutate(
      hrfb_less_18    = flag(age_at_first_birth < HRFB_YOUNG_AGE),
      hrfb_greater_34 = flag(age_at_most_recent_birth > HRFB_OLD_AGE),
      hrfb_sbi        = flag(min_birth_interval < HRFB_SHORT_INT),
      hrfb_parity     = flag(children_ever_born > HRFB_HIGH_PAR),
      hrfb_count      = hrfb_less_18 + hrfb_greater_34 + hrfb_sbi + hrfb_parity,
      hrfb_any        = as.integer(hrfb_count >= 1),
      hrfb_multiple   = as.integer(hrfb_count >= 2)
    )

  # ---- 4. Recode predictors (collapse sparse levels, set reference groups) --
  df <- df %>%
    mutate(
      age_group = factor(case_when(
        age_group == "15-19" ~ "15_19", age_group == "20-24" ~ "20_24",
        age_group == "25-29" ~ "25_29", age_group == "30-34" ~ "30_34",
        age_group == "35-39" ~ "35_39", TRUE ~ "40_plus"),
        levels = c("15_19", "20_24", "25_29", "30_34", "35_39", "40_plus")),

      province = factor(gsub("[ -]", "_", as.character(province)),
        levels = c("Western_Cape", "Eastern_Cape", "Northern_Cape", "Free_State",
                   "Kwazulu_Natal", "North_West", "Gauteng", "Mpumalanga", "Limpopo")),

      ethnicity = factor(case_when(
        ethnicity == "Black/African" ~ "Black_African",
        ethnicity == "White"         ~ "White",
        ethnicity == "Coloured"      ~ "Coloured",
        TRUE                         ~ "Indian_Asian_Other"),
        levels = c("Black_African", "White", "Coloured", "Indian_Asian_Other")),

      education = factor(gsub(" ", "_", as.character(education)),
        levels = c("No_education", "Primary", "Secondary", "Higher")),

      educ_years = suppressWarnings(as.numeric(as.character(educ_years))),

      literacy = factor(case_when(
        literacy %in% c("Cannot read at all", "Blind/visually impaired") ~ "Cannot_read",
        literacy %in% c("Able to read only parts of sentence",
                        "No card with required language")               ~ "Reads_partially",
        literacy == "Able to read whole sentence"                       ~ "Reads_fully"),
        levels = c("Cannot_read", "Reads_partially", "Reads_fully")),

      # 5 quintiles -> 3 groups, poorest as reference
      wealth_index = factor(case_when(
        wealth_index %in% c("Poorest", "Poorer") ~ "Poor",
        wealth_index == "Middle"                 ~ "Middle",
        TRUE                                     ~ "Rich"),
        levels = c("Poor", "Middle", "Rich")),

      marital_status = factor(case_when(
        marital_status == "Never in union"      ~ "Never_in_union",
        marital_status == "Living with partner" ~ "Living_with_partner",
        marital_status == "Married"             ~ "Married",
        TRUE                                    ~ "Formerly_in_union"),   # widowed/divorced/separated
        levels = c("Never_in_union", "Living_with_partner", "Married", "Formerly_in_union")),

      ever_used_fp = factor(ifelse(ever_used_fp == "No", "No", "Yes"), levels = c("No", "Yes")),

      unmet_need = factor(case_when(
        unmet_need == "Using for spacing"       ~ "Using_for_spacing",
        unmet_need == "Using for limiting"      ~ "Using_for_limiting",
        unmet_need == "Unmet need for spacing"  ~ "Unmet_need_spacing",
        unmet_need == "Unmet need for limiting" ~ "Unmet_need_limiting",
        TRUE                                    ~ "No_unmet_need"),
        levels = c("No_unmet_need", "Using_for_spacing", "Using_for_limiting",
                   "Unmet_need_spacing", "Unmet_need_limiting")),

      # any exposure = anything other than "Not at all"
      consumes_media = factor(ifelse(
        reads_newspaper != "Not at all" | listens_radio != "Not at all" |
          watches_tv != "Not at all", "Yes", "No"), levels = c("No", "Yes")),

      heard_fp_from_media = factor(ifelse(
        heard_fp_radio == "Yes" | heard_fp_tv == "Yes" | heard_fp_paper == "Yes",
        "Yes", "No"), levels = c("No", "Yes"))
    )

  df
}

# ---- Run as a script ---------------------------------------------------------
if (sys.nframe() == 0) {
  library(foreign)
  raw <- read.spss("data/raw/ZAIR71FL.SAV", to.data.frame = TRUE, max.value.labels = Inf)
  df <- prepare_hrfb_data(raw)
  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  saveRDS(df, "data/processed/hrfb_analysis.rds")
  message("Saved ", nrow(df), " women x ", ncol(df), " variables")
}
