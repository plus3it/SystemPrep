# SystemPrep
**SystemPrep** helps provision a system from its initial installation to its 
final configuration. It was inspired by a desire to eliminate static system
images with embedded configuration settings (e.g. gold disks) and the pain 
associated with maintaining them.

**SystemPrep** consists of a framework of highly-customizable scripts. For 
Linux systems, the scripts are written primarily in python (the one exception 
is that *bootstrap* scripts are written in bash); for Windows systems, the 
scripts are written in PowerShell. As it leverages OS-native capabilities to 
bootstrap a system, **SystemPrep** has very few inherent dependencies. More 
complex configuration management (CM) environments may be layered in as part 
of the **SystemPrep** framework. We use Salt to demonstrate how to layer in a 
CM tool and build a functioning system hardening capability, but feel free to 
use any CM tool of your choice.

## SystemPrep Components
**SystemPrep** scripts abstract the provisioning and configuration process into 
three components:

- *Bootstrap* scripts
- *Master* scripts
- *Content* scripts

*Bootstrap* scripts are very lightweight and static. Their primary task is to 
download and execute the master script. They may also establish a log file. 
Bootstrap scripts are tailored slightly to account for differences in 
provisioning mechanisms (E.g. Amazon EC2 instances, VMware templates, 
Microsoft Azure, Microsoft SCCM, PXE boot, etc). However, once created for the 
environment they should rarely require any modification. This fixed, static 
nature is a key feature of a bootstrap script, and makes them suitable for
embedding into an image, if required by the environment. The *Bootstrap* 
scripts can be found [here](BootStrapScripts).

**Template Bootstrap Scripts**
- [Linux Bootstrap script](BootStrapScripts/SystemPrep-Bootstrap-Template-Linux.sh)
- [Windows Bootstrap script](BootStrapScripts/SystemPrep-Bootstrap-Template-Windows.ps1)

*Master* scripts orchestrate the execution of content scripts. A master script 
contains a list of all the content scripts to execute and any required 
parameters, and it executes the content scripts accordingly. Separating the 
bootstrap script and the master script in this manner makes it simple to 
adjust the provisioning framework as requirements change, without 
changing the OS image in any way. Further, it also streamlines the process for 
providing new OS versions or updating OS images with patches, as there is no 
impact to any embedded components of the provisioning and configuration 
framework.

*Content* scripts are the workhorses. Content scripts download content, 
install software, and perform configuration actions. While content scripts can 
be utilized to perform configuration actions directly, we would recommend 
utilizing a content script to initialize a configuration management solution 
and apply a specific configuration state.




