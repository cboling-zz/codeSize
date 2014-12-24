#!/usr/bin/Rscript
################################################################################
#
# Crunch GHS NM output to determine what code is taking up the most space
#
# Author:   Chip Boling
#   Date:   Dec. 18, 2014
#
# When using GNM to create the input file, use the '-h -v -p -no_debug -S -a -X' options
# for best results

########################################
# Customized global

local
discardSections <- c("(UNDEF)", "syscall")

demangleCppNames  <- function(inputData, verbose)
{
    # Demangle C++ names as much as possible

    # No parameters in function
    inputData$symbol <- gsub("__Fv$", "()", inputData$symbol)

    # C++ destructor and constructor(no parameters)
    inputData$symbol <- sub("^__dt__([0-9]+)(.*)Fv$", "~\\2::\\2(void)", inputData$symbol)
    inputData$symbol <- sub("^__ct__([0-9]+)(.*)Fv$", "~\\2::\\2(void)", inputData$symbol)

    return(inputData)
}

cleanupSymbolNames <- function(inputData, verbose)
{
    ## Do some name mangling and path cleanup to make the symbol names more reasonable

    if (verbose) { print("Cleaning up filenames")}

    # Convert the .2F to a slash '/'.  This covers most source files.  Then delete any
    # ..[num] at end of line.

    inputData$symbol <- gsub(".2F", "/", inputData$symbol, fixed=TRUE)
    inputData$symbol <- sub("..([0-9]+)$", "", inputData$symbol)

    # Now look for ../ in the symbol name and use it to split into a symbol and file name.
    # Not all symbols (library/stl/...) may have a file name. Best way is to replace the first
    # '../' with a space and then use split. We know that a space is not already present as
    # that is what we used to read the file in from disk.

    if (verbose) { print("Creating separate symbol and filename columns")}

    inputData$symbol <- sub(".../", " /", inputData$symbol, fixed=TRUE)
    inputData$symbol <- sub("../", " /", inputData$symbol, fixed=TRUE)
    inputData$symbol <- sub("./", " /", inputData$symbol, fixed=TRUE)
    inputData$symbol <- sub("..", " /", inputData$symbol, fixed=TRUE)

    getSymbol   <- function(x) { str_split(x, " ", n=2)[[1]][1] }
    getFilename <- function(x) { str_split(x, " ", n=2)[[1]][2] }

    inputData[, file:=getFilename(symbol), by=symbol]
    inputData[, symbol:=getSymbol(symbol), by=symbol]

    demangleCppNames(inputData)
}

cleanupColumns <- function(inputData, verbose)
{
    # Discard undesired Sections

    if (verbose) { print("Discarding undesirable sections")}

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
        for (idx in 4:ncol(inputData))
        {
            cNameOld <- append(cNameOld, sprintf("V%d", idx))
            cNameNew <- append(cnameNew, sprintf("V%d", idx))
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

createSizeColumn <- function(inputData, tableName, verbose)
{
    # Create the 'size' column for each symbol

    if (verbose) { print(sprintf("  Creating 'size' column for '%s' section table", tableName)) }

    inputData$size <- as.numeric(NA)

    if (nrow(inputData) > 1)
    {
        for (row in 2:nrow(inputData))
        {
            prevSize <- inputData$address[[row - 1]]
            thisSize <- inputData$address[[row]]

            inputData$size[row] <- thisSize - prevSize
        }
    }
    setcolorder(inputData, c("address", "size", "symbol", "file"))

    return(inputData)
}

discardSmallSymbols <- function(inputData, minSize, tableName, verbose)
{
    # Discard symbols smaller than 'minSize'

    if (verbose)
    {
        print(sprintf("  Dropping symbols smaller than %d octets for '%s' table",
                      minSize, tableName))
    }
    nbefore   <- nrow(inputData)
    inputData <- inputData[!is.na(inputData$size) & inputData$size >= minSize,]

    if (verbose & nbefore > nrow(inputData))
    {
        print(sprintf("    Dropped %d small symbols from '%s' table",
                      nbefore - nrow(inputData), tableName))
    }
    return(inputData)
}

createSectionTables <- function(inputData, minSymSize, verbose)
{
    # This function takes the input data and creates a unique data.table object for each
    # section.  It then returns a named list of data.table objects where the list element
    # name is the section.  ie) tableList[['.text']] will return the data.table related
    # to the ".text" section

    tableList <- list()
    sections  <- unique(inputData$section)
    idx       <- 1

    for (sect in sections)
    {
        if (verbose) { print(sprintf("Creating section table for section '%s'", sect))}

        # Extract separate table and drop the section column.  Make the 'address' column
        # the index

        table     <- inputData[inputData$section==sect,]
        table     <- table[,section:=NULL]
        tableName <- sect

        setkey(table, address)

        table <- createSizeColumn(table, tableName, verbose)

        if (minSymSize > 0)
        {
            table <- discardSmallSymbols(table, minSymSize, tableName, verbose)
        }
        tableList[[idx]]      <- table
        names(tableList)[idx] <- tableName
        idx                   <- idx + 1
    }
    return(tableList)
}

discardSmallSections <- function(tableList, minSize, verbose)
{
    # Discard empty sections and sections smaller than 'minSize'

    if (verbose) { print(sprintf("Dropping section tables smaller than %d octets", minSize)) }

    finalList <- list()
    idx      = 1
    finalIdx = 1

    for (table in tableList)
    {
        tableName <- names(tableList)[idx]
        sectSize  <- sum(table$size, na.rm=TRUE)

        if (sectSize >= minSize)
        {
            finalList[[finalIdx]]      <- table
            names(finalList)[finalIdx] <- tableName
            finalIdx = finalIdx + 1

            if (verbose) { print(sprintf("  Section %s is %d octets", tableName, sectSize)) }
        }
        else if (verbose)
        {
            print(sprintf("  Dropped section %s. Only %d octets", tableName, sectSize))
        }
        idx <- idx + 1
    }
    return(finalList)
}

outputSectionReport <- function(tableList)
{
    print("------------------------------------------------")
    print("Symbol Table Results")
    print("--------------------\n")
    print("          Table :     Size");

    idx <- 1

    for (table in tableList)
    {
        tableName <- names(tableList)[idx]
        sum       <- sum(table$size)

        print(sprintf(" %14s : %9d", tableName, sum))
        idx <- idx + 1
    }
    invisible()
}

# Output largest symbols (per table)

outputLargestSymbols <- function(tableList, cutoff, maxLines)
{
    print("------------------------------------------------")
    print(sprintf("Largest Symbol per section by descending size. Report minimum = %d octets", cutoff))
    print("--------------------------------------------------------------------------------------")
    print("")

    idx <- 1

    for (table in tableList)
    {
        na.omit(table, cols="size")
        subTable <- table[table$size >= cutoff, ]

        if (nrow(subTable) > 0)
        {
            # And sort it

            subTable <- setorder(subTable, -size)

            # Output Results
            max <- nrow(subTable)
            if (maxLines < max)
            {
                max <- maxLines
            }
            print(sprintf("  Section: %s.  %d rows of %d", names(tableList)[idx], max,
                         nrow(table)))
            print("         Size :                                   Symbol  : File");

            for (row in 1:max)
            {
                print(sprintf("    %9d : %40s : %s", as.integer(subTable$size[row]),
                              subTable$symbol[row], subTable$file[row]))
            }
            print("")
            print("    -------------------------------------------")
            print("")
        }
        idx <- idx + 1
    }
    invisible()
}

# Output symbols sizes by directory

outputDirectorySizes <- function(tableList, cutoff, maxLines)
{
    print ("------------------------------------------------")
    print (sprintf("Largest directories  Report minimum = %d octets", cutoff))
    print ("")
    print ("   TODO:   Not yet implemented")
    print ("")


    invisible()
}

# Output symbols sizes by directory/file

outputFileSizes <- function(tableList, cutoff, maxLines)
{
    print ("------------------------------------------------")
    print (sprintf("Largest files.  Report minimum = %d octets", cutoff))
    print ("")
    print ("   TODO:   Not yet implemented")
    print ("")


    invisible()
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

checkPkgs <- function(pkgs, repo)
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

code_size <- function(inputFile="./nm.txt",
                      minSymSize=1,
                      minSectSize=256,
                      maxSymbolCutoff=4096,
                      maxDirCutoff=128 * 1024,
                      maxFileCutoff=64 * 1024,
                      maxLines=100,
                      csvOutput="",
                      verbose=FALSE)
{
    ## Compute the size requirements from each file
    ##
    ## inputFile   - Input NM file path created with GHS 'gnm' and the '-h -v -p -S -a -X'
    ##               options.  Default is './nm.txt'
    ##
    ## minSymSize  - Minimum symbol size (in octets). All symbols smaller than this will be
    ##               discarded. Default is 1 octet (zero length symbols discarded)
    ##
    ## minSectSize - Minimum section size (in octets). All sections smaller than this will be
    ##               discarded. Default is 256 octets
    ##
    ## maxSymbolCutoff - Size a symbol must be to make it into the maximum symbol report.
    ##                   Default is 4096
    ##
    ## maxDirCutoff  - Size that the sum of all symbols in a directory (and
    ##                  subdirectories) must be to make it into the directory report.
    ##                  Default is 128K.
    ##
    ## maxFileCutoff - Size that the sum of all symbols in a file must be to make it into the
    ##                 file report.  Default is 64K.
    ##
    ## csvOutput     - Output filename for CSV output for entire data.  By default no CSV
    ##                 output is generated.
    # Read our input data

    inputData <- readInputFile(inputFile, verbose)

    # Create separate tables based on section

    tableList <- createSectionTables(inputData, minSymSize, verbose)

    # Toss out small tables

    if (minSectSize > 0)
    {
        nbefore   <- length(tableList)
        tableList <- discardSmallSections(tableList, minSectSize, verbose)

        if (verbose & nbefore > length(tableList))
        {
            print(sprintf("Dropped %d small sections tables", nbefore - length(tableList)))
        }
    }
    # Output the section report

    outputSectionReport(tableList)

    # Output largest symbols

    outputLargestSymbols(tableList, maxSymbolCutoff, maxLines)

    # Output largest directories

    outputDirectorySizes(tableList, maxDirCutoff, maxLines)

    # Output largest directories

    outputFileSizes(tableList, maxFileCutoff, maxLines)

    # CSV output if requested

    if (length(csvOutput) > 0)
    {
        outputCsvFile(tableList, csvOutput)
    }
    print ("------------------------------------------------")
    print ("Done...")
}

####################################################################################
#
# Make sure we have all required packages
#
checkPkgs(c("Rcpp", "plyr", "stringr", "data.table", "getopt"),
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
        'file',     'f', '2', 'character', 'The input file name, default is nm.txt',
        'dir',      'd', '2', 'character', 'The input base directory, default is current working directory',
        'symSize',  's', '2', 'integer',   'Discard symbols smaller than this. Default is 1 octet',
        'secSize',  'S', '2', 'integer',   'Discard sections smaller than this. Default is 256 octets',
        'maxSymb',  'm', '2', 'integer',   'Only report symbols this size and larger in max symbol report. Deault is 4096 octets',
        'dirSize',  'D', '2', 'integer',   'Size that the sum of all symbols in a directory (and subdirectories) must be to make it into the directory report. Default is 128K.',
        'fileSize', 'F', '2', 'integer',   'Size that the sum of all symbols in a file must be to make it into the file report.  Default is 64K.',
        'maxLines', 'M', '2', 'integer',   'Maximum number of output lines per report/sub-report for sections that may have many.  Default is 100.',
        'output',   'o', '2', 'character', 'Output CSV filename for cleaned map.  Default is "" (no CSV output)',
        'verbose',  'v', '0', 'logical',   'Enable verbose output',
        'help',     '?', '0', 'logical',   'Print out help text'
        ), byrow=TRUE, ncol=5)

    opt = getopt(spec);

    # Asked for help?
    if (!is.null(opt$help))
    {
        cat(getopt(spec, usage=TRUE))
        q(status=1)
    }
    # Update defaults here and also in the 'code_size' function if you want consistent behaviour
    # from within RStudio (debugging) and from the command line

    if (is.null(opt$file))     { opt$file     = "./nm.txt" }
    if (is.null(opt$symSize))  { opt$symSize  = 1     }
    if (is.null(opt$secSize))  { opt$secSize  = 256   }
    if (is.null(opt$maxSymb))  { opt$maxSymb  = 4096  }
    if (is.null(opt$dirSize))  { opt$dirSize  = 128 * 1024  }
    if (is.null(opt$fileSize)) { opt$fileSize = 64 * 1024  }
    if (is.null(opt$maxLines)) { opt$maxLines = 100   }
    if (is.null(opt$verbose))  { opt$verbose  = FALSE }
    if (is.null(opt$output))   { oupt$output  = ""    }

    code_size(inputFile=opt$file,
              minSymSize=opt$symSize,
              minSectSize=opt$secSize,
              maxSymbolCutoff=opt$maxSymb,
              maxDirCutoff=opt$dirSize,
              maxFileCutoff=opt$fileSize,
              maxLines=opt$maxLines,
              csvOutput=opt$output,
              verbose=opt$verbose)
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
    else
    {
        code_size()
    }
}
