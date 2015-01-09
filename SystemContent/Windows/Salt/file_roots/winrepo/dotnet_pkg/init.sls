.NET:
  4.5.2:
    installer: 'salt://dotnet_pkg/dotnetfiles/NDP452-KB2901907-x86-x64-AllOS-ENU.exe'
    full_name: 'Microsoft .NET Framework 4.5.2'
    reboot: False
    install_flags: '/q /norestart'
    msiexec: False
    uninstaller: 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\SetupCache\v4.5.51209\Setup.exe'
    uninstall_flags: '/uninstall /x86 /x64 /q /norestart'
