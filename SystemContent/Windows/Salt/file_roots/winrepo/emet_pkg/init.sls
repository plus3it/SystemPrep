Emet:
  5.1:
    installer: 'salt://emet_pkg/emetfiles/5.1/EMET 5.1 Setup.msi'
    full_name: 'EMET 5.1'
    reboot: False
    install_flags: ' ALLUSERS=1 /quiet /qn /norestart'
    msiexec: True
    uninstaller: 'salt://emet_pkg/emetfiles/5.1/EMET 5.1 Setup.msi'
    uninstall_flags: ' /qn'
