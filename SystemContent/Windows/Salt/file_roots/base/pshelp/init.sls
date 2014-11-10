{% from "pshelp/map.jinja" import pshelp with context %}

#Update the Powershell Help files
UpdatePSHelp:
  cmd:
    - run
    - name: 'Update-Help -Source {{ pshelp.source }} -Force'
    - shell: powershell
