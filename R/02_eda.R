## =====================================================================
## STEP 2: exploratory data analysis of the analysis data set.
## Needs data/hrfb_data.RData from 01_data_pipeline.R.
## Prints to the console only - nothing is saved.
## =====================================================================

library(dplyr)
library(skimr)

load("data/hrfb_data.RData")   # df (all women) and df_34 (women aged 35+)

# Factor variables to look at (the survey design variables have hundreds
# of levels, so they are left out)
factor_vars <- setdiff(names(df)[sapply(df, is.factor)], c("cluster", "strata"))

outcomes <- c("hrfb_less_18", "hrfb_greater_34", "hrfb_sbi",
              "hrfb_parity", "hrfb_any", "hrfb_multiple")


## ---------------------------------------------------------------------
## 1. Overview: type, missing values, and summary of every variable
## ---------------------------------------------------------------------
cat("df:", nrow(df), "women,", ncol(df), "variables\n")
cat("df_34:", nrow(df_34), "women aged 35+\n")

skim(df)
skim(df_34)


## ---------------------------------------------------------------------
## 2. Factor levels (first level = reference category in the models)
## ---------------------------------------------------------------------
lapply(df[factor_vars], levels)

# Number and percentage of women in each level
for (var in factor_vars) {
  cat("\n----", var, "----\n")
  n <- table(df[[var]], useNA = "ifany")
  print(cbind(n = n, pct = round(100 * prop.table(n), 1)))
}

# Age group has only two levels among women aged 35+
levels(df_34$age_group)
table(df_34$age_group)


## ---------------------------------------------------------------------
## 3. Outcomes: how common is each HRFB?
##    Unweighted = share of the sample; weighted = estimate for all
##    South African women, using the DHS sample weight wt.
##    hrfb_greater_34 is shown for women aged 35+ (df_34) only.
## ---------------------------------------------------------------------
prevalence <- data.frame()
for (outcome in outcomes) {
  data <- if (outcome == "hrfb_greater_34") df_34 else df
  prevalence <- rbind(prevalence, data.frame(
    outcome      = outcome,
    n            = nrow(data),
    cases        = sum(data[[outcome]]),
    pct          = round(100 * mean(data[[outcome]]), 1),
    pct_weighted = round(100 * weighted.mean(data[[outcome]], data$wt), 1)
  ))
}
print(prevalence)

# How many HRFBs each woman has (0 to 4)
df %>%
  mutate(n_hrfb = hrfb_less_18 + hrfb_greater_34 + hrfb_sbi + hrfb_parity) %>%
  count(n_hrfb) %>%
  mutate(pct = round(100 * n / sum(n), 1))


## ---------------------------------------------------------------------
## 4. Numeric variables by group
## ---------------------------------------------------------------------
df %>%
  dplyr::select(residence, age, hh_members, children_ever_born, educ_years) %>%
  group_by(residence) %>%
  skim()

df %>%
  dplyr::select(province, age, children_ever_born) %>%
  group_by(province) %>%
  skim()
