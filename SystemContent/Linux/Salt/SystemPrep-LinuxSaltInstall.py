#!/usr/bin/env python
import sys

def main(**kwargs):
    scriptname = __file__

    print('+' * 80)
    print('Entering script -- ' + scriptname)
    print('Printing parameters...')
    for key, value in kwargs.items():
        print('    ' + str(key) + ' = ' + str(value))

    #TODO: do stuff
    
    print(str(scriptname) + ' complete!')
    print('-' * 80)


if __name__ == "__main__":
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    main(**kwargs)
