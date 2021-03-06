##########
# Duplicate snp discordance
# Usage: R --args config.file < dup_snps.R
##########

library(GWASTools)
library(QCpipeline)
sessionInfo()

## read configuration
args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 1) stop("missing configuration file")
config <- readConfig(args[1])

## check config and set defaults
required <- c("annot_scan_file", "annot_snp_file", "geno_subj_file")
optional <- c("annot_snp_dupSnpCol", "annot_snp_missingCol", "annot_snp_rsIDCol",
              "dupsnp_scan_exclude_file", "out_dupsnp_file")
default <- c("dup.pos.id", "missing.n1", "rsID", NA, "dup_snps.RData")
config <- setConfigDefaults(config, required, optional, default)
print(config)

(snpAnnot <- getobj(config["annot_snp_file"]))

data <- GenotypeReader(config["geno_subj_file"])
(scanAnnot <- getobj(config["annot_scan_file"]))
# take subset of annotation to match netCDF
scanAnnot <- scanAnnot[match(getScanID(data), getScanID(scanAnnot)), ]
genoData <- GenotypeData(data, scanAnnot=scanAnnot, snpAnnot=snpAnnot)
scanID <- getScanID(genoData)

## are there any scans to exclude?
if (!is.na(config["dupsnp_scan_exclude_file"])) {
  scan.exclude <- getobj(config["dupsnp_scan_exclude_file"])
  #stopifnot(all(scan.exclude %in% scanID))
} else {
  scan.exclude <- NULL
}
length(scan.exclude)
scan.sel <- which(!(scanID %in% scan.exclude))

#stopifnot(all(scan.sel %in% scanID))

## select snps
snpID <- getSnpID(snpAnnot)
snp.sel <- which(!is.na(getVariable(snpAnnot, config["annot_snp_dupSnpCol"])))
length(snp.sel)


## match up SNPs into pairs
snpset <- pData(snpAnnot)[snp.sel, c("snpID", config["annot_snp_rsIDCol"], config["annot_snp_dupSnpCol"])]
names(snpset) <- c("snpID", "rsID", "dupID")
table(table(snpset$dupID))
dups <- unique(snpset$dupID)
ndups <- length(dups)
if (ndups == nrow(snpset)/2) {

  snpset <- snpset[order(snpset$dupID),]
  dupsnp1 <- snpset[seq(1, length(snp.sel), by=2),]
  names(dupsnp1)[1:3] <- c("snpID.1", "rsID.1","dupID.1")
  dupsnp2 <- snpset[seq(2, length(snp.sel), by=2),]
  names(dupsnp2)[1:3] <- c("snpID.2", "rsID.2","dupID.2")
  snpset2 <- cbind(dupsnp1, dupsnp2)
  stopifnot(allequal(snpset2[,"dupID.1"], snpset2[,"dupID.2"]))
  snpset2$dupID <- snpset2$dupID.1
  snpset2$dupID.1 <- NULL
  snpset2$dupID.2 <- NULL

  ## for each pair of SNPs, find discordance
  n <- nrow(snpset2)
  disc.count <- rep(NA, n)
  disc.sampsize <- rep(NA, n)
  for (i in 1:n) {
    indx1 <- which(is.element(snpID, snpset2$snpID.1[i]))
    indx2 <- which(is.element(snpID, snpset2$snpID.2[i]))
    genox1 <- getGenotype(genoData, snp=c(indx1,1), scan=c(1,-1))[scan.sel]
    genox2 <- getGenotype(genoData, snp=c(indx2,1), scan=c(1,-1))[scan.sel]
    x <- !is.na(genox1) & !is.na(genox2)
    disc.count[i] <- sum(genox1[x]!=genox2[x])
    disc.sampsize[i] <- length(genox1[x])
    if(i %%100 ==0) print(i)
  }
  snpset2$disc.count <- disc.count
  snpset2$disc.sampsize <- disc.sampsize
  snpset2$disc.fraction <- snpset2$disc.count/snpset2$disc.sampsize

} else {

  message("more than 2 probes per SNP")
  idlist <- list()
  for (d in as.character(dups)) {
    idlist[[d]] <- snpset$snpID[snpset$dupID == d]
  }
  
  ## for each group of SNPs, find discordance
  disc.list <- list()
  for (d in 1:ndups) {
    ids <- which(is.element(snpID, idlist[[d]]))
    n <- length(ids)
    dat <- matrix(nrow=length(scan.sel), ncol=n)
    for (m in 1:n) {
      dat[,m] <- getGenotype(genoData, snp=c(ids[m],1), scan=c(1,-1))[scan.sel]
    }
    npair <- sum(upper.tri(matrix(nrow=n,ncol=n),diag=FALSE))
    dupID <- rep(dups[[d]], npair)
    snpID.1 <- rep(NA, npair)
    snpID.2 <- rep(NA, npair)
    disc.count <- rep(NA, npair)
    disc.sampsize <- rep(NA, npair)
    k <- 1
    for (i in 1:(n-1)) {
      nai <- !is.na(dat[,i])
      for (j in (i+1):n) {
        snpID.1[k] <- ids[i]
        snpID.2[k] <- ids[j]
        naij <- nai & !is.na(dat[,j])
        disc.count[k] <- sum(dat[naij,i] != dat[naij,j])
        disc.sampsize[k] <- sum(naij)
        k <- k+1
      }
    }
    disc.list[[d]] <- data.frame(dupID, snpID.1, snpID.2, disc.count, disc.sampsize,
                                 stringsAsFactors=FALSE)
    if(d %%100 ==0) print(d)
  }
  snpset2 <- do.call(rbind, disc.list)
  snpset2$rsID.1 <- snpset$rsID[match(snpset2$snpID.1, snpset$snpID)]
  snpset2$rsID.2 <- snpset$rsID[match(snpset2$snpID.2, snpset$snpID)]
  snpset2$disc.fraction <- snpset2$disc.count/snpset2$disc.sampsize
}
snpset2 <- snpset2[c("dupID", "snpID.1", "rsID.1", "snpID.2", "rsID.2", 
                     "disc.count", "disc.sampsize", "disc.fraction")]

## probability of discordance for various error rates
N <- max(snpset2$disc.sampsize, na.rm=TRUE)
max.disc <- 100
prob.disc <- duplicateDiscordanceProbability(N, max.disc=max.disc)

## find out how  many snps fall into each category of discordance
ncat <- max.disc + 1
num <- rep(NA, ncat)
discordant <- snpset2$disc.count
for(i in 1:ncat) num[i] <- length(discordant[!is.na(discordant) & discordant>(i-1)])
prob.tbl <- cbind(prob.disc, num)

## choose threshold as min # disc where error=0.01 is <0.99
threshold <- which(prob.tbl[,"error=0.01"] < 0.99)[1] - 1
message("filter pairs with > ", threshold, " discordances") # changed ">=" to  ">"


## for the snp pairs with <threshold discordant calls, filter out one member of each pair,
## the one with highest mcr

# bring in missing call rate
snp.mcr <- pData(snpAnnot)[,c("snpID", config["annot_snp_missingCol"])]
names(snp.mcr)[2] <- "mcr"
snpset3 <- merge(snpset2, snp.mcr, by.x="snpID.1", by.y="snpID")
snpset3 <- merge(snpset3, snp.mcr, by.x="snpID.2", by.y="snpID", suffixes=c(".1",".2"))

# snpIDs to filter out
filt <- snpset3[snpset3$disc.count <= threshold,]; dim(filt) #changed "<" to  "<="
filt$out <- ifelse(filt$mcr.1 > filt$mcr.2, 1, 2)
snpID.out <- c(filt$snpID.1[filt$out==1], filt$snpID.2[filt$out==2])
snp.mcr$redundant <- snp.mcr$snpID %in% snpID.out
table(snp.mcr$redundant)

# indicate the snps with at least one discordant duplicate
filt <- snpset3[snpset3$disc.count > threshold,]; dim(filt) #changed ">=" to  ">"
disc.rm <- unique(c(filt$snpID.1, filt$snpID.2))
snp.mcr$dup.probe.disc <- snp.mcr$snpID %in% disc.rm
table(snp.mcr$dup.probe.disc)

table(snp.mcr$redundant, snp.mcr$dup.probe.disc, useNA="ifany")

disc <- list("disc"=snpset2, "probability"=prob.tbl, "snp.annot"=snp.mcr)
save(disc, file=config["out_dupsnp_file"])
