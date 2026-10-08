# =============================================================
# 11_portfolio_figures.R
# Forest plot of the final multilevel models, drawn from the
# published table results/final_odds_ratios.csv. Needs no survey
# data, so anyone can run it from a fresh clone:
#   Rscript R/11_portfolio_figures.R
# =============================================================

library(ggplot2)

or <- read.csv("results/final_odds_ratios.csv", stringsAsFactors = FALSE)

or$group <- ifelse(or$p_value >= 0.05, "Not significant",
                   ifelse(or$odds_ratio > 1, "Higher risk", "Lower risk"))
or$outcome_label <- factor(or$outcome_label,
                           levels = c("First birth before 18", "Birth after age 34",
                                      "Short birth interval (<24 months)",
                                      "High parity (>3 children)"))
# One shared term order: sorted by the mean log odds ratio across outcomes
term_order <- names(sort(tapply(log(or$odds_ratio), or$term_label, mean)))
or$term_label <- factor(or$term_label, levels = term_order)

p <- ggplot(or, aes(x = odds_ratio, y = term_label, colour = group)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +
  geom_errorbar(aes(xmin = ci_lower, xmax = ci_upper), width = 0.3,
                orientation = "y", linewidth = 0.5) +
  geom_point(size = 1.8) +
  scale_x_log10(breaks = c(0.1, 0.25, 0.5, 1, 2, 4, 10, 50, 200),
                labels = function(x) format(x, drop0trailing = TRUE)) +
  scale_colour_manual(values = c("Higher risk" = "#C44536", "Lower risk" = "#3D9970",
                                 "Not significant" = "#9AA5AE"),
                      limits = c("Higher risk", "Lower risk", "Not significant")) +
  facet_wrap(~ outcome_label, nrow = 1, scales = "free_x") +
  labs(x = "Adjusted odds ratio (log scale, 95% CI)", y = NULL, colour = NULL,
       title = "Adjusted odds ratios from the final two-level logistic models",
       subtitle = "Variables chosen by group LASSO (BIC). Birth after 34 is modelled among women aged 35+.") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold"))

ggsave("figures/05_odds_ratios.png", p, width = 15, height = 9, dpi = 150, bg = "white")
cat("Wrote figures/05_odds_ratios.png\n")
