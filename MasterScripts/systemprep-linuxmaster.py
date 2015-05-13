#!/usr/bin/env python
import os
import sys
import platform
import tempfile
import urllib2
import shutil
import boto

from boto.exception import BotoClientError

def merge_dicts(a, b):
    """
Merge two dictionaries. If there is a key collision, `b` overrides `a`.
    :param a: Dictionary of default settings
    :param b: Dictionary of override settings
    :rtype : dict
    """
    
    try:
        a.update(b)
    except Exception as exc:
        #TODO: Update `except` logic
        raise SystemError('Failed to merge dictionaries. Dictionary A:\n\n'
                          '{0}\n\n'
                          'Dictionary B:\n\n'
                          '{1}\n\n'
                          'Exception: {2}'
                          .format(a, b, exc))
    
    return a


def get_scripts_to_execute(system, workingdir, **scriptparams):
    """
Returns an array of hashtables. Each hashtable has two keys: 'ScriptUrl' and 'Parameters'.
'ScriptSource' is the path to the script to be executed. Only supports http/s sources currently.
'Parameters' is a hashtable of parameters to pass to the script.
Use `merge_dicts({yourdict}, scriptparams)` to merge command line parameters with a set of default parameters.
    :param system: str, the system type as returned from `platform.system`
    :param workingdir: str, the working directory where content should be saved
    :param scriptparams: dict, parameters passed to the master script which should be relayed to the content scripts
    :rtype : dict
    """

    if 'Linux' in system:
        scriptstoexecute = (
            {
                'ScriptSource': "https://systemprep.s3.amazonaws.com/ContentScripts/systemprep-linuxyumrepoinstall.py",
                'Parameters': merge_dicts({
                    'yumrepomap': [
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-amzn-packages.repo',
                            'dist': 'amazon',
                        },
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-centos-packages.repo',
                            'dist': 'centos',
                        },
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-rhel-packages.repo',
                            'dist': 'redhat',
                        },
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-epel6-packages.repo',
                            'dist': 'all',
                            'epel_version': '6',
                        },
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-epel7-packages.repo',
                            'dist': 'all',
                            'epel_version': '7',
                        },
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-salt-epel6-packages.repo',
                            'dist': 'all',
                            'epel_version': '6',
                        },
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-salt-epel7-packages.repo',
                            'dist': 'all',
                            'epel_version': '7',
                        },
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-zmq-epel6-packages.repo',
                            'dist': 'all',
                            'epel_version': '6',
                        },
                        {
                            'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-zmq-epel7-packages.repo',
                            'dist': 'all',
                            'epel_version': '7',
                        },
                    ],
                }, scriptparams)
            },
            { 
                'ScriptSource': "https://systemprep.s3.amazonaws.com/ContentScripts/SystemPrep-LinuxSaltInstall.py",
                'Parameters': merge_dicts({
                    'saltinstallmethod': 'yum',
                    'saltbootstrapsource': "https://raw.githubusercontent.com/saltstack/salt-bootstrap/stable/bootstrap-salt.sh",
                    'saltgitrepo': "git://github.com/saltstack/salt.git",
                    'saltversion': "v2014.7.5",
                    'saltcontentsource': "https://systemprep-content.s3.amazonaws.com/linux/salt/salt-content.zip",
                    'formulastoinclude': [
                        "https://salt-formulas.s3.amazonaws.com/ash-linux-formula-master.zip",
                    ],
                    'formulaterminationstrings': [
                        "-master",
                        "-latest",
                    ],
                    'saltstates': 'Highstate',
                    'sourceiss3bucket': 'True',
                }, scriptparams)
            },
        )
    elif 'Windows' in system:
        scriptstoexecute = (
            {
                'ScriptSource': "https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1",
                'Parameters': merge_dicts({
                    'saltworkingdir': '{0}\\SystemContent\\Windows\\Salt'.format(workingdir),
                    'saltcontentsource': "https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/salt-content.zip",
                    'formulastoinclude': [
                        "https://salt-formulas.s3.amazonaws.com/ash-windows-formula-latest.zip",
                    ],
                    'formulaterminationstrings': [
                        "-latest",
                    ],
                    'ashrole': "MemberServer",
                    'netbannerstring': "Unclass",
                    'saltstates': "Highstate",
                }, scriptparams)
            },
        )
    else:
        #TODO: Update `except` logic
        raise SystemError('System, {0}, is not recognized?'.format(system))
    
    return scriptstoexecute


def create_working_dir(basedir, dirprefix):
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
    except Exception as exc:
        #TODO: Update `except` logic
        raise SystemError('Could not create workingdir in {0}.\n'
                          'Exception: {1}'.format(basedir, exc))

    return workingdir


def get_system_params(system):
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
    elif 'Windows' in system:
        #TODO: Add and test the Windows parameters/functionality
        systemroot = os.environ['SYSTEMROOT']
        systemdrive = os.environ['SYSTEMDRIVE']
        tempdir = os.environ['TEMP']
        a['pathseparator'] = '\\'
        a['readyfile'] = '\system-is-ready'.format(systemdrive)
        a['restart'] = '{0}\system32\shutdown.exe/r /t 30 /d p:2:4 /c "SystemPrep complete. Rebooting computer."'.format(systemroot)
    else:
        #TODO: Update `except` logic
        raise SystemError('System, {0}, is not recognized?'.format(system))

    a['workingdir'] = create_working_dir(tempdir, workingdirprefix)

    return a


def download_file(url, filename, sourceiss3bucket=None):
    """
Download the file from `url` and save it locally under `filename`.
    :rtype : bool
    :param url:
    :param filename:
    :param sourceiss3bucket:
    """
    conn = None

    if sourceiss3bucket:
        bucket_name = url.split('/')[3]
        key_name = '/'.join(url.split('/')[4:])
        try:
            conn = boto.connect_s3()
            bucket = conn.get_bucket(bucket_name)
            key = bucket.get_key(key_name)
            key.get_contents_to_filename(filename=filename)
        except (NameError, BotoClientError):
            try:
                bucket_name = url.split('/')[2].split('.')[0]
                key_name = '/'.join(url.split('/')[3:])
                bucket = conn.get_bucket(bucket_name)
                key = bucket.get_key(key_name)
                key.get_contents_to_filename(filename=filename)
            except Exception as exc:
                raise SystemError('Unable to download file from S3 bucket.\n'
                                  'url = {0}\n'
                                  'bucket = {1}\n'
                                  'key = {2}\n'
                                  'file = {3}\n'
                                  'Exception: {4}'
                                  .format(url, bucket_name, key_name,
                                          filename, exc))
        except Exception as exc:
            raise SystemError('Unable to download file from S3 bucket.\n'
                              'url = {0}\n'
                              'bucket = {1}\n'
                              'key = {2}\n'
                              'file = {3}\n'
                              'Exception: {4}'
                              .format(url, bucket_name, key_name,
                                      filename, exc))
        print('Downloaded file from S3 bucket -- \n'
              '    url      = {0}\n'
              '    filename = {1}'.format(url, filename))
    else:
        try:
            response = urllib2.urlopen(url)
            with open(filename, 'wb') as outfile:
                shutil.copyfileobj(response, outfile)
        except Exception as exc:
            #TODO: Update `except` logic
            raise SystemError('Unable to download file from web server.\n'
                              'url = {0}\n'
                              'filename = {1}\n'
                              'Exception: {2}'
                              .format(url, filename, exc))
        print('Downloaded file from web server -- \n'
              '    url      = {0}\n'
              '    filename = {1}'.format(url, filename))
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
    except Exception as exc:
        #TODO: Update `except` logic
        raise SystemError('Cleanup Failed!\n'
                          'Exception: {0}'.format(exc))

    print('Removed temporary data in working directory -- ' + workingdir)
    print('Exiting cleanup routine...')
    print('-+' * 40)
    return True


def main(noreboot='false', **kwargs):
    """
    Master Script that calls content scripts to be deployed when provisioning systems
    """

    scriptname = __file__

    #Check special parameter types
    noreboot = 'true' == noreboot.lower()
    sourceiss3bucket = 'true' == kwargs.get('sourceiss3bucket', 'false').lower()

    print('+' * 80)
    print('Entering script -- {0}'.format(scriptname))
    print('Printing parameters --')
    print('    noreboot = {0}'.format(noreboot))
    for key, value in kwargs.items():
        print('    {0} = {1}'.format(key, value))

    system = platform.system()
    systemparams = get_system_params(system)
    scriptstoexecute = get_scripts_to_execute(system, systemparams['workingdir'], **kwargs)

    #Loop through each 'script' in scriptstoexecute
    for script in scriptstoexecute:
        url = script['ScriptSource']
        filename = url.split('/')[-1]
        fullfilepath = systemparams['workingdir'] + systemparams['pathseparator'] + filename
        #Download each script, script['ScriptSource']
        download_file(url, fullfilepath, sourceiss3bucket)
        #Execute each script, passing it the parameters in script['Parameters']
        #TODO: figure out if there's a better way to call and execute the script
        print('Running script -- ' + script['ScriptSource'])
        print('Sending parameters --')
        for key, value in script['Parameters'].items():
            print('    {0} = {1}'.format(key, value))
        paramstring = ' '.join("%s='%s'" % (key, val) for (key, val) in script['Parameters'].iteritems())
        fullcommand = 'python {0} {1}'.format(fullfilepath, paramstring)
        try:
            os.system(fullcommand)
        except Exception as exc:
            raise SystemError('Encountered an unrecoverable error executing a '
                              'content script. Exiting with failure.\n'
                              'Command executed: {0}\n'
                              'Exception: {1}'.format(fullcommand, exc))

    cleanup(systemparams['workingdir'])

    if noreboot:
        print('Detected `noreboot` switch. System will not be rebooted.')
    else:
        print('Reboot scheduled. System will reboot after the script exits.')
        os.system(systemparams['restart'])

    print('{0} complete!'.format(scriptname))
    print('-' * 80)


if "__main__" == __name__:
    #convert command line parameters of the form `param=value` to a dict
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    #Convert parameter keys to lowercase, parameter values are unmodified
    kwargs = dict((k.lower(), v) for k, v in kwargs.items())

    main(**kwargs)
