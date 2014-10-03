#!/usr/bin/env python
import os
import sys
import platform
import tempfile


def mergeDicts(a, b):
    """
Merge two dictionaries. If there is a key collision, 'b' overrides 'a'.
    """
    try:
        a_copy = a.copy()
        a_copy.update(b)
    except:
        SystemError('Must pass only dictionaries to mergeDicts. One of these is not a dictionary: ' + a + ' , ' + b)

    return a_copy


def getScriptsToExecute(system,workingdir,**scriptparams):
    """
Returns an array of hashtables. Each hashtable has two keys: ScriptUrl and Parameters.
'ScriptUrl' is the url of the script to be downloaded and execute.
'Parameters' is a hashtable of parameters to pass to the script.
    """

    if 'Linux' in system:
        scriptstoexecute = (
            { 
            'ScriptUrl'  : "https://systemprep.s3.amazonaws.com/SystemContent/Linux/Salt/SystemPrep-LinuxSaltInstall.ps1",
            'Parameters' : mergeDicts({ 
                              'SaltWorkingPath' : workingdir + '/systemcontent/linux',
                              'SaltContentUrl' : "https://systemprep.s3.amazonaws.com/SystemContent/Linux/Salt/salt-content.zip" ,
                              'FormulasToInclude' : (
                                                        "https://salt-formulas.s3.amazonaws.com/ash-linux-formula-latest.zip", 
                                                    ),
                              'FormulaTerminationStrings' : ( "-latest" ),
                              'SaltStates' : 'Highstate',
                           }, scriptparams)
            },
        )
    #TODO: Add Windows parameters
    else:
        raise SystemError('System, ' + system + ', is not recognized?')

    return scriptstoexecute


def getOsParams():
    """
Returns a dictionary of OS platform-specific parameters.
    """
    dict_a = {}
    system = platform.system()
    if 'Linux' in system:
        tempdir = '/usr/tmp/'
        dict_a['readyfile'] = '/var/run/system-is-ready'
        dict_a['restart'] = 
    #TODO: Add Windows parameters
    # elif 'Windows' in system:
        # systemroot = os.environ['SYSTEMROOT']
        # systemdrive = os.environ['SYSTEMDRIVE']
        # tempdir = os.environ['TEMP']
        # dict_a['readyfile'] = systemdrive + '\system-is-ready'
        # dict_a['restart'] = systemroot + '\system32\shutdown.exe/r /t 30 /d p:2:4 /c "SystemPrep complete. Rebooting computer."'
    else:
        raise SystemError('System, ' + system + ', is not recognized?')

    if os.path.exists(tempdir):
        print('Creating working directory.')
        dict_a['workingdir'] = tempfile.mkdtemp(prefix='systemprep-', dir=tempdir)
        print(str(dict_a['workingdir']))
    else:
        raise SystemError('Defined tempdir does not exist! tempdir = ' + str('tempdir'))

    return dict_a


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

    print('+' * 80)
    print('Entering script -- ' + scriptname)
    print('Printing parameters...')
    for key, value in kwargs.items():
        print('    ' + str(key) + ' = ' + str(value))

    system = platform.system()
    osparams = getOsParams(system)
    scriptstoexecute = getScriptsToExecute(system,workingdir,**kwargs)

    #TODO: Add logic to loop through each 'script' in scriptstoexecute
    #Download each script, script['ScriptUrl']
    #Execute each script, passing it the parameters in script['Parameters']

    cleanup(osparams['workingdir'])

    if 'True' == kwargs['NoReboot']:
        print('Detected NoReboot switch. System will not be rebooted.')
    else:
        print('Reboot scheduled. System will reboot in 30 seconds')
        os.system(osparams['restart'])

    print(str(scriptname) + 'complete!')
    print('-' * 80)
#    raw_input("\n\nPress the enter key to exit.")


if __name__ == "__main__":
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    main(**kwargs)