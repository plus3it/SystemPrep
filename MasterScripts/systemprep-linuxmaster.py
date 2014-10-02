#!/usr/bin/env python 

import sys

####################################################################################
#Master Script that calls subscripts to be deployed to new Linux systems
####################################################################################

def main(*args,**kwargs) :

    #System variables
    scriptname = sys.argv[0]
    workingdir = '/usr/tmp/systemprep'
    readyfile = '/var/run/system-is-ready'
    scriptstart = '+' * 80
    scriptend = '-' * 80

    print ( str(scriptstart) )
    print ( 'Entering script -- ' + str(scriptname) )
    print ( 'Printing parameters...' )

    print 'kwargs = ', kwargs
    for key,value in kwargs.items() :
        print ( str(key) + ' = ' + str(value) )

#    raw_input("\n\nPress the enter key to exit.")

if __name__ == "__main__" :
    kwargs = dict( x.split('=', 1) for x in sys.argv[1:] )
    main(**kwargs)

