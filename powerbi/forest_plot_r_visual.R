# R visual for the Risk factors page (Power BI > Visualizations > R script visual).
# Fields to add to the visual's Values well, from fact_odds_ratios:
#   term_label, odds_ratio, ci_lower, ci_upper, p_value
# Power BI passes them in as a data frame called `dataset`, already filtered
# by the outcome slicer.

library(ggplot2)

d <- unique(dataset)
d$group <- ifelse(d$p_value >= 0.05, "Not significant",
                  ifelse(d$odds_ratio > 1, "Higher risk", "Lower risk"))
d$term_label <- reorder(d$term_label, d$odds_ratio)
d$or_text <- sprintf("%.2f (%.2f-%.2f)%s", d$odds_ratio, d$ci_lower, d$ci_upper,
                     ifelse(d$p_value < 0.001, " ***", ifelse(d$p_value < 0.01, " **",
                     ifelse(d$p_value < 0.05, " *", ""))))
x_text <- max(d$ci_upper) * 1.6   # column of OR labels to the right of the plot

ggplot(d, aes(x = odds_ratio, y = term_label, colour = group)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +
  geom_errorbar(aes(xmin = ci_lower, xmax = ci_upper), width = 0.25, linewidth = 1, orientation = "y") +
  geom_point(size = 4.5) +
  geom_text(aes(x = x_text, label = or_text), hjust = 0, size = 6, colour = "grey20") +
  scale_x_log10(breaks = c(0.1, 0.25, 0.5, 1, 2, 5, 10, 50, 250),
                labels = function(x) format(x, drop0trailing = TRUE),
                expand = expansion(mult = c(0.05, 0.9))) +
  scale_colour_manual(values = c("Higher risk" = "#C44536",
                                 "Lower risk" = "#3D9970",
                                 "Not significant" = "#9AA5AE"),
                      limits = c("Higher risk", "Lower risk", "Not significant"),
                      labels = c("Higher risk (OR > 1, p < 0.05)",
                                 "Lower risk (OR < 1, p < 0.05)",
                                 "Not significant (p >= 0.05)"),
                      drop = FALSE) +
  labs(x = "Adjusted odds ratio (log scale, 95% CI)", y = NULL, colour = NULL) +
  theme_minimal(base_size = 22) +
  theme(legend.position = "top", legend.text = element_text(size = 16),
        panel.grid.minor = element_blank()) +
  guides(colour = guide_legend(nrow = 2, byrow = TRUE, override.aes = list(size = 5))) +
  coord_cartesian(clip = "off")
