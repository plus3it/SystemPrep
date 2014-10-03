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
        SystemError('Failed to merge dictionaries. Dictionary A:\n\n' + a + '\n\nDictionary B:\n\n' + b)

    return a_copy


def getScriptsToExecute(system, workingdir, **scriptparams):
    """
Returns an array of hashtables. Each hashtable has two keys: 'ScriptUrl' and 'Parameters'.
'ScriptUrl' is the url of the script to be downloaded and execute.
'Parameters' is a hashtable of parameters to pass to the script.
    """

    if 'Linux' in system:
        scriptstoexecute = (
            { 
                'ScriptUrl'  : "https://systemprep.s3.amazonaws.com/SystemContent/Linux/Salt/SystemPrep-LinuxSaltInstall.py",
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


def createWorkingDir(basedir, dirprefix):
    """
Creates a directory in 'basedir' with a prefix of 'dirprefix'.
The directory will have a random 5 character string appended to 'dirprefix'.
Returns the path to the working directory.
    """
    
    try:
        workingdir = tempfile.mkdtemp(prefix=dirprefix, dir=basedir)
    except:
        SystemError('Could not create workingdir in ' + str('basedir'))

    return workingdir


def getSystemParams(system):
    """
Returns a dictionary of OS platform-specific parameters.
    """
    
    dict_a = {}
    workingdirprefix = 'systemprep'
    if 'Linux' in system:
        tempdir = '/usr/tmp/'
        dict_a['pathseparator'] = '/'
        dict_a['readyfile'] = '/var/run/system-is-ready'
        # dict_a['restart'] = 
    #TODO: Add Windows parameters
    elif 'Windows' in system:
        systemroot = os.environ['SYSTEMROOT']
        systemdrive = os.environ['SYSTEMDRIVE']
        tempdir = os.environ['TEMP']
        dict_a['pathseparator'] = '\\'
        dict_a['readyfile'] = systemdrive + '\system-is-ready'
        dict_a['restart'] = systemroot + '\system32\shutdown.exe/r /t 30 /d p:2:4 /c "SystemPrep complete. Rebooting computer."'
    else:
        raise SystemError('System, ' + system + ', is not recognized?')

    dict_a['workingdir'] = createWorkingDir(tempdir, workingdirprefix)

    return dict_a


def downloadFile(url, filename):
    import urllib.request
    import shutil

    # Download the file from `url` and save it locally under `filename`:
    try:
        with urllib.request.urlopen(url) as response, open(file_name, 'wb') as out_file:
            shutil.copyfileobj(response, out_file)
    except:
        raise SystemError('Unable to download and save file. Url =\n\n    ' + url + '\n\nfilename = \n\n    ' + filename)
        
    print('Downloaded file -- ' + url)


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

    scriptname = __file__

    print('+' * 80)
    print('Entering script -- ' + scriptname)
    print('Printing parameters...')
    for key, value in kwargs.items():
        print('    ' + str(key) + ' = ' + str(value))

    system = platform.system()
    systemparams = getSystemParams(system)
    scriptstoexecute = getScriptsToExecute(system, workingdir, **kwargs)

    # #Loop through each 'script' in scriptstoexecute
    # for script in scriptstoexecute:
        # filename = script['ScriptUrl'].split('/')[-1]
        # fullfilepath = systemparams['workingdir'] + systemparams['pathseparator'] + filename
        # #Download each script, script['ScriptUrl']
        # downloadFile(script['ScriptUrl'], fullfilepath)
        # #Execute each script, passing it the parameters in script['Parameters']
        # os.system('python ' + fullfilepath + script['Parameters']) ## likely a dirty hack, probably want to code the python sub-script with an importable module instead

    # cleanup(systemparams['workingdir'])

    # if 'True' == kwargs['NoReboot']:
        # print('Detected NoReboot switch. System will not be rebooted.')
    # else:
        # print('Reboot scheduled. System will reboot in 30 seconds')
        # os.system(systemparams['restart'])

    print(str(scriptname) + 'complete!')
    print('-' * 80)
    raw_input("\n\nPress the enter key to exit.")


if __name__ == "__main__":
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    main(**kwargs)