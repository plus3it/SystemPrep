#!/usr/bin/env python
import os
import sys
import platform
import tempfile

def cleanup(workingdir):
    print('+-' * 40)
    print('Cleanup Time...')
    print('Removing temporary data...')
    try:
        os.removedirs(workingdir)
    except:
        raise SystemError('Cleanup Failed!')


def main(**kwargs):
    """
Master Script that calls subscripts to be deployed to new Linux systems
    """

    scriptname = sys.argv[0]
    #Logic to define variables based on OS
    if 'Windows' in platform.system():
        #workingdir = 'C:\WINDOWS\TEMP\SYSTEMPREP'
        workingdir = 'C:\WINDOWS\TEMP'
        readyfile = 'C:\WINDOWS\TEMP\system-is-ready'
    elif 'Linux' in platform.system():
        #workingdir = '/usr/tmp/systemprep'
        workingdir = '/usr/tmp/'
        readyfile = '/var/run/system-is-ready'
    else:
        raise SystemError('platform.system() is not recognized?')

    print('+' * 80)
    print('Entering script -- ' + scriptname)
    if not os.path.exists(readyfile):
        raise SystemError(readyfile + ' does not exist! System is not ready?')

    if os.path.exists(workingdir):
        print('Creating working directory.')
        workingdir = tempfile.mkdtemp(prefix='systemprep-', dir=workingdir)
        print(workingdir)
    else:
        raise SystemError('Defined workingdir does not exist!')

    print('Printing parameters...')
    print('kwargs = ' + str(kwargs))

    for key, value in kwargs.items():
        print(str(key) + ' = ' + str(value))

    cleanup(workingdir)
    print('-' * 80)
#    raw_input("\n\nPress the enter key to exit.")


if __name__ == "__main__":
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    main(**kwargs)