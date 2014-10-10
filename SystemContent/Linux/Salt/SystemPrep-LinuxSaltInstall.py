#!/usr/bin/env python
import os
import sys
import tempfile
import urllib2
import shutil
import tarfile
import zipfile
import re

def download_file(url, filename):
    """
Download the file from `url` and save it locally under `filename`:
    :rtype : bool
    :param url:
    :param filename:
    """
    try:
        response = urllib2.urlopen(url)
    except:
        #TODO: Update `except` logic
        raise SystemError('Unable to open connection to web server. \nurl =\n    ' + url)

    try:
        with open(filename, 'wb') as outfile:
            shutil.copyfileobj(response, outfile)
    except:
        #TODO: Update `except` logic
        raise SystemError('Unable to save file. \nfilename = \n    ' + filename)

    print('Downloaded file -- \n    url      = ' + url + '\n    filename = ' + filename)
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
    except:
        #TODO: Update `except` logic
        raise SystemError('Could not create workingdir in ' + str('basedir'))

    return workingdir


def extract_contents(filepath, to_directory='.'):
    if filepath.endswith('.zip'):
        opener, mode = zipfile.ZipFile, 'r'
    elif filepath.endswith('.tar.gz') or filepath.endswith('.tgz'):
        opener, mode = tarfile.open, 'r:gz'
    elif filepath.endswith('.tar.bz2') or filepath.endswith('.tbz'):
        opener, mode = tarfile.open, 'r:bz2'
    else:
        raise ValueError('Could not extract ' + filepath + ' as no appropriate extractor is found')

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
        #TODO: Update `except` logic
        raise SystemError('Cleanup Failed!')

    print('Removed temporary data in working directory -- ' + workingdir)
    print('Exiting cleanup routine...')
    print('-+' * 40)
    return True


def main(saltbootstrapsource,
         saltgitrepo,
         saltversion,
         saltcontentsource=None,
         formulastoinclude=(),
         formulaterminationstrings=(),
         saltstates='none',
         **kwargs):

    scriptname = __file__

    print('+' * 80)
    print('Entering script -- ' + scriptname)
    print('Printing parameters...')
    print('    saltbootstrapsource = ' + str(saltbootstrapsource))
    print('    saltgitrepo = ' + str(saltgitrepo))
    print('    saltversion = ' + str(saltversion))
    print('    saltcontentsource = ' + str(saltcontentsource))
    print('    formulastoinclude = ' + str(formulastoinclude))
    print('    formulaterminationstrings = ' + str(formulaterminationstrings))
    print('    saltstates = ' + str(saltstates))
    for key, value in kwargs.items():
        print('    ' + str(key) + ' = ' + str(value))

    minionconf = '/etc/salt/minion'
    saltcall = '/usr/bin/salt-call'
    saltfilebase = '/srv'
    saltfileroot = saltfilebase + '/salt'
    saltformularoot = saltfilebase + '/saltformulas'
    workingdir = create_working_dir('/usr/tmp/', 'saltinstall-')

    #Download the salt bootstrap installer and install salt
    saltbootstrapfile = workingdir + '/' + saltbootstrapsource.split('/')[-1]
    download_file(saltbootstrapsource, saltbootstrapfile)
    os.system('sh ' + saltbootstrapfile + ' -g ' + saltgitrepo + ' git ' + saltversion)

    #Create directories for salt content and formulas
    try:
        os.makedirs(saltfileroot)
    except OSError:
        if not os.path.isdir(saltfileroot):
            raise
    try:
        os.makedirs(saltformularoot)
    except OSError:
        if not os.path.isdir(saltformularoot):
            raise

    #Download and extract the salt content specified by saltcontentsource
    if saltcontentsource:
        saltcontentfile = workingdir + '/' + saltcontentsource.split('/')[-1]
        download_file(saltcontentsource, saltcontentfile)
        extract_contents(filepath=saltcontentfile, to_directory=saltfilebase)

    #Download and extract any salt formulas specified in formulastoinclude
    saltformulaconf = []
    for formulasource in formulastoinclude:
        formulafilename = formulasource.split('/')[-1]
        for string in formulaterminationstrings:
            if formulafilename.endswith(string):
                formulafilename = formulafilename[:-len(string)]
        formulafile = workingdir + '/' + formulafilename
        download_file(formulasource, formulafile)
        extract_contents(filepath=formulafile, to_directory=saltformularoot)
        saltformulaconf += '    - ' + saltformularoot + '/' + formulafilename + '\n',

    #Create a list that contains the new file_roots configuration
    saltfilerootconf = []
    saltfilerootconf += 'file_roots:\n',
    saltfilerootconf += '  base:\n',
    saltfilerootconf += '    - ' + saltfileroot + '\n',
    saltfilerootconf += saltformulaconf
    saltfilerootconf += '\n',

    #Backup the minionconf file
    shutil.copyfile(minionconf, minionconf + '.bak')

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
    minionconflines = minionconflines[0:beginindex] + saltfilerootconf + minionconflines[endindex+1:]

    #Write the new configuration to minionconf
    try:
        with open(minionconf, 'w') as f:
            f.writelines(minionconflines)
    except:
        raise SystemError('Could not write to minion conf file' + minionconf)
    else:
        print('Saved the new minion configuration successfully.')

    #Apply the specified salt state
    if 'none' == saltstates.lower():
        print('No States were specified. Will not apply any salt states.')
    elif 'highstate' == saltstates.lower():
        print('Detected the States parameter is set to `highstate`. Applying the salt `"highstate`" to the system.')
        os.system(saltcall + ' --local state.highstate')
    else:
        print('Detected the States parameter is set to: ' + saltstates + '. Applying the user-defined list of states to the system.')
        os.system(saltcall + ' --local state.sls ' + saltstates)

    #Remove working files
    cleanup(workingdir)

    print(str(scriptname) + ' complete!')
    print('-' * 80)


if __name__ == "__main__":
    #convert command line parameters of the form `param=value` to a dict
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    #Convert parameter keys to lowercase, parameter values are unmodified
    kwargs = dict((k.lower(), v) for k, v in kwargs.items())

    #Need to convert comma-delimited strings strings to lists, where the strings may have parentheses or brackets
    #First, remove the parentheses and brackets
    kwargs['formulastoinclude'] = kwargs['formulastoinclude'].translate(None, '()[]')
    kwargs['formulaterminationstrings'] = kwargs['formulaterminationstrings'].translate(None, '()[]')
    #Then, split the string on the comma to convert to a list, and remove empty strings with filter
    kwargs['formulastoinclude'] = filter(None,kwargs['formulastoinclude'].split(','))
    kwargs['formulaterminationstrings'] = filter(None,kwargs['formulaterminationstrings'].split(','))

    main(**kwargs)
