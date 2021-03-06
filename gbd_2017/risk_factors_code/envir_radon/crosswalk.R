#----HEADER----------------------------------------------------------------------------------------------------------------------
# Project: RF: envir_radon
# Purpose: Run a linear model to crosswalk radon input data from geometric to arithmetic mean
#********************************************************************************************************************************

#----CONFIG----------------------------------------------------------------------------------------------------------------------
# clear memory, only if running locally - otherwise you want the df from the launcher to be passed through from global namespace
if (Sys.info()["sysname"] == "Windows") {
  rm(list=ls())
  
  # disable scientific notation
  options(scipen = 999)
}
# runtime configuration
if (Sys.info()["sysname"] == "Linux") {
  
  j_root <- "FILEPATH" 
  h_root <- "FILEPATH"
  
} else { 
  
  j_root <- "FILEPATH"
  h_root <- "FILEPATH"
  
}

# set control flow arguments
run.interactively <- F

# load packages
library(plyr)
library(foreign)
library(splines)
library(boot)
library(reshape2)
library(data.table)
library(stats)
library(lme4)
library(ggplot2)

source("FILEPATH/get_location_metadata.R")
locations <- get_location_metadata(location_set_id=22)
#********************************************************************************************************************************

#----PREP------------------------------------------------------------------------------------------------------------------------
# Read in your model data if you are working interactively

  df <- fread("FILEPATH/gbd15_radon_data.csv")
  new <- fread("FILEPATH/new_gbd16_radon_data.csv",
               colClasses = c(standard_error = "numeric",variance = "numeric"))
  new2 <- fread("FILEPATH/new_gbd17_radon_data.csv")
  
  new2 <- new2[outlier==0,names(new),with=F]
  new2$super_region_id <- NULL
  new2$region_id <- NULL
  new2 <- merge(new2,locations[,.(ihme_loc_id,super_region_id,region_id)],by=c("ihme_loc_id"))
  
  new <- rbind(new2,new)
  
  #calc variance and standard error for new data
  new[is.na(standard_error) & geometric_mean == 1, standard_error := standard_deviation/sqrt(sample_size)]
  new[is.na(variance),variance := standard_error**2]
  df <- rbind(df, new)
  
# Remove extreme outliers
df <- df[ihme_loc_id != "SRB" | data != 529]
df <- df[ihme_loc_id != "CZE" | data != 969]
df <- df[ihme_loc_id != "NGA" | data < 200]
df <- df[ihme_loc_id != "PRT" | data < 600]

# save a csv of raw combined data
write.csv(df,"FILEPATH/input_data.csv")

#********************************************************************************************************************************

#----MODEL------------------------------------------------------------------------------------------------------------------------
## Linear model
mod <- lmer(log(data) ~ geometric_mean + subnational + (1|location_id) + (1|region_id), 
            data=df, 
            na.action=na.omit)

## Crosswalk non-gold standard datapoints
# First store the relevant coefficients
coefficients <- as.data.table(coef(summary(mod)), keep.rownames = T)
#********************************************************************************************************************************

#----CROSSWALKING DATA-------------------------------------------------------------------------------------------------------------
# The regression is done in logspace, so transform data/variance in order to adjust them in this space
df[, "data" := log(data)]
df[, "variance" := variance * (1/exp(data))^2] # using delta method for logspace

# Save your raw data/variance for reference
df[, "raw_data" := copy(data)]
df[, "raw_variance" := copy(variance)]

# We will first crosswalk our data based on the results of the regression
# Then, adjust the variance of datapoints, given that our adjusted data is less certain subject to the variance of the regression 

# Adjust datapoints to geometric mean
# note that if the variable = 1, that means data is arithmetic (non standard)
# therefore, we want to crosswalk these points down to the geometric mean values
gm_coeff <- as.numeric(coefficients[rn == "geometric_mean", 'Estimate', with=F])
df[, "data" := data - (geometric_mean * gm_coeff)]

# Now adjust the variance for points crosswalked to geometric mean
gm_se <- as.numeric(coefficients[rn == "geometric_mean", 'Std. Error', with=F])
df[, variance := variance + (geometric_mean^2 * gm_se^2)]

# see what happened if working interactively
if (run.interactively == TRUE) {
  
  df[, "adj_mean" := exp(data)]
  df[, "raw_mean" := exp(raw_data)]
  df[, "diff" := adj_mean - raw_mean]
  summary(df$diff)
  range(df$diff, na.rm=TRUE)
  
  View(df[abs(diff)>5,])
  
  qplot(data = df, adj_mean, raw_mean, color=abs(diff))
  
  df[, "diff" := raw_variance - variance]
  range(df$diff, na.rm=TRUE)
  qplot(data = df, variance, raw_variance, color=abs(diff)) + geom_abline(slope=1)
  
}


# First reset all study level covariates to predict as the gold standard
# Also save the originals for comparison
df[, geometric_mean_og := geometric_mean]
df[, geometric_mean := 0]

# Reverse transform data/variance (they wil be transformed for the linear model in later code)
# The regression is done in logspace, so transform data/variance in order to adjust them in this space
df[, "data" := exp(data)]
df[, "variance" := variance / (1/data)^2] # using reverse delta method for logspace

#impute variance
df[, CV := standard_error*sqrt(sample_size)/data]
cvmean <- mean(df$CV,na.rm=T)
df[is.na(standard_error), standard_error := cvmean*data/sqrt(sample_size)]
df[is.na(variance), variance := standard_error**2]

df[,cv_subgeo := 0]
df[!grepl("_",ihme_loc_id) & subnational == 1, cv_subgeo := 1]

# Save df with all crosswalk result variables for examination
write.csv(df, ("FILEPATH/crosswalked_results.csv"), row.names=FALSE)
