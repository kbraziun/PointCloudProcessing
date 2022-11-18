#####
# 
## Step 03: Comparison with field measurements
#
#####

# R 4.1.3

# libraries
library(tidyverse) # 1.3.1
library(ggpubr) # 0.4.0
library(plotrix) # 3.8-2, comput std error

# set working directory (base directory) if needed

###
# 1. load data
###

### uas data
uas.plots <- read.csv("processed_data/uas_plot_meas.csv") %>%
  separate(Plot_UAS, into=c("pre","comp"), sep="rg") %>%
  # omit nogps plots and avg tree biomass
  filter(comp!="nir_hh_8gcps_nogps") %>%
  dplyr::select(-tree_avg_bm_kg) %>%
  pivot_longer(c(trees_ha:bm_Mg_ha), values_to="uas")

### field data
field.plots <- read.csv("data/field_plot_measurements.csv") %>%
  dplyr::select(-tree_avg_bm_kg) %>%
  pivot_longer(c(snags_ha:bm_Mg_ha), values_to="field")

# join
plot.comp <- uas.plots %>%
  left_join(field.plots, by=c("Plot_code","name"))

###
# 2. plot comparisons
###

facet.labels <- as_labeller(c("stems_ha"="Stems~ha^-1",
                              "trees_ha"="Trees~ha^-1",
                              "snags_ha"="Snags~ha^-1",
                              "tree_mean_ht"="Mean~tree~ht~(m)",
                              "tree_dom_ht"="90*th~pct~tree~ht~(m)",
                              "tree_max_ht"="Max~tree~ht~(m)",
                              "snag_mean_ht"="Mean~snag~ht~(m)",
                              "snag_dom_ht"="90*th~pct~snag~ht~(m)",
                              "snag_max_ht"="Max~snag~ht~(m)",
                              "bm_Mg_ha" = "Tree~biomass~(Mg~ha^-1)"),
                            label_parsed)

fsize=10
fsize2=8

### predicted v. observed, 1:1 line
plot.comp %>%
  mutate(name=factor(name, levels=c("stems_ha","trees_ha","snags_ha",
                                    "tree_mean_ht","tree_dom_ht","tree_max_ht",
                                    "snag_mean_ht","snag_dom_ht","snag_max_ht",
                                    "bm_Mg_ha"))) %>%
  filter(!comp %in% c("nir_hh_1gcps_withgps","nir_hh_5gcps_withgps")) %>%
  ggplot(aes(x=field, y=uas)) +
  facet_wrap(~name, scales="free",ncol=3,
             labeller=facet.labels) +
  geom_point(aes(color=factor(comp), shape=factor(comp))) +
  geom_abline(slope=1, col="black") +
  scale_color_manual(labels=c("RGB","RGN Nadir+Oblique 8 GCPs","RGN Nadir 8 GCPs","RGN Nadir+Oblique 0 GCPs"), values=c("#2166ac","#f4a582","#d6604d","#b2182b")) +
  scale_shape_manual(labels=c("RGB","RGN Nadir+Oblique 8 GCPs","RGN Nadir 8 GCPs","RGN Nadir+Oblique 0 GCPs"), values=c(16,15,17,18)) +
  ylab("UAS measurement") +
  xlab("Field measurement") +
  theme_bw() +
  theme(panel.grid.minor = element_blank(),
        axis.text = element_text(size=fsize2),
        axis.title = element_text(size=fsize),
        legend.text = element_text(size=fsize),
        legend.title = element_blank(),
        legend.position = c(0.6,0.1))
ggsave("figures/uas_field_comparisons.pdf",width=6,height=7.5)

### normalized RMSE
plot.rmse <- plot.comp %>%
  mutate(error = (uas-field)^2) %>%
  group_by(comp,name) %>%
  summarise(rmse = sqrt(mean(error)),
            nrmse = rmse/mean(field)) %>%
  # classify by measurement type
  mutate(meas_type = ifelse(name %in% c("trees_ha","stems_ha","snags_ha"),"density",
                            ifelse(name %in% c("tree_mean_ht","tree_dom_ht","tree_max_ht","snag_mean_ht","snag_dom_ht","snag_max_ht"),"height",
                                   ifelse(name=="bm_Mg_ha","biomass",NA)))) %>%
  # reorder factors
  mutate(comp=factor(comp, levels=c("b_hh","nir_hh_8gcps_withgps",
                                    "nir_hh_8gcps_withgps_nadironly",
                                    "nir_hh_nogcps",
                                    "nir_hh_1gcps_withgps",
                                    "nir_hh_5gcps_withgps")))

# compute mean and se for plotting
rmse.stats <- plot.rmse %>%
  group_by(comp,meas_type) %>%
  summarise(mean=mean(nrmse),se=std.error(nrmse)) %>%
  # add 0s for biomass
  mutate(se=ifelse(meas_type=="biomass",0,se))

# plot
plot.rmse %>%
  ggplot(aes(x=interaction(comp,meas_type),y=nrmse, color=factor(meas_type), fill=factor(meas_type))) +
  geom_jitter(width=0.1, data=plot.rmse[plot.rmse$name !="bm_Mg_ha",], shape=21) + # remove because only 1 value, this is included in stat_summary as a mean point
  stat_summary(geom="point",fun=mean,size=2, alpha=1) +
  geom_errorbar(aes(ymin=mean-se, ymax=mean+se,y=mean), data=rmse.stats, width=0,size=0.5,alpha=1) +
  scale_color_manual(labels=c("Biomass","Density","Height"),values=alpha(c("#543005","#7fbc41","#8856a7"),0.3), name="Measurement type") +
  scale_fill_manual(labels=c("Biomass","Density","Height"),values=alpha(c("#543005","#7fbc41","#8856a7"),0.2), name="Measurement type") +
  scale_x_discrete(labels=c("","RGB","","","RGN Nadir+Oblique\n8GCPs","","","RGN Nadir only\n8GCPs","","","RGN Nadir+Oblique\n0GCPs","","","RGN Nadir+Oblique\n1GCPs","","","RGN Nadir+Oblique\n5GCPs","")) +
  ylab("Normalized RMSE") +
  theme_bw() +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        axis.text.y = element_text(size=fsize2),
        axis.text.x = element_text(size=fsize2,angle=45,vjust=1,hjust=1),
        axis.ticks.x = element_blank(),
        axis.title = element_text(size=fsize),
        legend.text = element_text(size=fsize),
        axis.title.x = element_blank())
ggsave("figures/uas_field_rmse.pdf",width=6.5,height=3.5)
