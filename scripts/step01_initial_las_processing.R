#####
# 
## Step 01: Initial point cloud processing: normalized las, chm, and individual tree segmentation
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

### can specify directory and plot
# dir.in <- "IronMtn_Derby_1_1_long_1"
# plot.in <- "IronMtn_Derby_1_1_long_1_rgb_hh"
# inputs for this script are not included on github due to size limits, but can be provided upon request
# outputs are included on github

### or run a loop multiple plots
dir_plot <- read.csv("scripts/dir_plot_lookup.csv")

for(i in 1:dim(dir_plot)[1]) {
  dir.in <- dir_plot[i,]$dir
  plot.in <- dir_plot[i,]$plot
  
  
  ###
  # 1. load data
  ###
  
  # point cloud, already subset to plot boundaries
  las <- readLAS(paste0("data/",dir.in,"/",plot.in,"_classified_plot.laz"))
  
  # dem including buffer around plot
  dem <- rast(paste0("data/",dir.in,"/",plot.in,"_DEM_grd.tif"))
    
  # plot boundaries
  plot.bound <- st_read(paste0("data/",dir.in,"/plot_shp.shp")) %>%
    st_transform(crs(dem))
  
  ###
  # 2. filter duplicates
  ###
  
  # remove duplicated points for more efficient computation
  las.sub <- filter_duplicates(las)
  # save npoints and density
  summ.out <- data.frame(npoints=npoints(las.sub),pts_m2=density(las.sub))
  
  # clean up
  rm(las)
  gc()
  
  ###
  # 3. normalize to DEM derived from point cloud
  ###
  
  # ideally, have high-resolution DEM created from lidar point cloud that can penetrate the canopy
  # alternative used here: used DEM from photogrammetry point cloud
  
  ### filter by classification
  # 0 is aboveground, 2 is ground, 7 is belowground
  
  # top
  top <- filter_poi(las.sub, Classification==0)
  # clean up
  rm(las.sub)
  gc()
  
  ### normalize las with high resolution DEM
  dem.plot <- crop(dem, st_buffer(plot.bound, 30))
  
  # simple subtraction, because already high resolution, derived from same point cloud data
  nlas <- top - dem.plot
  
  ###
  # 4. canopy height model
  ###
  
  # 10 cm resolution
  chm <- rasterize_canopy(nlas, res = 0.10, algorithm = p2r()) 
  
  # can fill in missing values if desired
  
  ###
  # 5. individual tree detection
  ###
  
  ### locate treetops
  # using 1m diameter circle because expect many small trees
  # set min height to 0.1 m
  ttops <- locate_trees(nlas, lmf(ws = 1, hmin=0.1)) 
  
  ### segment trees
  algo <- dalponte2016(chm, ttops, th_tree=0.1) # segmentation algorithm, uses chm
  tlas <- segment_trees(nlas, algo) # segment point cloud
  
  ### write out final treetops, segmented point cloud, chm
  st_write(ttops, paste0("processed_data/",plot.in,"_ttops.gpkg"))
  writeLAS(tlas, paste0("processed_data/",plot.in,"_tlas.laz"))
  writeRaster(chm, paste0("processed_data/",plot.in,"_chm.tif"))
  write.csv(summ.out, paste0("processed_data/",plot.in,"_pointDensity_noDuplicates.csv"),row.names=FALSE)
  
}
