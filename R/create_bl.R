##########
# BAF/LRR netCDF file
# Usage: R --args config.file <test> <nbatches> <batch> < create_bl.R
##########

library(GWASTools)
library(QCpipeline)
sessionInfo()

# read configuration
args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 1) stop("missing configuration file")
config <- readConfig(args[1])

# check config and set defaults
required <- c("annot_scan_file", "annot_snp_file", "array_build", "array_name",
              "bl_file", "raw_path")
optional <- c("annot_scan_fileCol", "annot_scan_nameCol", "annot_snp_nameCol",
              "bl_checkFile", "bl_diagFile", "bl_file_type",
              "raw_bafCol", "raw_lrrCol",
              "raw_colTotal", "raw_sampleCol", "raw_scanNameInFile", "raw_sepType",
              "raw_skipNum", "raw_snpCol")
default <- c("file", "Sample.Name", "rsID", "bl_check.RData", "bl_diag.RData", "gds",
             11, 12, 14, NA, 0, ",", 12, 1)
config <- setConfigDefaults(config, required, optional, default)
print(config)

scanAnnot <- getobj(config["annot_scan_file"])
ncfile <- config["bl_file"]
diagfile <- config["bl_diagFile"]
checkfile <- config["bl_checkFile"]

batchfile <- function(x, batch) {
    file.path(dirname(x), paste0("batch", batch, ".", basename(x)))
}

# check for test
if (length(args) > 1) {
  if ((args[2]) == "test") {
    message("testing first 5 scans")
    scanAnnot <- scanAnnot[1:5,] # testing
  } else {
    nbatches <- as.integer(args[2])
    batch <- as.integer(args[3])
    stopifnot(batch <= nbatches)
    nsamp <- nrow(scanAnnot)
    n.per.batch <- ceiling(nsamp/nbatches)
    start <- n.per.batch*(batch-1) + 1
    end <- min(n.per.batch*batch, nsamp)
    scanAnnot <- scanAnnot[start:end,]
    ncfile <- batchfile(ncfile, batch)
    diagfile <- batchfile(diagfile, batch)
    checkfile <- batchfile(checkfile, batch)
  }
}
nsamp <- nrow(scanAnnot)


##########
# Add data to ncdf
##########
(snpAnnot <- getobj(config["annot_snp_file"]))
snp.cols <- intersect(c("snpID", config["annot_snp_nameCol"], "chromosome", "position", 
                        "alleleA", "alleleB"),
                      getVariableNames(snpAnnot))
snpdf <- getVariable(snpAnnot, snp.cols)
names(snpdf)[2] <- "snpName"

scandf <- getVariable(scanAnnot, c("scanID", config["annot_scan_nameCol"], config["annot_scan_fileCol"]))
names(scandf) <- c("scanID", "scanName", "file")

col.nums <- as.integer(c(config["raw_snpCol"], config["raw_bafCol"], config["raw_lrrCol"]))
names(col.nums) <- c("snp", "BAlleleFreq", "LogRRatio")
if (config["raw_scanNameInFile"] == 1) {
  col.nums <- append(col.nums, as.integer(config["raw_sampleCol"]), after=1)
  names(col.nums)[2] <- "sample"
}
skip.num <- as.integer(config["raw_skipNum"])
col.total <- as.integer(config["raw_colTotal"])
scan.name.in.file <- as.integer(config["raw_scanNameInFile"])

res <- createDataFile(path = config["raw_path"], filename = ncfile,
                      file.type = config["bl_file_type"],
                      variables = c("BAlleleFreq","LogRRatio"),
                      snp.annotation = snpdf, scan.annotation = scandf,
                      sep.type=config["raw_sepType"], skip.num=skip.num,
                      col.total=col.total,
                      col.nums=col.nums, scan.name.in.file=scan.name.in.file,
                      compress="LZMA_RA:1M", compress.annot="LZMA_RA",
                      array.name = config["array_name"],
                      genome.build = config["array_build"],
                      diagnostics.filename=diagfile)

########################################
# MANUAL REVIEW - DIAGNOSTICS
########################################
names(res)
table(res$read.file, useNA="ifany")
stopifnot(all(res$read.file == 1))

table(res$row.num, useNA="ifany")
stopifnot(all(res$row.num == nrow(snpAnnot)))

table(unlist(lapply(res$samples, length)),useNA="ifany")  
table(res$sample.match, useNA="ifany")

table(unlist(lapply(res$missg, length)), useNA="ifany") 
unique(unlist(res$missg))

table(res$snp.chk, useNA="ifany")
stopifnot(all(res$snp.chk == 1))

table(res$chk, useNA="ifany")
stopifnot(all(res$chk == 1))

########################################
# MANUAL REVIEW - DATA VALUES
########################################
(nc <- IntensityReader(ncfile))
data <- IntensityData(nc, snpAnnot=snpAnnot, scanAnnot=scanAnnot)
scanID <- getScanID(data)
range(scanID)

n <- nsamp-1   # number of samples minus 1 to get last 2 samples
baf <- getBAlleleFreq(data, snp=c(1,-1), scan=c(n,2))
dim(baf)
nsnp <- nrow(snpAnnot)
stopifnot(dim(baf) == c(nsnp, 2))
baf[round(nsnp/2):(round(nsnp/2)+10),] # middle 10 snps
baf[(nsnp-4):nsnp,]  # last 5 snps

lrr <- getLogRRatio(data, snp=c(1,-1), scan=c(n,2))
dim(lrr)
nsnp <- nrow(snpAnnot)
stopifnot(dim(lrr) == c(nsnp, 2))
lrr[round(nsnp/2):(round(nsnp/2)+10),] # middle 10 snps
lrr[(nsnp-4):nsnp,]  # last 5 snps
close(data)


##########
# Check ncdf file
##########
res <- checkIntensityFile(path = config["raw_path"], filename = ncfile,
                          file.type = config["bl_file_type"],
                          snp.annotation = snpdf, scan.annotation = scandf,
                          sep.type=config["raw_sepType"], skip.num=skip.num,
                          col.total=col.total,
                          col.nums=col.nums, scan.name.in.file=scan.name.in.file,
                          check.scan.index=1:nsamp, n.scans.loaded=nsamp,
                          diagnostics.filename=config["bl_checkFile"])

########################################
# MANUAL REVIEW - DIAGNOSTICS
########################################
table(res$read.file, useNA="ifany")
stopifnot(all(res$read.file == 1))

table(res$row.num, useNA="ifany")
stopifnot(all(res$row.num == nrow(snpAnnot)))

table(unlist(lapply(res$sample.names, length)),useNA="ifany")
table(res$sample.match, useNA="ifany")

table(res$snp.chk, useNA="ifany")
stopifnot(all(res$snp.chk == 1))

table(res$chk, useNA="ifany")
stopifnot(all(res$chk == 1))

table(res$inten.chk$BAlleleFreq, useNA="ifany")
stopifnot(all(res$inten.chk$BAlleleFreq == 1))

table(res$inten.chk$LogRRatio, useNA="ifany")
stopifnot(all(res$inten.chk$LogRRatio == 1))

