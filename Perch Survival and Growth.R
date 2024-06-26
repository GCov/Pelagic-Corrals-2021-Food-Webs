# Setup ------

# Load libraries for this script

library(ggplot2)  # for plotting
library(tidyr)  # for data wrangling
library(dplyr)  # for data wrangling
library(glmmTMB)  # for LMs
library(DHARMa)  # for assessing LMs
library(emmeans)  # for interpreting LMs
library(ggeffects)  # intaerpreting LMs

# Set a universal ggplot theme to use for all plots

theme1 <-
  theme_bw() +
  theme(
    panel.spacing = unit(1, "lines"),
    text = element_text(size = 9,
                        family = "serif"),
    axis.text = element_text(size = 9),
    strip.background = element_blank(),
    strip.text = element_text(size = 8),
    legend.text = element_text(size = 10),
    panel.grid = element_blank(),
    legend.key.size = unit(0.4, "cm"),
    legend.spacing = unit(0, "cm")
  )

# Load perch biometrics and stocking/mortality data ----

biometrics <- read.csv("perch_biometrics.csv",
                       # biometrics
                       header = TRUE,
                       stringsAsFactors = TRUE)

pop <- read.csv("fish_pop.csv",
                # population data
                header = TRUE,
                stringsAsFactors = TRUE)

perch2021 <-
  left_join(biometrics,  # combine the data by mesocosm ID
            pop, by = "corral")

# Remove those without data (mostly non-perch fish that got into the mesocosms)

perch2021 <-
  perch2021 %>%
  filter(!is.na(TL))

# Take means and SDs for body weight and total length, by treatment

perch2021 %>%
  group_by(MPconcentration, YP.end) %>%
  summarize(
    mean.body.weight = mean(body.weight),
    sd.body.weight = sd(body.weight),
    mean.TL = mean(TL),
    sd.TL = sd(TL)
  )

# Compare body weight (growth) with MP concentration ----

## As an ANOVA ----

fish2021.mod1 <-
  aov(body.weight ~ corral,
      data = perch2021)

summary(fish2021.mod1)

plot(residuals(fish2021.mod1) ~ fitted(fish2021.mod1))
abline(0, 0)

# Corral is sig (p<0.001)

TukeyHSD(fish2021.mod1)  # Differences in H-B, H-D, H-I

# Predict from the model

fish2021.pred <-
  data.frame(corral = levels(perch2021$corral))

fish2021.pred$fit <- predict(fish2021.mod1,
                             newdata = fish2021.pred,
                             re.form = NA)

fish2021.pred <- left_join(fish2021.pred,
                           pop,
                           by = "corral")

# Define treatment names

perch2021$treatment <-
  perch2021$MPconcentration

perch2021$treatment[perch2021$treatment == "0"] <-
  with(perch2021[perch2021$treatment == "0", ],
       ifelse(corral == "B",
              "0 (1)",
              "0 (2)"))

perch2021$treatment <- as.factor(perch2021$treatment)

# Make data frame for letters according to significant differences

fish2021.labs <-
  perch2021 %>%
  group_by(corral, MPconcentration, treatment) %>%
  summarize(y = max(na.omit(body.weight)))

fish2021.labs$lab <-
  c("a", "ab", "a", "ab", "ab", "ab", "b", "a")

# Plot the ANOVA results

png(
  "2021 Perch Weights.png",
  width = 8.84,
  height = 6,
  units = "cm",
  res = 600
)

ggplot(perch2021) +
  geom_boxplot(aes(
    x = MPconcentration,
    y = body.weight,
    fill = reorder(treatment,
                   MPconcentration,
                   mean)
  ),
  alpha = 0.75) +
  geom_text(
    data = fish2021.labs,
    aes(
      x = MPconcentration,
      y = y + 0.5,
      label = lab,
      group = reorder(treatment,
                      MPconcentration,
                      mean)
    ),
    size = 10 / .pt,
    position = position_dodge(width = 1)
  ) +
  labs(x = expression(paste(
    "MP Exposure Concentration (particles" ~ L ^ -1 * ")"
  )),
  y = "Body Weight (g)") +
  scale_fill_viridis_d(option = "plasma",
                       name = "Treatment",
                       direction = -1) +
  scale_x_continuous(trans = "log1p",
                     breaks = sort(unique(perch2021$MPconcentration))) +
  theme1 +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

dev.off()

## As a regression ----

fish2021.mod1 <-
  glmmTMB(body.weight ~ log(MPconcentration + 6) + (1 | corral),
          data = perch2021)

plot(simulateResiduals(fish2021.mod2))  # issues with the residuals

plotResiduals(fish2021.mod1, perch2021$corral)
plotResiduals(fish2021.mod1, perch2021$YP.end)
# Seems to be some variation in residuals by mesocosm, maybe driven by mortality

# Try including number of survivors in each mesocosm
# Excluded the mesocosm random effect because every mesocosm has a unique
# combination of MP concentration and number of survivors

fish2021.mod2 <-
  glmmTMB(body.weight ~ log(MPconcentration + 6) + YP.end,
          data = perch2021)

plot(simulateResiduals(fish2021.mod2))  # this solves the issue

summary(fish2021.mod2)

# Predict from the model

perch.body.predict <-
  as.data.frame(ggemmeans(fish2021.mod2,
                          c("YP.end")),
                terms_to_colnames = TRUE)

ggemmeans(fish2021.mod2,
          c("YP.end"))

perch.body.predict$YP.end <- as.character(perch.body.predict$YP.end)
perch.body.predict$YP.end <- as.numeric(perch.body.predict$YP.end)

### Make the body weight figure for the paper ----

set.seed(5465)

png(
  "2021 Perch Weights 2.png",
  width = 8.84,
  height = 9.5,
  units = "cm",
  res = 600
)

ggplot(perch2021) +
  geom_ribbon(data = perch.body.predict,
              aes(x = YP.end,
                  ymin = conf.low,
                  ymax = conf.high),
              alpha = 0.4) +
  geom_line(data = perch.body.predict,
            aes(x = YP.end,
                y = predicted)) +
  geom_jitter(
    aes(
      x = YP.end,
      y = body.weight,
      fill = as.factor(MPconcentration)
    ),
    shape = 21,
    alpha = 0.75,
    height = 0,
    width = 0.1
  ) +
  scale_y_continuous(limits = c(0, 14),
                     expand = c(0, 0)) +
  scale_fill_viridis_d(option = "inferno",
                       direction = -1,
                       name =
                         expression(
                           paste("Microplastic exposure concentration (particles" ~ L ^ -1 * ")")
                         )) +
  labs(x = "Number of Surviving Yellow Perch",
       y = "Final Body Weight (g)") +
  theme1 +
  theme(legend.position = "bottom",
        legend.direction = "vertical") +
  guides(colour = guide_legend(nrow = 2),
         fill = guide_legend(nrow = 2))

dev.off()

## Check that mortality and treatment weren't correlated ----

fish_pop <-
  pop %>%
  mutate(surv.ratio = YP.end/YP.start)

fish_pop

plot(surv.ratio ~ log(MPconcentration + 6), data = fish_pop)

mort.mod <-
  glmmTMB(
    surv.ratio ~ log(MPconcentration + 6),
    family = beta_family(link = "logit"),
    data = fish_pop
  )  # beta model

plot(simulateResiduals(mort.mod))  # doesn't work, too few data points
plot(resid(mort.mod) ~ fitted(mort.mod))  # doesn't look great

summary(mort.mod)
# But p is very high and just visually it seems unlikely that there is a 
# relationship

# Some extra stuff ----

# Additional density plot to view how the body weight data are distributed

ggplot(perch2021) +
  geom_density(aes(x = FL,
                   fill = corral),
               alpha = 0.5) +
  facet_grid(MPconcentration ~ .) +
  labs(x = "Fork Length (cm)",
       y = "Density") +
  scale_fill_viridis_d(option = "turbo",
                       name = "Corral") +
  scale_x_continuous(limits = c(6, 11.5),
                     expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0)) +
  theme1

## Fultons's K ----

perch2021$FultonK <- with(perch2021,
                          body.weight / (TL ^ 3))

fish2022.mod3 <-
  glmmTMB(FultonK ~ corral,
          data = perch2021)

summary(fish2022.mod3)

plot(simulateResiduals(fish2022.mod3))

ggplot(perch2021) +
  geom_density(aes(x = FultonK,
                   fill = corral),
               alpha = 0.5) +
  facet_grid(MPconcentration ~ .) +
  labs(x = "Condition Factor (K)",
       y = "Density") +
  scale_fill_viridis_d(option = "turbo",
                       name = "Corral") +
  scale_x_continuous(limits = c(0.0075, 0.0125),
                     expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0)) +
  theme1

# Neither fork length nor condition affected by MP concentration #

## Gonad weight ----

fish2021.mod2 <-
  aov(gonad.weight ~ corral,
      data = perch2021)

summary(fish2021.mod2)

plot(residuals(fish2021.mod1) ~ fitted(fish2021.mod1))
abline(0, 0)
