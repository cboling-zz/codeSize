GHS Code Size
=============

Crunch GHS NM output to determine what code is taking up the most space


Author:   Chip Boling
  Date:   Dec. 18, 2014

When using GNM to create the input file, use the '-h -v -p -no_debug -S -a -X' options
for best results.  For example, with **input.bin** as the ELF image create by *multi* and
**nm.txt** as the path/filename.

    $ gnm -h -v -p -no_debug -S -a -X input.bin > /tmp/nm.output.txt

Then run the script, such as:
    
    $ R --quiet --no-save
    > source "codeSize.R"
    > source ("codeSize.R")
    > code_size(inputDir="/tmp", inputFile="nm.output.txt", verbose=TRUE)
    > 

Enter ^D to exit from **R**.  The output will is sent to *stdout*

The parameters to the *code_size()* function are:

Parameter   | Description
----------- | ------------
inputFile   | Input NM filename created with GHS *'gnm'* and the *'-h -v -p -S -a -X'* options.  Default is **'ram.nm.txt'**
inputDir    | Input base directory.  Default is the current working directory
minSymSize  | Minimum symbol size (in octets). All symbols smaller than this will be discarded. Default is **1 octet** (*zero* length symbols discarded)
minSectSize | Minimum section size (in octets). All sections smaller than this will be discarded. Default is **256 octets**
maxSymbolCuttoff | Size a symbol must be to make it into the maximum symbol report. Default is **4096 octets**
verbose     | Verbose output flag for debugging purposes

