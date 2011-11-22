readConfig <- function(file, ...) {
  config.table <- read.table(file, as.is=TRUE, ...)
  config <- config.table[,2]
  names(config) <- config.table[,1]
  return(config)
}