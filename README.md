GHS Code Size
=============

Crunch GHS NM output to determine what code is taking up the most space


Author:   Chip Boling
  Date:   Dec. 18, 2014

When using GNM to create the input file, use the '-h -v -p -no_debug -S -a -X' options
for best results.  For example, with **input.bin** as the ELF image create by *multi* and
**nm.txt** as the path/filename.

    $ gnm -h -v -p -no_debug -S -a -X input.bin > /tmp/nm.output.txt


Then run the script, make sure that 'codeSize.R' is executable, **chmod +x codesize.R** and
then just enter:

    $ *./codeSize.R*.

To see allowed options, enter the command:
    
    $ ./codeSize.R --help
    Usage: ./codeSize.R [-[-file|f] [<inputFile>]] [-[-dir|d] [<inputDir>]]
                        [-[-symSize|s] [<minSymSize>]] [-[-secSize|S] [<minSectSize>]]
                        [-[-maxSymb|m] [<maxSymbolCutoff>]] [-[-verbose|v]] [-[-help|?]]\
    where:
        -f|--file       The input file name, default is nm.txt
        -d|--dir        The input base directory, default is current working directory
        -s|--symSize    Discard symbols smaller than this. Default is 1 octet
        -S|--secSize    Discard sections smaller than this. Default is 256 octets
        -m|--maxSymb    Only report symbols this size and larger in max symbol report. Deault is 4096 octets
        -v|--verbose    Enable verbose output
        -?|--help       Print out help text

The output will is sent to *stdout*

The parameters to the *code_size* function are:

Parameter   | Description
----------- | ------------
inputFile   | Input NM filename created with GHS *'gnm'* and the *'-h -v -p -S -a -X'* options.  Default is **'ram.nm.txt'**
inputDir    | Input base directory.  Default is the current working directory
minSymSize  | Minimum symbol size (in octets). All symbols smaller than this will be discarded. Default is **1 octet** (*zero* length symbols discarded)
minSectSize | Minimum section size (in octets). All sections smaller than this will be discarded. Default is **256 octets**
maxSymbolCutoff | Size a symbol must be to make it into the maximum symbol report. Default is **4096 octets**
verbose     | Verbose output flag for debugging purposes
