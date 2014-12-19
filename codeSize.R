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

codeSize <- local(
{
    ########################################
    # Customized global

    discardSections <- c("(UNDEF)", "syscall")

    cleanupSymbolNames <- function(inputData, verbose)
    {
        ## Do some name mangling and path cleanup to make the symbol names more reasonable
        #
        # Convert the .2F to a slash '/'

        if (verbose) { print("Cleaning up filenames")}

        inputData$symbol <- gsub(".2F", "/", inputData$symbol)

        # Now look for ../ in the symbol name and use it to split into a symbol and file name.
        # Not all symbols (library/stl/...) may have a file name. Best way is to replace the first
        # '../' with a space and then use split. We know that a space is not already present as
        # that is what we used to read the file in from disk.

        if (verbose) { print("Creating separate symbol and filename columns")}

        inputData$symbol <- sub("../", " ", inputData$symbol, fixed=TRUE)

        getSymbol   <- function(x) { str_split(x, " ", n=2)[[1]][1] }
        getFilename <- function(x) { str_split(x, " ", n=2)[[1]][2] }

        inputData[, file:=getFilename(symbol), by=symbol]
        inputData[, symbol:=getSymbol(symbol), by=symbol]

        return(inputData)
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
        idx = 1

        for (table in tableList)
        {
            tableName <- names(tableList)[idx]
            sectSize  <- sum(table$size, na.rm=TRUE)

            if (sectSize >= minSize)
            {
                finalList[[idx]]      <- table
                names(finalList)[idx] <- tableName
                idx                   <- idx + 1

                if (verbose) { print(sprintf("  Section %s is %d octets", tableName, sectSize)) }
            }
            else if (verbose)
            {
                print(sprintf("  Dropped section %s. Only %d octets", tableName, sectSize))
            }
        }
        return(finalList)
    }


    outputSectionReport <- function(tableList)
    {
        print ("------------------------------------------------")
        print ("Symbol Table Results")
        print ("")
        print ("   TODO:   Not yet implemented")
        print ("")
    }

    # Output largest symbols

    outputLargestSymbols <- function(tableList, cutoff)
    {
        print ("------------------------------------------------")
        print (sprintf("Largest Symbol per section.  Report minimum = %d octets", cutoff))
        print ("")
        print ("   TODO:   Not yet implemented")
        print ("")
    }
    checkPkgs <- function()
    {
        pkg.inst <- installed.packages()
        pkgs     <- c("data.table", "stringr", "plyr")
        have.pkg <- pkgs %in% rownames(pkg.inst)

        if (any(!have.pkg))
        {
            message("\nSome packages need to be installed.\n")
            r <- readline("Install necessary packages [y/n]? ")
            if(tolower(r) == "y")
            {
                need <- pkgs[!have.pkg]
                message("\nInstalling packages ",
                        paste(need, collapse = ", "))
                install.packages(need)
            }
        }
    }

    function(inputFile="nm.txt",
             inputDir=getwd(),
             minSymSize=1,
             minSectSize=256,
             maxSymbolCuttoff=4096,
             verbose=FALSE)
    {
        #code_size <- function(inputFile="nm.txt",
        #                  inputDir=getwd(),
        #                  minSymSize=1,
        #                  minSectSize=256,
        #                  maxSymbolCuttoff=4096,
        #                  verbose=FALSE)

        ## Compute the size requirements from each file
        ##
        ## inputFile   - Input NM filename created with GHS 'gnm' and the '-h -v -p -S -a -X'
        ##               options.  Default is 'ram.nm.txt'
        ##
        ## inputDir    - Input base directory.  Default is the current working directory.
        ##
        ## minSymSize  - Minimum symbol size (in octets). All symbols smaller than this will be
        ##               discarded. Default is 1 octet (zero length symbols discarded)
        ##
        ## minSectSize - Minimum section size (in octets). All sections smaller than this will be
        ##               discarded. Default is 256 octets
        ##
        ## maxSymbolCuttoff - Size a symbol must be to make it into the maximum symbol report.
        ##                    default is 4096
        ## verbose     - Verbose output flag for debugging purposes

        checkPkgs()
        suppressPackageStartupMessages(library(data.table))

        library(data.table)
        library(stringr)
        library(plyr)

        # See if running for RStudio or command lien

        cmdArgs <- commandArgs()

        print(cmdArgs)
        #summary(cmdArgs)

        # Make sure output directory exists

        # Read our input data

        inputData <- readInputFile(file.path(inputDir, inputFile), verbose)

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

        outputLargestSymbols(tableList, maxSymbolCuttoff)

        print ("------------------------------------------------")
        print ("Done...")
    }

})
