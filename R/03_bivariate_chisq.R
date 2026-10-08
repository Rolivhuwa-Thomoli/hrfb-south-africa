## =====================================================================
## STEP 3: bivariate analysis - chi-square test of every factor against
## every HRFB outcome. Needs data/hrfb_data.RData from 01_data_pipeline.R.
## =====================================================================

library(dplyr)
library(vcd)   # for assocstats()

load("data/hrfb_data.RData")   # df and df_34

# ---- Settings -----------------------------------------------------------------
outcomes <- c("hrfb_less_18", "hrfb_greater_34", "hrfb_sbi",
              "hrfb_parity", "hrfb_any", "hrfb_multiple")

# All factor variables except the survey design variables (cluster, strata)
# and age_first_sex (too many levels to be useful here)
factor_vars <- names(df)[sapply(df, is.factor)]
factor_vars <- setdiff(factor_vars, c("cluster", "strata", "age_first_sex"))

# Empty table to collect one summary row per test
summary_table <- data.frame()

# ---- Loop over every outcome and every factor ------------------------------------
for (outcome in outcomes) {

  # hrfb_greater_34 is only possible for women aged 35+, so use df_34 for it
  # (empty levels were already removed in 01_data_pipeline.R)
  if (outcome == "hrfb_greater_34") {
    data <- df_34
  } else {
    data <- df
  }

  for (var in factor_vars) {

    cat("\n==============================================================\n")
    cat("Outcome:", outcome, "  |  Variable:", var, "\n")
    cat("==============================================================\n")

    # 1. Counts and proportions per level
    props <- data %>%
      group_by(.data[[var]]) %>%
      summarise(n          = n(),
                hrfb_prop  = mean(.data[[outcome]]),
                hrfb_cases = sum(.data[[outcome]]))
    print(props)

    # 2. Chi-square test and standardised residuals
    tlb        <- table(data[[var]], data[[outcome]])
    chisq_test <- chisq.test(tlb)
    print(chisq_test)
    cat("\nStandardised residuals:\n")
    print(round(chisq_test$stdres, 2))

    # 3. Association measures (phi, contingency coefficient, Cramer's V)
    assoc <- assocstats(tlb)
    print(assoc)

    # 4. Warn if the chi-square approximation may be unreliable
    small_expected <- sum(chisq_test$expected < 5)
    if (small_expected > 0) {
      cat("WARNING:", small_expected, "cell(s) have expected count < 5\n")
    }

    # 5. Save one summary row
    summary_table <- rbind(summary_table, data.frame(
      outcome        = outcome,
      variable       = var,
      chi_sq         = round(unname(chisq_test$statistic), 2),
      df             = unname(chisq_test$parameter),
      p_value        = signif(chisq_test$p.value, 3),
      cramers_v      = round(assoc$cramer, 3),
      small_expected = small_expected
    ))
  }
}

# ---- Overview of all tests ----------------------------------------------------------
summary_table$significant <- ifelse(summary_table$p_value < 0.05, "Yes", "No")
print(summary_table)

# Save it for the write-up
dir.create("output", showWarnings = FALSE)
write.csv(summary_table, "output/chisq_summary.csv", row.names = FALSE)
