#!/usr/bin/Rscript
################################################################################
#
# Compare symbols from two CSV files (created by codeSize.R) for differences
#
# Author:   Chip Boling
#   Date:   Feb. 9, 2015
#
########################################
# Customized global

readInputCsvFile <- function(inputPath, verbose)
{
    print(sprintf("Reading input file: '%s'", inputPath))

    inputData <- read.csv(inputPath)
}

outputCsvFile <- function(tableList, csvOutput)
{
    # Recreate the one big list.  But first add back in section name

    idx = 1

    for (table in tableList)
    {
        table$section <- as.factor(names(tableList)[idx])
    }
    allSections <- rbindlist(tableList)

    write.table(allSections, file=csvOutput, sep = ",", row.names=FALSE)

    invisible()
}

checkSizeDiffPkgs <- function(pkgs, repo)
{
    pkg.inst <- installed.packages()
    have.pkg <- pkgs %in% rownames(pkg.inst)

    if (any(!have.pkg))
    {
        message("\nSome packages need to be installed.\n")
        #r <- readline("Install necessary packages [y/n]? ")
        cat("  Install necessary packages [y/n]? ")
        answer <- readLines(con="stdin", 1)
        cat(answer, "\n")
        if(tolower(answer) == "y")
        {
            need <- pkgs[!have.pkg]
            message("\nInstalling packages ", paste(need, collapse = ", "))

            # Use 0-clouds RStudion since it provides redirection to other servers worldwide

            install.packages(need, repos=repo)
        }
    }
}

size_diff <- function(leftFile,
                      rightFile,
                      csvOutput="",
                      verbose=FALSE)
{
    ## Compute the size difference between the left and right file
    ##
    ## leftFile   - File path for first file
    ##
    ## rightFile  - File path for first file
    ##
    ## csvOutput     - Output filename for CSV output for entire data.  By default no CSV
    ##                 output is generated.
    # Read our input data

    leftData  <- readInputCsvFile(leftFile, verbose)
    rightData <- readInputCsvFile(leftFile, verbose)

    # We will use the right as the output and so take over the 'address' column as the left
    # data and add in a difference column.  Also zero out the 'leftSize' to start with

    colnames(rightData)[[1]] <- 'leftSize'
    colnames(rightData)[[2]] <- 'rightSize'
    rightData$leftSize       <- 0
    rightData$difference     <- NA

    # Reorder the columns so output/debug is a bit easier

    rightData <- rightData[c('leftSize', 'rightSize', 'difference', 'symbol', 'file')]

    # Walk the left data and search for equivalent match in right.

    findDeltas <- function(rightRow, leftDF)
    {
        # Find equivalent row in the leftDF

        leftRow <- leftDF[leftDF$symbol==rightRow['symbol'] & leftDF$file==rightRow['file'],]

        if ((length(leftRow) == 1) && !is.na(leftRow$size))
        {
            # calculate new value

            rightRow['leftSize']   <- leftRow$size
            rightRow['difference'] <- leftRow$size - rightRow$rightSize

            leftRow$size <- NA
        }
    }
    diffArray <- apply(rightData, 1, findDeltas, leftDF=leftData)

    # Now add remaining right rows in
    # TODO

    print ("------------------------------------------------")
    print ("Done...")
}

####################################################################################
#
# Make sure we have all required packages
#
checkSizeDiffPkgs(c("Rcpp", "plyr", "stringr", "data.table", "getopt"),
                  repo="http://cran.stat.ucla.edu/")
suppressPackageStartupMessages(library(data.table))

library(data.table)
library(stringr)
library(plyr)
library(getopt)

# Get command args

cmdArgs <- commandArgs(TRUE)

if (length(cmdArgs) > 0)
{
    # Parse input with getopt() library

    spec = matrix(c(
        'leftFile',  'l', '1', 'character', 'The input file name # 1',
        'rightFile', 'l', '1', 'character', 'The input file name # 2',
        'output',    'o', '2', 'character', 'Output CSV filename for cleaned map.  Default is "" (no CSV output)',
        'verbose',   'v', '0', 'logical',   'Enable verbose output',
        'help',      '?', '0', 'logical',   'Print out help text'
        ), byrow=TRUE, ncol=5)

    opt = getopt(spec);

    # Asked for help?
    if (!is.null(opt$help))
    {
        cat(getopt(spec, usage=TRUE))
        q(status=1)
    }
    # Update defaults here and also in the 'size_diff' function if you want consistent behaviour
    # from within RStudio (debugging) and from the command line

    if (is.null(opt$verbose))  { opt$verbose  = FALSE }
    if (is.null(opt$output))   { oupt$output  = ""    }

    size_diff(leftFile=opt$leftFile, rightFile=opt$rightFile,
              csvOutput=opt$output, verbose=opt$verbose)
}
if (length(cmdArgs) == 0)
{
    # No arguments on the command line.  May be running it from shell command line or sourcing
    # the file within RStudio for debugging purposes

    cmdArgs <- commandArgs()

    if ("--interactive" %in% cmdArgs)
    {
        # print("Just sourcing inside RStudio")
    }
}
