#!/usr/bin/env python
import os
import sys
import platform
import tempfile
import urllib2
import shutil


def mergeDicts(a, b):
    """
Merge two dictionaries. If there is a key collision, `b` overrides `a`.
    :param a: Dictionary of default settings
    :param b: Dictionary of override settings
    :rtype : dict
    """
    
    try:
        a.update(b)
    except:
        SystemError('Failed to merge dictionaries. Dictionary A:\n\n' + a + '\n\nDictionary B:\n\n' + b)
    
    return a


def getScriptsToExecute(system, workingdir, **scriptparams):
    """
Returns an array of hashtables. Each hashtable has two keys: 'ScriptUrl' and 'Parameters'.
'ScriptSource' is the path to the script to be executed. Only supports http/s sources currently.
'Parameters' is a hashtable of parameters to pass to the script.
Use `mergeDicts({yourdict}, scriptparams)` to merge command line parameters with a set of default parameters.
    :param system: str, the system type as returned from `platform.system`
    :param workingdir: str, the working directory where content should be saved
    :param scriptparams: dict, parameters passed to the master script which should be relayed to the content scripts
    :rtype : dict
    """

    if 'Linux' in system:
        scriptstoexecute = (
            { 
                'ScriptSource'  : "https://systemprep.s3.amazonaws.com/SystemContent/Linux/Salt/SystemPrep-LinuxSaltInstall.py",
                'Parameters'    : mergeDicts({
                                              'SaltWorkingPath' : workingdir + '/systemcontent/linux',
                                              'SaltContentUrl' : "https://systemprep.s3.amazonaws.com/SystemContent/Linux/Salt/salt-content.zip" ,
                                              'FormulasToInclude' : (
                                                                        "https://salt-formulas.s3.amazonaws.com/ash-linux-formula-latest.zip",
                                                                    ),
                                              'FormulaTerminationStrings' : ( "-latest", ),
                                              'SaltStates' : 'Highstate',
                                             }, scriptparams)
            },
        )
    elif 'Windows' in system:
        scriptstoexecute = (
            {
                'ScriptSource'  : "https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1",
                'Parameters'    : mergeDicts({
                                              'SaltWorkingDir' : workingdir + '\\SystemContent\\Windows\\Salt',
                                              'SaltContentUrl' : "https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/salt-content.zip",
                                              'FormulasToInclude' : (
                                                                        "https://salt-formulas.s3.amazonaws.com/ash-windows-formula-latest.zip",
                                                                    ),
                                              'FormulaTerminationStrings' : ( "-latest", ),
                                              'AshRole' : "MemberServer",
                                              'NetBannerString' : "Unclass",
                                              'SaltStates' : "Highstate",
                                             }, scriptparams)
            },
        )
    else:
        raise SystemError('System, ' + system + ', is not recognized?')
    
    return scriptstoexecute


def createWorkingDir(basedir, dirprefix):
    """
Creates a directory in `basedir` with a prefix of `dirprefix`.
The directory will have a random 5 character string appended to `dirprefix`.
Returns the path to the working directory.
    :rtype : str
    :param basedir: str, the directory in which to create the working directory
    :param dirprefix: str, prefix to prepend to the working directory
    """
    workingdir = None
    try:
        workingdir = tempfile.mkdtemp(prefix=dirprefix, dir=basedir)
    except:
        SystemError('Could not create workingdir in ' + str('basedir'))

    return workingdir


def getSystemParams(system):
    """
Returns a dictionary of OS platform-specific parameters.
    :param system: str, the system type as returned by `platform.system`
    :rtype : dict
    """
    
    a = {}
    workingdirprefix = 'systemprep-'
    if 'Linux' in system:
        tempdir = '/usr/tmp/'
        a['pathseparator'] = '/'
        a['readyfile'] = '/var/run/system-is-ready'
        a['restart'] = 'shutdown -r +1 &'
    #TODO: Add and test more Windows parameters/functionality
    elif 'Windows' in system:
        systemroot = os.environ['SYSTEMROOT']
        systemdrive = os.environ['SYSTEMDRIVE']
        tempdir = os.environ['TEMP']
        a['pathseparator'] = '\\'
        a['readyfile'] = systemdrive + '\system-is-ready'
        a['restart'] = systemroot + '\system32\shutdown.exe/r /t 30 /d p:2:4 /c "SystemPrep complete. Rebooting computer."'
    else:
        raise SystemError('System, ' + system + ', is not recognized?')

    a['workingdir'] = createWorkingDir(tempdir, workingdirprefix)

    return a


def downloadFile(url, filename):
    """
Download the file from `url` and save it locally under `filename`:
    :rtype : bool
    :param url:
    :param filename:
    """
    try:
        response = urllib2.urlopen(url)
    except:
        raise SystemError('Unable to open connection to web server. \nurl =\n    ' + url)
    
    try:
        with open(filename, 'wb') as outfile:
            shutil.copyfileobj(response, outfile)
    except:
        raise SystemError('Unable to save file. \nfilename = \n    ' + filename)

    print('Downloaded file -- \n    url      = ' + url + '\n    filename = ' + filename)
    return True


def cleanup(workingdir):
    """
    Removes temporary files loaded to the system.
    :param workingdir: str, Path to the working directory
    :return: bool
    """
    print('+-' * 40)
    print('Cleanup Time...')
    try:
        shutil.rmtree(workingdir)
    except:
        raise SystemError('Cleanup Failed!')

    print('Removed temporary data in working directory -- ' + workingdir)
    print('Exiting cleanup routine...')
    print('-+' * 40)
    return True


def main( noreboot, **kwargs):
    """
    Master Script that calls content scripts to be deployed when provisioning systems
    """

    scriptname = __file__

    print('+' * 80)
    print('Entering script -- ' + scriptname)
    print('Printing parameters --')
    for key, value in kwargs.items():
        print('    ' + str(key) + ' = ' + str(value))
    
    system = platform.system()
    systemparams = getSystemParams(system)
    scriptstoexecute = getScriptsToExecute(system, systemparams['workingdir'], **kwargs)
    
    #Loop through each 'script' in scriptstoexecute
    for script in scriptstoexecute:
        filename = script['ScriptSource'].split('/')[-1]
        fullfilepath = systemparams['workingdir'] + systemparams['pathseparator'] + filename
        #Download each script, script['ScriptSource']
        downloadFile(script['ScriptSource'], fullfilepath)
        #Execute each script, passing it the parameters in script['Parameters']
        #TODO: figure out a better way to call and execute the script
        print('Running script -- ' + script['ScriptSource'])
        print('Sending parameters --')
        for key, value in script['Parameters'].items():
            print('    ' + str(key) + ' = ' + str(value))
        paramstring = ' '.join("%s='%s'" % (key,val) for (key,val) in script['Parameters'].iteritems())
        fullcommand = 'python ' + fullfilepath + ' ' + paramstring
        os.system(fullcommand) # likely a dirty hack, probably want to code the
                               # python sub-script with an importable module instead
    
    cleanup(systemparams['workingdir'])
    
    #TODO: uncomment this when linux has a value for systemparams['restart']
    if 'True' == noreboot :
        print('Detected noreboot switch. System will not be rebooted.')
    else:
        print('Reboot scheduled. System will reboot after the script exits.')
        os.system(systemparams['restart'])

    print(str(scriptname) + ' complete!')
    print('-' * 80)


if "__main__" == __name__ :
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    noreboot = kwargs.setdefault('NoReboot', 'False')
    main(noreboot, **kwargs)
