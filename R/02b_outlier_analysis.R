## =====================================================================
## STEP 2b: outlier and plausibility checks on the fertility histories.
## Reads the raw DHS file (the analysis data set drops the raw ages and
## intervals) plus data/hrfb_data.RData from 01_data_pipeline.R.
##
## 1. Distributions of the four quantities the outcomes are built from,
##    with Tukey fences (1.5 x IQR) and biological plausibility limits.
## 2. A table of every rule, how many women break it, and the decision.
## 3. Sensitivity check: refit the first-birth-before-18 model without
##    the implausible first births and compare the odds ratios.
##
## Output: figures/07_outliers.png, results/outlier_audit.csv,
##         results/outlier_sensitivity.csv
## =====================================================================

library(foreign)
library(dplyr)
library(tidyr)
library(ggplot2)
library(lme4)

if (!exists("sav_path"))   sav_path   <- "ZAIR71SV/ZAIR71FL.SAV"
if (!exists("rdata_path")) rdata_path <- "data/hrfb_data.RData"

raw <- read.spss(sav_path, to.data.frame = TRUE, max.value.labels = Inf)
load(rdata_path)   # df, df_34 (same women, same order as the raw file)
stopifnot(nrow(raw) == nrow(df))

as_num <- function(x) suppressWarnings(as.numeric(as.character(x)))
b11 <- raw[, grepl("^B11\\.", names(raw))]
b11[] <- lapply(b11, as_num)

fert <- data.frame(
  age                = as_num(raw$V012),
  children_ever_born = as_num(raw$V201),
  age_first_birth    = as_num(raw$V212),
  age_recent_birth   = floor((as_num(raw$B3.01) - as_num(raw$V011)) / 12),
  shortest_interval  = apply(b11, 1, function(r) if (all(is.na(r))) NA else min(r, na.rm = TRUE))
)

## ---------------------------------------------------------------------
## 1. Tukey fences for each quantity
## ---------------------------------------------------------------------
fence <- function(x) {
  q <- quantile(x, c(0.25, 0.75), na.rm = TRUE); iqr <- diff(q)
  c(lower = unname(q[1] - 1.5 * iqr), upper = unname(q[2] + 1.5 * iqr))
}
vars <- c(age_first_birth = "Age at first birth (years)",
          age_recent_birth = "Age at most recent birth (years)",
          shortest_interval = "Shortest birth interval (months)",
          children_ever_born = "Children ever born")
fences <- sapply(names(vars), function(v) fence(fert[[v]]))

## ---------------------------------------------------------------------
## 2. Rules, counts and decisions
## ---------------------------------------------------------------------
n_out <- function(cond) sum(cond, na.rm = TRUE)
audit <- data.frame(
  check = c(
    "Age at first birth below 12 (biologically implausible)",
    "Age at first birth outside Tukey fences",
    "Age at first birth above current age",
    "Age at most recent birth above 49",
    "Age at most recent birth outside Tukey fences",
    "Shortest birth interval of 0-8 months (twins or recording error)",
    "Shortest birth interval outside Tukey fences",
    "Children ever born outside Tukey fences",
    "Children ever born above 12"
  ),
  n_women = c(
    n_out(fert$age_first_birth < 12),
    n_out(fert$age_first_birth < fences["lower", "age_first_birth"] |
          fert$age_first_birth > fences["upper", "age_first_birth"]),
    n_out(fert$age_first_birth > fert$age),
    n_out(fert$age_recent_birth > 49),
    n_out(fert$age_recent_birth < fences["lower", "age_recent_birth"] |
          fert$age_recent_birth > fences["upper", "age_recent_birth"]),
    n_out(fert$shortest_interval < 9),
    n_out(fert$shortest_interval < fences["lower", "shortest_interval"] |
          fert$shortest_interval > fences["upper", "shortest_interval"]),
    n_out(fert$children_ever_born < fences["lower", "children_ever_born"] |
          fert$children_ever_born > fences["upper", "children_ever_born"]),
    n_out(fert$children_ever_born > 12)
  )
)
audit$pct_of_women <- round(100 * audit$n_women / nrow(fert), 2)
print(audit)

## ---------------------------------------------------------------------
## 3. Figure: distributions with the flagged values highlighted
## ---------------------------------------------------------------------
long <- fert %>%
  select(all_of(names(vars))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "value") %>%
  filter(!is.na(value)) %>%
  mutate(lo = fences["lower", variable], hi = fences["upper", variable],
         flag = ifelse(value < lo | value > hi, "Outside Tukey fences", "Within fences"),
         variable = factor(vars[variable], levels = vars))

# Biological plausibility limit, drawn on the age-at-first-birth panel only
limit <- data.frame(variable = factor(vars["age_first_birth"], levels = vars), x = 12,
                    label = paste0(n_out(fert$age_first_birth < 12),
                                   " women report a\nfirst birth before 12"))

p <- ggplot(long, aes(x = value, fill = flag)) +
  geom_histogram(binwidth = 1, boundary = 0) +
  geom_vline(data = limit, aes(xintercept = x), linetype = "dashed", colour = "grey30") +
  geom_text(data = limit, aes(x = x - 0.5, y = Inf, label = label), inherit.aes = FALSE,
            hjust = 1, vjust = 1.5, size = 3.4, colour = "grey20") +
  facet_wrap(~ variable, scales = "free", ncol = 2) +
  scale_fill_manual(values = c("Outside Tukey fences" = "#C44536", "Within fences" = "#1F6F8B")) +
  labs(x = NULL, y = "Women", fill = NULL,
       title = "Outlier screening of the fertility histories (SADHS 2016)",
       subtitle = "Red bars lie outside 1.5 x IQR of the quartiles. Dashed line: biological plausibility limit") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "top", strip.text = element_text(face = "bold"))
dir.create("figures", showWarnings = FALSE)
ggsave("figures/07_outliers.png", p, width = 11, height = 7.5, dpi = 150, bg = "white")

## ---------------------------------------------------------------------
## 4. Sensitivity: first birth before 18 without first births under 12
## ---------------------------------------------------------------------
ctrl <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
f18 <- hrfb_less_18 ~ age_group + province + residence + ethnicity + hh_head_sex +
  education + literacy + wealth_index + marital_status + currently_working +
  ever_used_fp + unmet_need + consumes_media + heard_fp_from_media + (1 | cluster)

keep <- is.na(fert$age_first_birth) | fert$age_first_birth >= 12
fit_all  <- glmer(f18, family = binomial, data = df,         control = ctrl, nAGQ = 25)
fit_trim <- glmer(f18, family = binomial, data = df[keep, ], control = ctrl, nAGQ = 25)

sens <- data.frame(term = names(fixef(fit_all))[-1],
                   or_all_women = round(exp(fixef(fit_all))[-1], 3),
                   or_without_flagged = round(exp(fixef(fit_trim))[-1], 3))
sens$pct_change <- round(100 * (sens$or_without_flagged / sens$or_all_women - 1), 1)
cat("\nLargest change in an odds ratio after removing", sum(!keep), "women:",
    max(abs(sens$pct_change)), "%\n")

dir.create("results", showWarnings = FALSE)
write.csv(audit, "results/outlier_audit.csv", row.names = FALSE)
write.csv(sens, "results/outlier_sensitivity.csv", row.names = FALSE)
