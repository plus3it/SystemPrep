#!/usr/bin/env python
import os
import sys
import tempfile
import urllib2
import shutil
import tarfile
import zipfile
import re
import boto

from boto.exception import BotoClientError
from boto.exception import S3ResponseError


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
        except (NameError, BotoClientError, S3ResponseError):
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
        # TODO: Update `except` logic
        raise SystemError('Could not create workingdir in {0}.\n'
                          'Exception: {1}'.format(basedir, exc))

    return workingdir


def extract_contents(filepath,
                     to_directory='.',
                     createdirfromfilename=None,
                     pathseparator='/'):
    """
    Extracts a compressed file to the specified directory.
    Supports files that end in .zip, .tar.gz, .tgz, tar.bz2, or tbz.
    :param filepath: str, path to the compressed file
    :param to_directory: str, path to the target directory
    :raise ValueError: error raised if file extension is not supported
    """
    if filepath.endswith('.zip'):
        opener, mode = zipfile.ZipFile, 'r'
    elif filepath.endswith('.tar.gz') or filepath.endswith('.tgz'):
        opener, mode = tarfile.open, 'r:gz'
    elif filepath.endswith('.tar.bz2') or filepath.endswith('.tbz'):
        opener, mode = tarfile.open, 'r:bz2'
    else:
        raise ValueError('Could not extract `"{0}`" as no appropriate '
                         'extractor is found'.format(filepath))

    if createdirfromfilename:
        to_directory = pathseparator.join((to_directory,
                                           '.'.join(filepath.split(pathseparator)[-1].split('.')[:-1])))
    try:
        os.makedirs(to_directory)
    except OSError:
        if not os.path.isdir(to_directory):
            raise

    cwd = os.getcwd()
    os.chdir(to_directory)

    try:
        openfile = opener(filepath, mode)
        try:
            openfile.extractall()
        finally:
            openfile.close()
    finally:
        os.chdir(cwd)

    print('Extracted file -- \n'
          '    source = {0}\n'
          '    dest   = {1}'.format(filepath, to_directory))
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
        # TODO: Update `except` logic
        raise SystemError('Cleanup Failed!\n'
                          'Exception: {0}'.format(exc))

    print('Removed temporary data in working directory -- ' + workingdir)
    print('Exiting cleanup routine...')
    print('-+' * 40)
    return True


def main(saltinstallmethod='git',
         saltbootstrapsource="https://raw.githubusercontent.com/saltstack/salt-bootstrap/develop/bootstrap-salt.sh",
         saltgitrepo="git://github.com/saltstack/salt.git",
         saltversion=None,
         saltcontentsource=None,
         formulastoinclude=None,
         formulaterminationstrings=None,
         saltstates='none',
         salt_results_log=None,
         salt_debug_log=None,
         sourceiss3bucket='false',
         **kwargs):
    """
    Manages the salt installation and configuration.
    :param saltinstallmethod: str, method of installing salt
                          'git': install salt from git source. requires 
                                 `saltbootstrapsource` and `saltgitrepo`. 
                                 optionally specify `saltversion`.
                          'yum': install salt from a yum repo. the salt 
                                 packages must be available in a yum repo 
                                 already configured on the system.
    :param saltbootstrapsource: str, location of the salt bootstrap installer
    :param saltgitrepo: str, git repo containing the salt source files
    :param saltversion: str, optional. version of salt to install. if 
                        `installmethod` is 'git', then this value must be a 
                        tag or branch in the git repo.
    :param saltcontentsource: str, location of additional salt content, must 
                              be a compressed file
    :param formulastoinclude: list, locations of salt formulas to configure, 
                              must be compressed files
    :param formulaterminationstrings: list, strings that will be removed from 
                                      the end of a salt formula name
    :param saltstates: str, comma-separated string of saltstates to apply.
                       'none' is a keyword that will not apply any states.
                       'highstate' is a keyword that will apply states based 
                       on the top.sls definition.
    :param salt_results_log: str, path to the file to save the output of the
                             salt-call state run
    :param salt_debug_log: str, path to the file to save the debug log of the
                           salt-call state run
    :param sourceiss3bucket: str, set to 'true' if saltcontentsource and 
                             formulastoinclude are hosted in an S3 bucket.
    :param kwargs: dict, catch-all for other params that do not apply to this 
                   content script
    :raise SystemError: error raised whenever an issue is encountered
    """
    scriptname = __file__

    # Convert from None to list, to support iteration
    formulastoinclude = [] if formulastoinclude is None else formulastoinclude
    formulaterminationstrings = [] if formulaterminationstrings is None else \
        formulaterminationstrings
    # Convert from string to bool
    sourceiss3bucket = 'true' == sourceiss3bucket.lower()

    print('+' * 80)
    print('Entering script -- ' + scriptname)
    print('Printing parameters...')
    print('    saltinstallmethod = {0}'.format(saltinstallmethod))
    print('    saltbootstrapsource = {0}'.format(saltbootstrapsource))
    print('    saltgitrepo = {0}'.format(saltgitrepo))
    print('    saltversion = {0}'.format(saltversion))
    print('    saltcontentsource = {0}'.format(saltcontentsource))
    print('    formulastoinclude = {0}'.format(formulastoinclude))
    print('    formulaterminationstrings = {0}'.format(formulaterminationstrings))
    print('    saltstates = {0}'.format(saltstates))
    for key, value in kwargs.items():
        print('    {0} = {1}'.format(key, value))

    minionconf = '/etc/salt/minion'
    saltcall = '/usr/bin/salt-call'
    saltsrv = '/srv/salt'
    saltfileroot = os.sep.join((saltsrv, 'states'))
    saltformularoot = os.sep.join((saltsrv, 'formulas'))
    saltbaseenv = os.sep.join((saltfileroot, 'base'))
    workingdir = create_working_dir('/usr/tmp/', 'saltinstall-')
    salt_results_logfile = salt_results_log or os.sep.join((workingdir, 
                                'saltcall.results.log'))
    salt_debug_logfile = salt_debug_log or os.sep.join.join((workingdir, 
                                'saltcall.debug.log'))
    saltcall_arguments = '--out json --out-file {0} --return local --log-file ' \
                         '{1} --log-file-level debug' \
                         .format(salt_results_logfile, salt_debug_logfile)

    #Install salt via yum or git
    if 'yum' == saltinstallmethod.lower():
        # Install dependencies for selinux python modules
        os.system('yum -y install policycoreutils-python')
        # Install salt-minion
        # TODO: Install salt version specified by `saltversion`
        os.system('yum -y install salt-minion')
    elif 'git' == saltinstallmethod.lower():
        #Download the salt bootstrap installer and install salt
        saltbootstrapfilename = saltbootstrapsource.split('/')[-1]
        saltbootstrapfile = '/'.join((workingdir, saltbootstrapfilename))
        download_file(saltbootstrapsource, saltbootstrapfile)
        if saltversion:
            os.system('sh {0} -g {1} git {2}'.format(saltbootstrapfile,
                                                     saltgitrepo, saltversion))
        else:
            os.system('sh {0} -g {1}'.format(saltbootstrapfile, saltgitrepo))
    else:
        raise SystemError('Unrecognized `saltinstallmethod`! Must set '
                          '`saltinstallmethod` to either "git" or "yum".')

    #Create directories for salt content and formulas
    for saltdir in [saltfileroot, saltbaseenv, saltformularoot]:
        try:
            os.makedirs(saltdir)
        except OSError:
            if not os.path.isdir(saltdir):
                raise

    #Download and extract the salt content specified by saltcontentsource
    if saltcontentsource:
        saltcontentfilename = saltcontentsource.split('/')[-1]
        saltcontentfile = os.sep.join((workingdir, saltcontentfilename))
        download_file(saltcontentsource, saltcontentfile, sourceiss3bucket)
        extract_contents(filepath=saltcontentfile,
                         to_directory=saltsrv)

    #Download and extract any salt formulas specified in formulastoinclude
    saltformulaconf = []
    for formulasource in formulastoinclude:
        formulafilename = formulasource.split('/')[-1]
        formulafile = os.sep.join((workingdir, formulafilename))
        download_file(formulasource, formulafile)
        extract_contents(filepath=formulafile,
                         to_directory=saltformularoot)
        formulafilebase = os.sep.join(formulafilename.split('.')[:-1])
        formuladir = os.sep.join((saltformularoot, formulafilebase))
        for string in formulaterminationstrings:
            if formulafilebase.endswith(string):
                newformuladir = formuladir[:-len(string)]
                shutil.move(formuladir, newformuladir)
                formuladir = newformuladir
        saltformulaconf += '    - {0}\n'.format(formuladir),

    #Create a list that contains the new file_roots configuration
    saltfilerootconf = []
    saltfilerootconf += 'file_roots:\n',
    saltfilerootconf += '  base:\n',
    saltfilerootconf += '    - {0}\n'.format(saltbaseenv),
    saltfilerootconf += saltformulaconf
    saltfilerootconf += '\n',

    #Backup the minionconf file
    shutil.copyfile(minionconf, '{0}.bak'.format(minionconf))

    #Read the minionconf file into a list
    with open(minionconf, 'r') as f:
        minionconflines = f.readlines()

    #Find the file_roots section in the minion conf file
    filerootsbegin = '^#file_roots:|^file_roots:'
    filerootsend = '^$'
    beginindex = None
    endindex = None
    n = 0
    for line in minionconflines:
        if re.match(filerootsbegin, line):
            beginindex = n
        if beginindex and not endindex and re.match(filerootsend, line):
            endindex = n
        n += 1

    #Update the file_roots section with the new configuration
    minionconflines = minionconflines[0:beginindex] + \
                      saltfilerootconf + minionconflines[endindex + 1:]

    #Write the new configuration to minionconf
    try:
        with open(minionconf, 'w') as f:
            f.writelines(minionconflines)
    except Exception as exc:
        raise SystemError('Could not write to minion conf file: {0}\n'
                          'Exception: {1}'.format(minionconf, exc))
    else:
        print('Saved the new minion configuration successfully.')

    #Check whether we need to run salt-call
    if 'none' == saltstates.lower():
        print('No States were specified. Will not apply any salt states.')
    else:
        # Apply the requested salt state(s)
        result = None
        if 'highstate' == saltstates.lower():
            print('Detected the States parameter is set to `highstate`. '
                  'Applying the salt `"highstate`" to the system.')
            result = os.system('{0} --local state.highstate {1}'
                        .format(saltcall, saltcall_arguments))
        else:
            print('Detected the States parameter is set to: {0}. '
                  'Applying the user-defined list of states to the system.'
                  .format(saltstates))
            result = os.system('{0} --local state.sls {1} {2}'
                        .format(saltcall, saltstates, saltcall_arguments))

        print('Return code of salt-call: {0}'.format(result))

        # Check for errors in the salt state execution
        try:
            with open(salt_results_logfile, 'rb') as f:
                salt_results = f.read()
        except Exception as exc:
            raise SystemError('Could open the salt results log file: {0}\n'
                              'Exception: {1}'
                              .format(salt_results_logfile, exc))
        if (not re.search('"result": false', salt_results)) and \
           (re.search('"result": true', salt_results)):
            #At least one state succeeded, and no states failed, so log success
            print('Salt states applied successfully! Details are in the log, '
                  '{0}'.format(salt_results_logfile))
        else:
            raise SystemError('ERROR: There was a problem running the salt '
                              'states! Check for errors and failed states in '
                              'the log file, {0}'
                              .format(salt_results_logfile))

    #Remove working files
    cleanup(workingdir)

    print(str(scriptname) + ' complete!')
    print('-' * 80)


if __name__ == "__main__":
    # convert command line parameters of the form `param=value` to a dict
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    #Convert parameter keys to lowercase, parameter values are unmodified
    kwargs = dict((k.lower(), v) for k, v in kwargs.items())

    #Need to convert comma-delimited strings strings to lists,
    #where the strings may have parentheses or brackets
    #First, remove any parentheses or brackets
    kwargs['formulastoinclude'] = kwargs['formulastoinclude'].translate(None, '()[]')
    kwargs['formulaterminationstrings'] = kwargs['formulaterminationstrings'].translate(None, '()[]')
    #Then, split the string on the comma to convert to a list,
    #and remove empty strings with filter
    kwargs['formulastoinclude'] = filter(None, kwargs['formulastoinclude'].split(','))
    kwargs['formulaterminationstrings'] = filter(None, kwargs['formulaterminationstrings'].split(','))

    main(**kwargs)
