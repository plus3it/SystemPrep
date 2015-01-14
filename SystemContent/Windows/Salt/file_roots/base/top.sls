base:
  'osrelease:2012Server':
    - match: grain
    - netbanner.custom
    - pshelp
    - emet

  'osrelease:2008ServerR2':
    - match: grain
    - pshelp

  '*'
    - ash-windows.stig
    - ash-windows.delta
