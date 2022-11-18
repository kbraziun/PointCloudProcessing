#####
# 
## Step 02: Estimate some simple plot measurements from point cloud data
#
#####

# R 4.1.3

# libraries
library(lidR) # 4.0.2
library(terra) # 1.6.17 
library(sp) # 1.5-0
library(sf) # 1.0-8
library(tidyverse) # 1.3.1

# set working directory (base directory) if needed

dir_plot <- read.csv("scripts/dir_plot_lookup.csv")

### here, go through 1 at a time to vet the classification of snags versus trees
i=1

plot.in <- dir_plot[i,]$plot
plotcode.in <- dir_plot[i,]$Plot_code

###
# 1. load data
###

### read in processed las data
ttops <- st_read(paste0("processed_data/",plot.in,"_ttops.gpkg"))
tlas <- readLAS(paste0("processed_data/",plot.in,"_tlas.laz"))
chm <- rast(paste0("processed_data/",plot.in,"_chm.tif"))

###
# 2. classification of trees versus snags
###

### first derive standard crown metrics, shape
crowns <- crown_metrics(tlas, func=.stdtreemetrics, geom="convex", attribute="treeID")
plot(chm)
plot(crowns["convhull_area"], add=TRUE) # could also derive canopy cover from this
plot(crowns["Z"])

### derive metrics for spectral classification of snags versus trees
# subset to only trees and points > 1.4 m height
tlas.trees <- filter_poi(tlas, Z>=1.4)

# metrics: average, max, and variability
metrics_custom <- function(z) { # user defined function
  list(
    mean <-  mean(z),
    max <- max(z),
    coef_var <-   sd(z) / mean(z) * 100) # coefficient of variation
}

# use spectral data to classify live tree v. snag
tree.red <- tree_metrics(tlas.trees, ~metrics_custom(R))
names(tree.red) <- c("treeID","mean_r","max_r","cv_r")
tree.green <- tree_metrics(tlas.trees, ~metrics_custom(G))
names(tree.green) <- c("treeID","mean_g","max_g","cv_g")
tree.blue <- tree_metrics(tlas.trees, ~metrics_custom(B))
names(tree.blue) <- c("treeID","mean_b","max_b","cv_b")

# combine into dataframe
tree.df <- cbind(as.data.frame(tree.red)[,c(1:4)],as.data.frame(tree.green)[,c(2:4)],as.data.frame(tree.blue)[,c(2:4)])

# first, unsupervised kmeans classification
set.seed(479)
kmncluster <- kmeans(na.omit(tree.df), centers=10, iter.max=500, nstart=10, algorithm="Lloyd")
tree.df$cluster <- kmncluster$cluster # add to df

# snags show distinct spectral characteristics with generally higher blue or lower NIR

# ID cluster that matches expectations for snag
tree.df %>%
  pivot_longer(-c(treeID,cluster)) %>%
  ggplot(aes(y=value, group=cluster, fill=factor(cluster))) +
  facet_wrap(~name, scales="free") +
  geom_boxplot() +
  theme_bw()

tree.df %>%
  dplyr::select(treeID,cluster) %>%
  group_by(cluster) %>% 
  tally()

if(dir_plot[i,]$spectral=="rgb") {
  # cluster if RGB, choose based on highest mean blue
  cluster.in <- tree.df %>%
    group_by(cluster) %>%
    summarise(mean_b = median(mean_b)) %>%
    slice(which.max(mean_b)) 
  } else if(dir_plot[i,]$spectral=="rgnir") {
  # cluster if RGNIR, choose based on lowest mean NIR (coded as R)
  cluster.in <- tree.df %>%
    group_by(cluster) %>%
    summarise(mean_r = median(mean_r)) %>%
    slice(which.min(mean_r)) }

# join with crown metrics, plot trees and snags
tree.clusters <- crowns %>%
  left_join(tree.df, by="treeID")

cluster.sub <- tree.clusters %>%
  filter(cluster==cluster.in$cluster)

plot(chm)
plot(cluster.sub["Z"],add=TRUE)

# second, classify any remaining trees > 5 m in height as snags, because expect regenerating trees to be shorter
trees.tall <- ttops %>%
  filter(Z>=5)

snags <- filter_poi(tlas.trees,treeID %in% c(cluster.sub$treeID, trees.tall$treeID))
plot(snags, color="RGB")
plot(snags, bg="white", color="RGB")

trees <- filter_poi(tlas.trees,!(treeID %in% c(cluster.sub$treeID,trees.tall$treeID))&!is.na(treeID))
plot(trees, bg="white", color="RGB")

# 5 clusters + max height cutoff: generally differentiates well between trees and snag

###
# 3. summarize plot-level measurements
###

### tree, snag, stem density
trees_ha <- length(unique(trees$treeID)) * 4  # nbr unique trees, 1/4 ha plot
snags_ha <- length(unique(snags$treeID)) * 4  # nbr unique snags, 1/4 ha plot
stems_ha <- (dim(ttops)[1]-snags_ha) * 4  # nbr ttops minus nbr snags

### mean and 90th percentile height
tree_ht <- crowns %>%
  filter(treeID %in% c(trees$treeID)) %>%
  summarise(tree_mean_ht = mean(Z), tree_dom_ht = quantile(Z, 0.90), tree_max_ht = max(Z)) %>%
  as.data.frame() %>%
  dplyr::select(-geometry)

snag_ht <- crowns %>%
  filter(treeID %in% c(snags$treeID)) %>%
  summarise(snag_mean_ht = mean(Z), snag_dom_ht = quantile(Z, 0.90), snag_max_ht = max(Z)) %>%
  as.data.frame() %>%
  dplyr::select(-geometry)

### total live tree biomass
# using simple allometric equation from Brown 1978 for whole tree wts, trees < 15 ft height, lodgepole pine
tree_bm <- crowns %>%
  filter(treeID %in% c(trees$treeID)) %>%
  mutate(ht_ft = Z * 3.281,
         bm_lbs = exp(-3.720 + 2.411*log(ht_ft)),
         bm_Mg = bm_lbs*0.0004536) %>%
  summarise(bm_Mg_ha = sum(bm_Mg)*4) %>%
  as.data.frame() %>%
  dplyr::select(-geometry)

### combine and write out
out.df <- data.frame(cbind(trees_ha,stems_ha,snags_ha,tree_ht,snag_ht,tree_bm)) %>%
  # add avg tree bm
  mutate(tree_avg_bm_kg = (bm_Mg_ha*1000)/trees_ha) %>%
  mutate(Plot_code=plotcode.in,
         Plot_UAS=plot.in)

out.update <- read.csv("processed_data/uas_plot_meas.csv") %>%
  rbind(out.df)

write.csv(out.update, "processed_data/uas_plot_meas.csv",row.names=FALSE)

