Emet:
  5.0:
    installer: 'salt://emet/emetfiles/5.0/EMET Setup.msi'
    full_name: 'EMET 5.0'
    reboot: False
    install_flags: ' ALLUSERS=1 /quiet /qn /norestart'
    msiexec: True
    uninstaller: 'salt://emet/emetfiles/5.0/EMET Setup.msi'
    uninstall_flags: ' /qn'