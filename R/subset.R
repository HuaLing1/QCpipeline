##########
# Subset a netCDF file
# Usage: R --args config.file < subset.R
##########

library(GWASTools)
library(QCpipeline)
library(tools)
sessionInfo()

# read configuration
args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 1) stop("missing configuration file")
config <- readConfig(args[1])

# check config and set defaults
required <- c("annot_scan_file", "in_file", "out_file")
optional <- c("chrom_anom_file", "filterYinF", "scan_include_file")
default <- c(NA, TRUE, NA)
config <- setConfigDefaults(config, required, optional, default)
print(config)

(scanAnnot <- getobj(config["annot_scan_file"]))
scanID <- getScanID(scanAnnot)

# get scans to include
if (!is.na(config["scan_include_file"])) {
  scan.include <- getobj(config["scan_include_file"])
} else {
  message("No scan_include_file specified, using all scans")
  scan.include <- scanID
}
length(scan.include)

# get chrom anomalies to filter
if (!is.na(config["chrom_anom_file"])) {
  anom <- getobj(config["chrom_anom_file"])
  if ("filter" %in% names(anom)) anom <- anom[anom$filter,]
  if (!("whole.chrom" %in% names(anom))) anom$whole.chrom <- FALSE
  anom <- anom[,c("scanID", "chromosome", "left.base", "right.base", "whole.chrom")]
} else {
  # dummy anomaly data frame
  anom <- data.frame("scanID"=0, "chromosome"=0, "left.base"=0,
                     "right.base"=0, "whole.chrom"=0)[0,]
}
dim(anom)

# filter XY if X is filtered, or if Y is filtered for males
sex <- getSex(scanAnnot)
allx <- anom$chromosome == 23
table(allx)
ally <- anom$chromosome == 25 & anom$scanID %in% scanID[sex %in% "M"]
table(ally)
filtxy <- allx | ally
if (sum(filtxy) > 0) {
  anom.xy <- anom[filtxy,]
  anom.xy$chromosome <- 24
  anom.xyy <- anom[filtxy,]
  anom.xyy$chromosome <- 28
  anom.xyy$whole.chrom <- TRUE
  anom <- rbind(anom, anom.xy, anom.xyy)
}
dim(anom)

# set Y chromosome to missing for females
if (as.logical(config["filterYinF"])) {
  (nf <- sum(sex %in% "F"))
  if (nf > 0) {
    anom.Y <- data.frame("scanID"=scanID[sex %in% "F"], "chromosome"=rep(25, nf),
                         "left.base"=rep(NA, nf), "right.base"=rep(NA, nf),
                         "whole.chrom"=rep(TRUE, nf))
    anom <- rbind(anom, anom.Y)
  }
  dim(anom)
}

# create a new netCDF with samples in 'scan.include' and anomalies set to missing
parent.file <- config["in_file"]
sub.file <- config["out_file"]
ext <- file_ext(parent.file)
if (ext == "nc") {
    type <- "ncdf"
} else if (ext == "gds") {
    type <- "gds"
} else {
  stop("in_file must end in .nc or .gds")
}
setMissingGenotypes(parent.file, sub.file, anom, file.type=type,
                    sample.include=scan.include)

# check it against the source
nc1 <- GenotypeReader(parent.file)
nc2 <- GenotypeReader(sub.file)
stopifnot(allequal(getSnpID(nc1), getSnpID(nc2)))
stopifnot(allequal(getChromosome(nc1), getChromosome(nc2)))
stopifnot(allequal(getPosition(nc1), getPosition(nc2)))
stopifnot(allequal(scan.include, getScanID(nc2)))

chrom <- getChromosome(nc2)
pos <- getPosition(nc2)
scanID1 <- getScanID(nc1)
scanID2 <- scan.include
ind.old <- which(scanID1 %in% scanID2)
for (ind.new in 1:length(scanID2)) {
  if (ind.new%%10==0) message(paste("scan", ind.new, "of", length(scanID2)))
  geno1 <- getGenotype(nc1, snp=c(1,-1), scan=c(ind.old[ind.new],1))
  geno2 <- getGenotype(nc2, snp=c(1,-1), scan=c(ind.new,1))
  if (!all(na.omit(geno1 == geno2))) stop(paste("non-missing genotypes differ for sample",ind.new))
  nadiff <- which(is.na(geno1) != is.na(geno2))
  anom.sub <- anom[anom$scanID %in% scanID2[ind.new],]
  if (nrow(anom.sub) > 0) {
    na.exp <- vector()
    for (a in 1:nrow(anom.sub)) {
      if (anom.sub$whole.chrom[a]) {
        na.exp <- c(na.exp, which(chrom == anom.sub$chromosome[a] & !is.na(geno1)))
      } else {
        na.exp <- c(na.exp, which(chrom == anom.sub$chromosome[a] & anom.sub$left.base[a] <= pos & pos <= anom.sub$right.base[a] & !is.na(geno1)))
      }
    }
    if (!setequal(nadiff, na.exp)) stop(paste("missing genotypes not as expected for sample",ind.new))
  } else {
    if (length(nadiff) > 0) stop(paste("missing genotypes not as expected for sample",ind.new))
  }
}
close(nc1)
close(nc2)
