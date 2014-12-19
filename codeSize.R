################################################################################
#
# Crunch GHS NM output to determine what code is taking up the most space
#
# Author:   Chip Boling
#   Date:   Dec. 18, 2014
#
# When using GNM to create the input file, use the '-h -v -p -no_debug -S -a -X' options for best results

library(data.table)
library(stringr)
library(plyr)

########################################
# Customized global

discardSections <- c("(UNDEF)", "syscall")

cleanupSymbolNames <- function(inputData, verbose)
{
    ## Do some name mangling and path cleanup to make the symbol names more reasonable
    #
    # Convert the .2F to a slash '/'

    inputData$symbol <- gsub(".2F", "/", inputData$symbol)

    # Now look for ../ in the symbol name and use it to split into a symbol and file name.
    # Not all symbols (library/stl/...) may have a file name. Best way is to replace '../'
    # with a space and then use split.  We know that a space is not already present as that is
    # what we used to read the file in from disk.

    inputData$symbol <- gsub("../", " ", inputData$symbol)

    #inputData$file <- as.character(NA)

    #getFilename <- function(delim="../")
    #{
    #    if (grepl(delim, inputData$symbol))
    #    {
    #        location <- str_locate()
    #    }
    #}

    return(inputData)
}

cleanupColumns <- function(inputData, verbose)
{
    # Discard undesired Sections

    inputData <- inputData[!inputData$section %in% discardSections, ]

    # Perform major cleanup of the symbol names

    cleanupSymbolNames(inputData, verbose)
}

readInputFile <- function(inputPath, verbose)
{
    print(sprintf("Reading input file: '%s'", inputPath))
    classes   <- c(A="numeric", B="factor", C="character")
    #inputData <- fread(inputPath, header=FALSE, colClasses=classes)
    inputData <- as.data.table(read.table(inputPath, sep="", header=FALSE, colClasses=classes))

    # Input is expected to have 3 columns

    cNameOld <- c("V1", "V2", "V3")
    cNameNew <- c("address", "section", "symbol")

    if (ncol(inputData) != 3)
    {
        msg <- sprintf("Input file did not have 3 columns, found %d",ncol(inputData))
        if (ncol(inputData) < 3)
        {
            stop(msg)
        }
        else
        {
            warning(msg)
        }
        idx = 4
        while (idx <= ncol(inputData))
        {
            cNameOld <- append(cNameOld, sprintf("V%d", idx))
            cNameNew <- append(cnameNew, sprintf("V%d", idx))
            idx <- idx + 1
        }
    }
    # Give columns some useful names

    setnames(inputData, cNameOld, cNameNew)

    # Scrub N/A records

    numRowsBefore =nrow(inputData)

    na.omit(inputData)

    if (verbose & numRowsBefore != nrow(inputData))
    {
        print(sprintf("Input reduced from by %d rows (from %d) by omitting NA's",
                      numRowsBefore - nrow(inputData), numRowsBefore))
    }
    # Cleanup our columns

    cleanupColumns(inputData, verbose)
}

createSectionTables <- function(inputData, verbose)
{
    tableList <- vector("list")
    sections  <- inputData$section

    for (sect in sections)
    {
        table <- inputData[inputData$section==sect,]
        table <- table[,section:=NULL]

        tableList <- append(tableList, table)
        print("x")
    }


    return(tableList)
}


code_size <- function(inputFile="ram.nm.txt",
                      outputFile="results.txt",
                      inputDir="./data",
                      outputDir="./output",
                      verbose=TRUE)
{
    ## Compute the size requirements from each file
    ##
    ## inputFile  - Input NM filename created with GHS 'gnm' and the '-h -v -p -S -a -X'
    ##              options.  Default is 'ram.nm.txt'
    ##
    ## outputFile - Output results filename.  Default is 'results.txt'
    ##
    ## inputDir   - Input base directory.  Default is './data'
    ##
    ## outputDir  - Output base directory.  Default is './output'
    ##
    ## verbose    - Verbose output flag for debugging purposes

    # Make sure output directory exists

    if (!file.exists(outputDir)) { dir.create(outputDir) }

    # Read our input data

    inputData<- readInputFile(file.path(inputDir, inputFile), verbose)

    # Create separate tables based on section

    tableList <- createSectionTables(inputData, verbose)

    print ("Done...")
}
