#!/usr/bin/env python
import boto
import re
import shutil
import sys
import urllib2

from boto.exception import BotoClientError


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


_supported_dists = ('amazon', 'centos', 'red hat')
_match_supported_dist = re.compile(r'^({0})'
                                    '(?:[^0-9]+)'
                                    '([\d]+[.][\d]+)'
                                    '(?:.*)'
                                    .format('|'.join(_supported_dists)))
_amazon_epel_versions = {
    '2014.03' : '6',
    '2014.09' : '6',
    '2015.03' : '6',
}


def main(yumrepomap=None):
    """
    Checks the distribution version and installs yum repo definition files
    that are specific to that distribution.
    :param yumrepomap: list of dicts, each dict contains two or three keys.
                       'url': the url to the yum repo definition file
                       'dist': the linux distribution to which the repo should
                               be installed. one of 'amazon', 'redhat',
                               'centos', or 'all'. 'all' is a special keyword
                               that maps to all distributions.
                       'epel_version': optional. match the major version of the
                                       epel-release that applies to the
                                       system. one of '6' or '7'. if not
                                       specified, the repo is installed to all
                                       systems.
        Example: [ { 
                     'url' : 'url/to/the/yum/repo/definition.repo',
                     'dist' : 'amazon' or 'redhat' or 'centos' or 'all',
                     'version' : '6' or '7',
                   },
                 ]
    """
    if not yumrepomap:
        print('`yumrepomap` is empty. Nothing to do!')
        return None

    if not isinstance(yumrepomap, list):
        raise SystemError('`yumrepomap` must be a list!')

    # Read first line from /etc/system-release
    release = None
    try:
        with open(name='/etc/system-release', mode='rb') as f:
            release = f.readline().strip()
    except Exception as exc:
        raise SystemError('Could not read /etc/system-release. '
                          'Error: {0}'.format(exc))

    # Search the release file for a match against _supported_dists
    m = _match_supported_dist.search(release.lower())
    if m is None:
        # Release not supported, exit with error
        raise SystemError('Unsupported OS distribution. OS must be one of: '
                          '{0}.'.format(', '.join(_supported_dists)))

    # Assign dist,version from the match groups tuple, removing any spaces
    dist,version = (x.translate(None, ' ') for x in m.groups())

    # Determine epel_version
    epel_version = None
    if 'amazon' == dist:
        epel_version = _amazon_epel_versions.get(version, None)
    else:
        epel_version = version.split('.')[0]

    for repo in yumrepomap:
        # Test whether this repo should be installed to this system
        if repo['dist'] in [dist, 'all'] and repo.get('epel_version', 'all') \
                                                in [epel_version, 'all']:
            # Download the yum repo definition to /etc/yum.repos.d/
            url = repo['url']
            repofile = '/etc/yum.repos.d/{0}'.format(url.split('/')[-1])
            download_file(url, repofile)


if __name__ == "__main__":
    # Convert command line parameters of the form `param=value` to a dict
    kwargs = dict(x.split('=', 1) for x in sys.argv[1:])
    # Convert parameter keys to lowercase, parameter values are unmodified
    kwargs = dict((k.lower(), v) for k, v in kwargs.items())

    # Need to convert a string to a list of dicts,
    # First, remove any parentheses or brackets
    kwargs['yumrepomap'] = kwargs.get('yumrepomap', '').translate(None, '()[]')
    # Then, split the string to form groups around {}
    kwargs['yumrepomap'] = re.split('({.*?})', kwargs['yumrepomap'])
    # Now remove empty/bad strings
    kwargs['yumrepomap'] = [v for v in filter(None, kwargs['yumrepomap']) \
        if not v == ', ']
    # Remove braces and split on commas. it's now a list of lists
    kwargs['yumrepomap'] = [v.translate(None, '{}').split(',') for v in \
        kwargs['yumrepomap']]
    # Convert to a list of dicts
    kwargs['yumrepomap'] = [dict(x.split(':', 1) for x in y) for y in \
        kwargs['yumrepomap']]
    # Strip whitespace around the keys and values
    kwargs['yumrepomap'] = [dict((k.strip(), v.strip()) for k, v in \
        x.items()) for x in kwargs['yumrepomap']]

    main(**kwargs)
