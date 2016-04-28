#!/usr/bin/env python

import argparse
import boto, urllib2
import os, platform, shutil, subprocess

class SystemPrep:
    params = None
    system_params = None

    def __init__(self):
        """
        Class constructor - parses parameters that follows the script when it is run.
        """
        parser = argparse.ArgumentParser()
        parser.add_argument('--noreboot', type = bool, default = False, choices = [True, False])
        parser.add_argument('--sourceiss3bucket', type = bool, default = False, choices = [True, False])
        try:
            params = parser.parse_known_args()
            self.params = vars(params[0])
            self.params['prog'] = os.path.abspath(parser.prog)

            # Loop through extra parameters and put into dictionary.
            for param in params[1]:
                if '=' in param:
                    [key, value] = param.split('=', 1)
                    if key.lower() in ['noreboot', 'sourceiss3bucket']:
                        self.params[key.lower()] =  True if value.lower() == 'true' else False
                    else:
                        self.params[key.lower()] = value
                else:
                    message = 'Encountered an invalid parameter: {0}'.format(param)
                    raise ValueError(message)

            # Obtain the platform OS that script is running on.
            self.params['system'] = platform.system()
        except:
            print parser.print_help()
            raise ValueError('Script could not process parameters.')

    def execute_scripts(self):
        """
        Master Script that calls content scripts to be deployed when provisioning systems.
        """
        print('+' * 80)
        print('Entering script -- {0}'.format(self.params['prog']))
        print('Printing parameters --')
        for key, value in self.params.items():
            print('    {0} = {1}'.format(key, value))

        print self.params['system']
        self.get_system_params()
        print self.system_params
        scripts = self.get_scripts_to_execute(self.system_params['workingdir'])

        # Loop through each 'script' in scripts
        for script in scripts:
            url = script['ScriptSource']
            print url
            filename = url.split('/')[-1]
            print filename
            fullfilepath = self.system_params['workingdir'] + self.system_params['pathseparator'] + filename
            print fullfilepath

            # Download each script, script['ScriptSource']
            self.download_file(url, fullfilepath, self.params['sourceiss3bucket'])

            # Execute each script, passing it the parameters in script['Parameters']
            print('Running script -- ' + script['ScriptSource'])
            print('Sending parameters --')
            for key, value in script['Parameters'].items():
                print('    {0} = {1}'.format(key, value))
            paramstring = ' '.join("%s='%s'" % (key, val) for (key, val) in script['Parameters'].iteritems())
            print paramstring
            if 'Linux' in self.params['system']:
                fullcommand = 'python {0} {1}'.format(fullfilepath, paramstring)
            else:
                powershell = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe '
                fullcommand = powershell + ' {0} {1}'.format(fullfilepath, paramstring)
            print fullcommand
            if result is not 0:
                message = 'Encountered an unrecoverable error executing a ' \
                          'content script. Exiting with failure.\n' \
                          'Command executed: {0}' \
                    .format(fullcommand)
                raise SystemError(message)

        self.cleanup()

        if self.params['noreboot']:
            print('Detected `noreboot` switch. System will not be rebooted.')
        else:
            print('Reboot scheduled. System will reboot after the script exits.')

        print('{0} complete!'.format(self.params['prog']))
        print('-' * 80)

    def get_system_params(self):
        """
        Returns a dictionary of OS platform-specific parameters.
            :rtype : dict
        """
        params = {}
        if 'Linux' in self.params['system']:
            systemdrive = '/var'
            params['pathseparator'] = '/'
            params['prepdir'] = '{0}/systemprep'.format(systemdrive)
            params['readyfile'] = '{0}/run/system-is-ready'.format(systemdrive)
            params['logdir'] = '{0}/logs'.format(params['prepdir'])
            params['workingdir'] = '{0}/workingfiles'.format(params['prepdir'])
            params['restart'] = 'shutdown -r +1 &'
        elif 'Windows' in self.params['system']:
            systemdrive = os.environ['SYSTEMDRIVE']
            params['pathseparator'] = '\\'
            params['prepdir'] = '{0}\\SystemPrep'.format(systemdrive)
            params['readyfile'] = '{0}\\system-is-ready'.format(params['prepdir'])
            params['logdir'] = '{0}\\Logs'.format(params['prepdir'])
            params['workingdir'] = '{0}\\WorkingFiles'.format(params['prepdir'])
            params['restart'] = ('{0}\\system32\\shutdown.exe '
                                 '/r /t 30 /d p:2:4 /c '
                                 '"SystemPrep complete. Rebooting computer."').format(os.environ['SYSTEMROOT'])
        else:
            #TODO: Update `except` logic
            raise SystemError('System, {0}, is not recognized?'.format(self.params['system']))

        # Create SystemPrep directories
        try:
            if not os.path.exists(params['logdir']):
                os.makedirs(params['logdir'])
            if not os.path.exists(params['workingdir']):
                os.makedirs(params['workingdir'])
        except Exception as exc:
            # TODO: Update `except` logic
            raise SystemError('Could not create a directory in {0}.\n'
                              'Exception: {1}'.format(params['prepdir'], exc))
        self.system_params = params

    def get_scripts_to_execute(self, workingdir):
        """
        Returns an array of hashtables. Each hashtable has two keys: 'ScriptSource' and 'Parameters'.
        'ScriptSource' is the path to the script to be executed. Only supports http/s sources currently.
        'Parameters' is a hashtable of parameters to pass to the script.
        Use `merge_dicts({yourdict}, scriptparams)` to merge command line parameters with a set of default parameters.
            :param workingdir: str, the working directory where content should be saved
            :rtype : dict
        """
        if 'Linux' in self.params['system']:
            scriptstoexecute = (
                {
                    'ScriptSource': "https://systemprep.s3.amazonaws.com/ContentScripts/systemprep-linuxyumrepoinstall.py",
                    'Parameters': self.merge_dicts({
                        'yumrepomap': [
                            {
                                'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-amzn.repo',
                                'dist': 'amazon',
                            },
                            {
                                'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-centos.repo',
                                'dist': 'centos',
                            },
                            {
                                'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-rhel.repo',
                                'dist': 'redhat',
                            },
                            {
                                'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-salt-el6.repo',
                                'dist': 'all',
                                'epel_version': '6',
                            },
                            {
                                'url': 'https://s3.amazonaws.com/systemprep-repo/linux/yum.repos/systemprep-repo-salt-el7.repo',
                                'dist': 'all',
                                'epel_version': '7',
                            },
                        ],
                    }, self.params)
                },
                {
                    'ScriptSource': "https://systemprep.s3.amazonaws.com/ContentScripts/SystemPrep-LinuxSaltInstall.py",
                    'Parameters': self.merge_dicts({
                        'saltinstallmethod': 'yum',
                        'saltcontentsource': "https://systemprep-content.s3.amazonaws.com/linux/salt/salt-content.zip",
                        'formulastoinclude': [
                            "https://salt-formulas.s3.amazonaws.com/systemprep-formula-master.zip",
                            "https://salt-formulas.s3.amazonaws.com/ash-linux-formula-master.zip",
                            "https://salt-formulas.s3.amazonaws.com/join-domain-formula-master.zip",
                            "https://salt-formulas.s3.amazonaws.com/scc-formula-master.zip",
                        ],
                        'formulaterminationstrings': [
                            "-master",
                            "-latest",
                        ],
                        'saltstates': 'Highstate',
                        'entenv': 'False',
                        'salt_results_log': '/var/log/saltcall.results.log',
                        'salt_debug_log': '/var/log/saltcall.debug.log',
                        'sourceiss3bucket': True,
                    }, self.params)
                },
            )
        elif 'Windows' in self.params['system']:
            scriptstoexecute = (
                {
                    'ScriptSource': "https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1",
                    'Parameters': self.merge_dicts({
                        'saltworkingdir': '{0}\\SystemContent\\Windows\\Salt'.format(workingdir),
                        'saltcontentsource': "https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/salt-content.zip",
                        'formulastoinclude': [
                            "https://salt-formulas.s3.amazonaws.com/systemprep-formula-master.zip",
                            "https://salt-formulas.s3.amazonaws.com/ash-windows-formula-master.zip",
                        ],
                        'formulaterminationstrings': [
                            "-latest",
                        ],
                        'ashrole': "MemberServer",
                        'entenv': 'False',
                        'saltstates': "Highstate",
                    }, self.params)
                },
            )
        else:
            # TODO: Update `except` logic
            raise SystemError('System, {0}, is not recognized?'.format(self.params['system']))

        return scriptstoexecute

    def merge_dicts(self, a, b):
        """
        Merge two dictionaries. If there is a key collision, `b` overrides `a`.
            :param a: Dictionary of default settings
            :param b: Dictionary of override settings
            :rtype : dict
        """

        try:
            a.update(b)
        except Exception as exc:
            # TODO: Update `except` logic
            raise SystemError('Failed to merge dictionaries. Dictionary A:\n\n'
                              '{0}\n\n'
                              'Dictionary B:\n\n'
                              '{1}\n\n'
                              'Exception: {2}'
                              .format(a, b, exc))

        return a

    def download_file(self, url, filename, sourceiss3bucket = False):
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
            except (NameError, boto.exception.BotoClientError):
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
                # TODO: Update `except` logic
                raise SystemError('Unable to download file from web server.\n'
                                  'url = {0}\n'
                                  'filename = {1}\n'
                                  'Exception: {2}'
                                  .format(url, filename, exc))
            print('Downloaded file from web server -- \n'
                  '    url      = {0}\n'
                  '    filename = {1}'.format(url, filename))
        return True

    def cleanup(self):
        """
        Removes temporary files loaded to the system.
            :return: bool
        """
        print('+-' * 40)
        print('Cleanup Time...')
        try:
            shutil.rmtree(self.system_params['workingdir'])
        except Exception as exc:
            # TODO: Update `except` logic
            raise SystemError('Cleanup Failed!\n'
                              'Exception: {0}'.format(exc))

        print('Removed temporary data in working directory -- ' + self.system_params['workingdir'])
        print('Exiting cleanup routine...')
        print('-+' * 40)
        return True

if "__main__" == __name__:
    systemprep = SystemPrep()
    systemprep.execute_scripts()
