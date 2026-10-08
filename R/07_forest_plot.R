# =============================================================================
# odds_ratio_forest_plot.R
#
# Draw a "forest plot" of odds ratios from one or more logistic models:
#   - one dot per predictor level (the odds ratio)
#   - a horizontal bar for its 95% confidence interval
#   - a dashed line at OR = 1 (no effect)
#   - one panel per model/outcome, side by side
#
# Works with:
#   * glmer() multilevel logistic models (lme4)   <- what the HRFB project uses
#   * glm(family = binomial) ordinary logistic models
#
# The file has 3 parts:
#   PART 1  odds_ratio_table()  - turns a fitted model into a tidy table of ORs
#   PART 2  plot_odds_ratios()  - turns that table into the forest plot
#   PART 3  worked examples      - (A) a demo on simulated data you can run
#                                   right now, (B) how to use it on your models
#
# Author: Rolivhuwa Thomoli
# =============================================================================

library(lme4)      # glmer(), fixef(), vcov() for mixed models
library(dplyr)     # data manipulation: mutate(), filter(), bind_rows()
library(ggplot2)   # the plot itself


# =============================================================================
# PART 1: From a fitted model to a table of odds ratios
# =============================================================================
#
# The maths, in brief
# -------------------
# A logistic model estimates coefficients (beta) on the LOG-ODDS scale:
#       log( p / (1 - p) ) = beta0 + beta1*x1 + ...
# Exponentiating a coefficient gives the ODDS RATIO:
#       OR = exp(beta)
# i.e. how many times the odds of the outcome change compared with the
# reference category (OR > 1 = higher odds, OR < 1 = lower odds).
#
# A 95% Wald confidence interval is built on the log scale, where the
# estimate is approximately normal, and then exponentiated:
#       exp( beta - 1.96*SE )   to   exp( beta + 1.96*SE )
# That's why the interval is NOT symmetric around the OR on the normal scale,
# but IS symmetric on a log scale (which is why the plot uses a log x-axis).

odds_ratio_table <- function(fit, model_name) {

  # 1. Coefficients (log-odds). For glmer use fixef() to get only the FIXED
  #    effects; for glm, coef() does the same job.
  est <- if (inherits(fit, "merMod")) fixef(fit) else coef(fit)

  # 2. Standard errors = square root of the diagonal of the variance-covariance
  #    matrix. vcov() works for both glm and glmer. as.matrix() is needed
  #    because glmer returns a special "dpoMatrix" object.
  se <- sqrt(diag(as.matrix(vcov(fit))))

  # 3. Wald z statistic and two-sided p-value: P(|Z| > |z|) = 2 * P(Z < -|z|)
  z <- est / se
  p <- 2 * pnorm(-abs(z))

  # 4. Put it all in a data frame, converting to the odds-ratio scale
  out <- data.frame(
    model   = model_name,
    term    = names(est),
    OR      = exp(est),
    lower   = exp(est - 1.96 * se),
    upper   = exp(est + 1.96 * se),
    p_value = p,
    row.names = NULL
  )

  # 5. Drop the intercept: exp(intercept) is the baseline ODDS for the
  #    reference group, not a ratio, so it doesn't belong on this plot.
  out <- filter(out, term != "(Intercept)")

  # 6. Make readable labels. R names dummy variables by gluing the variable
  #    name to the level, e.g. "education" + "Higher" = "educationHigher".
  #    We look up which original variable each term came from and turn it
  #    into "education: Higher".
  vars <- all.vars(formula(fit, fixed.only = TRUE))[-1]   # predictor names (no response)
  out$variable <- sapply(out$term, function(t) {
    hit <- vars[startsWith(t, vars)]
    if (length(hit)) hit[which.max(nchar(hit))] else t     # longest match wins
  })
  out$level <- mapply(function(t, v) sub(paste0("^", v), "", t), out$term, out$variable)
  out$label <- ifelse(out$level == "", out$variable,
                      paste0(out$variable, ": ", gsub("_", " ", out$level)))
  out
}


# =============================================================================
# PART 2: The forest plot
# =============================================================================
#
# Arguments
#   or_table     : output of odds_ratio_table() (several models bind_rows()'d together)
#   drop_vars    : variables to leave off the plot (e.g. "age_group" when its
#                  ORs are so large they squash everything else)
#   model_order  : order of the panels (default: order they appear in the table)
#   title, subtitle : plot text

plot_odds_ratios <- function(or_table,
                             drop_vars   = NULL,
                             model_order = unique(or_table$model),
                             title       = "Adjusted odds ratios",
                             subtitle    = "95% Wald confidence intervals, log scale") {

  plot_data <- or_table %>%
    # (a) remove any variables we don't want to show
    filter(!variable %in% drop_vars) %>%
    mutate(
      # (b) factor() fixes the panel order; otherwise ggplot sorts alphabetically
      model = factor(model, levels = model_order),
      # (c) flag significance so we can colour it. Here "significant" means
      #     the 95% CI doesn't cross 1, which is the same as p < 0.05.
      significant = p_value < 0.05,
      # (d) keep labels grouped by variable, top to bottom in formula order.
      #     rev() because ggplot draws the first factor level at the BOTTOM.
      label = factor(label, levels = rev(unique(label)))
    )

  ggplot(plot_data, aes(x = OR, y = label, colour = significant)) +

    # Reference line at OR = 1 ("no difference from the reference group").
    # Drawn FIRST so the points sit on top of it.
    geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +

    # The confidence interval: a horizontal error bar from lower to upper.
    # `width` is the height of the little end caps (in y-axis units).
    geom_errorbar(aes(xmin = lower, xmax = upper), width = 0.25, orientation = "y") +

    # The point estimate
    geom_point(size = 1.8) +

    # LOG scale on x: an OR of 2 (double the odds) and 0.5 (half the odds)
    # are the same distance from 1. On a linear scale, protective effects
    # (between 0 and 1) would be squashed into a tiny space.
    scale_x_log10() +

    # Colours: dark blue for significant, grey for not. Named values make sure
    # TRUE/FALSE always get the same colour, whatever order they appear in.
    scale_colour_manual(
      values = c(`TRUE` = "#1F3F77", `FALSE` = "grey65"),
      labels = c(`TRUE` = "p < 0.05", `FALSE` = "not significant"),
      drop   = FALSE
    ) +

    # One panel per model, in a single row, sharing the same y-axis labels
    # so you can read across and compare the same predictor between outcomes.
    facet_wrap(~ model, nrow = 1) +

    labs(title = title, subtitle = subtitle, x = "Odds ratio (log scale)", y = NULL, colour = NULL) +
    theme_minimal(base_size = 10) +
    theme(legend.position = "bottom",
          panel.spacing = unit(1, "lines"),                # space between panels
          strip.text = element_text(face = "bold"))        # bold panel titles
}


# =============================================================================
# PART 3A: Demo on simulated data (runs anywhere, no DHS data needed)
# =============================================================================
# We invent 3,000 women in 150 clusters with two binary outcomes, so you can
# see every step working and experiment with the options.

set.seed(2026)
n <- 3000
demo <- data.frame(
  cluster   = factor(sample(1:150, n, replace = TRUE)),
  education = factor(sample(c("No_education", "Primary", "Secondary", "Higher"), n,
                            replace = TRUE, prob = c(.05, .20, .55, .20)),
                     levels = c("No_education", "Primary", "Secondary", "Higher")),
  wealth    = factor(sample(c("Poor", "Middle", "Rich"), n, replace = TRUE),
                     levels = c("Poor", "Middle", "Rich")),
  residence = factor(sample(c("Urban", "Rural"), n, replace = TRUE),
                     levels = c("Urban", "Rural"))
)
# Each cluster gets its own random "community effect" u_j (this is what the
# (1 | cluster) term in glmer estimates)
u <- rnorm(150, 0, 0.5)[demo$cluster]

# True log-odds for two made-up outcomes; higher education & wealth protect
lp1 <- -1.2 - 0.4 * (demo$education == "Secondary") - 1.1 * (demo$education == "Higher") -
        0.5 * (demo$wealth == "Rich") + 0.3 * (demo$residence == "Rural") + u
lp2 <- -2.0 - 0.2 * (demo$education == "Secondary") - 0.9 * (demo$education == "Higher") -
        0.3 * (demo$wealth == "Middle") - 0.6 * (demo$wealth == "Rich") + u
demo$outcome_a <- rbinom(n, 1, plogis(lp1))    # plogis() = inverse logit
demo$outcome_b <- rbinom(n, 1, plogis(lp2))

# Fit a two-level logistic model for each outcome.
# The "bobyqa" optimiser is more reliable than lme4's default for binary
# outcomes; if you see convergence warnings on your own models, try it first.
ctrl <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
fit_a <- glmer(outcome_a ~ education + wealth + residence + (1 | cluster),
               data = demo, family = binomial, control = ctrl)
fit_b <- glmer(outcome_b ~ education + wealth + residence + (1 | cluster),
               data = demo, family = binomial, control = ctrl)

# Step 1: one OR table per model, stacked into one data frame
or_demo <- bind_rows(
  odds_ratio_table(fit_a, "Outcome A"),
  odds_ratio_table(fit_b, "Outcome B")
)
print(or_demo[, c("model", "label", "OR", "lower", "upper", "p_value")], digits = 3)

# Step 2: plot it
p_demo <- plot_odds_ratios(or_demo, title = "Demo: adjusted odds ratios (simulated data)")
print(p_demo)

# Step 3: save it. Width/height are in inches; dpi = 300 for print quality.
ggsave("output/odds_ratios_demo.png", p_demo, width = 9, height = 4.5, dpi = 300, bg = "white")


# =============================================================================
# PART 3B: Using it on the HRFB models
# =============================================================================
# Uncomment after fitting your glmer models (e.g. glmm_birth_before18,
# glmm_birth_after34, glmm_short_interval, glmm_high_parity). The names in
# quotes become the panel titles.
#
# or_hrfb <- bind_rows(
#   odds_ratio_table(glmm_birth_before18, "First birth before 18"),
#   odds_ratio_table(glmm_birth_after34,  "Birth after age 34"),
#   odds_ratio_table(glmm_short_interval, "Birth interval < 24 months"),
#   odds_ratio_table(glmm_high_parity,    "More than 3 children")
# )
#
# # age_group is dropped from the picture because its ORs (up to ~26) would
# # stretch the axis and hide everything else. Report it in a table instead.
# p_hrfb <- plot_odds_ratios(or_hrfb, drop_vars = "age_group",
#                            title = "Adjusted odds ratios from two-level logistic models")
# ggsave("output/odds_ratios_hrfb.png", p_hrfb, width = 13, height = 8, dpi = 300, bg = "white")
#
# # Export the numbers too (e.g. for a table in your write-up):
# write.csv(or_hrfb, "output/odds_ratios_hrfb.csv", row.names = FALSE)


# =============================================================================
# Ideas to customise it
# =============================================================================
# * Only one model?       Pass one table; facet_wrap() just draws one panel.
# * Profile CIs:          for glmer, confint(fit, method = "profile") is more
#                         accurate than Wald but much slower.
# * Show the numbers:     add  geom_text(aes(label = sprintf("%.2f", OR)), vjust = -0.8, size = 2.5)
# * Other colours:        change the hex codes in scale_colour_manual().
# * Fixed axis range:     scale_x_log10(limits = c(0.05, 5))
