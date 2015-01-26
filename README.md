# SystemPrep

**SystemPrep** helps provision a system from its initial installation to its 
final configuration. It was inspired by a desire to eliminate static system
images with embedded configuration settings (e.g. gold disks) and the pain 
associated with maintaining them.

**SystemPrep** consists of a framework of highly-customizable scripts. For 
Linux systems, the scripts are written primarily in python (the one exception 
is that [*Bootstrap* scripts](#bootstrap-scripts) are written in bash); for 
Windows systems, the scripts are written in PowerShell. As it leverages 
OS-native capabilities to bootstrap a system, **SystemPrep** has very few 
inherent dependencies. More complex configuration management (CM) environments 
may be layered in as part of the **SystemPrep** framework. We use [Salt][0] to 
demonstrate how to layer in a CM tool and build a functioning system hardening 
capability, but feel free to use any CM tool of your choice.

## Dependencies

- A web server to host the *Master* script(s) and *Content* script(s), as well
as any content (binaries, config files, etc) that must be distributed to the 
system. The web server must be reachable from the system executing the 
*Bootstrap* script.

## SystemPrep Components

**SystemPrep** scripts abstract the provisioning and configuration process into 
three components:

- [*Bootstrap* scripts](#bootstrap-scripts)
- [*Master* scripts](#master-scripts)
- [*Content* scripts](#content-scripts)

### Bootstrap Scripts

*Bootstrap* scripts are very lightweight and static. Their primary task is to 
download and execute the master script. They may also establish a log file. 
They may also pass parameters to the master script (and the master script may, 
in turn, [\*\*kwargs-style][1], pass them to a content script). Bootstrap 
scripts are tailored slightly to account for differences in provisioning 
mechanisms (E.g. Amazon EC2 instances, VMware templates, Microsoft Azure, 
Microsoft SCCM, PXE boot, etc). However, once created for the environment they 
should rarely require any modification. This fixed, static nature is a key 
feature of a bootstrap script, and makes them suitable for embedding into an 
image, if required by the environment. We make a handful of *Bootstrap* 
scripts available [here](BootStrapScripts), and also provide templates for 
creating others.

**Bootstrap Script Templates:**
- [Linux Bootstrap script Template](TemplateScripts/SystemPrep-Bootstrap-Template-Linux.sh)
- [Windows Bootstrap script Template](TemplateScripts/SystemPrep-Bootstrap-Template-Windows.ps1)

### Master Scripts

*Master* scripts orchestrate the execution of content scripts. A master script 
contains a list of all the content scripts to execute and any required 
parameters, and it executes the content scripts accordingly. Separating the 
bootstrap script and the master script in this manner makes it simple to 
adjust the provisioning framework as requirements change, without 
changing the OS image in any way. Further, it also streamlines the process for 
providing new OS versions or updating OS images with patches, as there is no 
impact to any embedded components of the provisioning and configuration 
framework.

The included [*Master* scripts](MasterScripts) may be used as templates for 
creating alternative *Master* scripts. Dedicated *Master* script templates
will be added a later time.

### Content Scripts

*Content* scripts are the workhorses of the capability. Content scripts 
download content, install software, and perform configuration actions. While 
content scripts can be utilized to perform configuration actions directly, we 
would recommend utilizing a content script to initialize a configuration 
management solution and apply a specific configuration state. **SystemPrep** 
provides *Content* script templates that can be modified as necessary.

**Content Script Templates:**
- [Windows Content script Template](TemplateScripts/SystemPrep-Content-WindowsTemplate.ps1)

In addition, to demonstrate the capability, **SystemPrep** includes a single 
*Content* script that installs [Salt][0] and configures Salt for masterless 
operations. Optionally, the Salt *Content* script will also:

- Download salt formulas and configure the `file_roots` parameter accordingly
- Execute one or more Salt states
 
(Technically, there's one *Content* script for 
[Linux](SystemContent/Linux/Salt/SystemPrep-LinuxSaltInstall.py) and one for 
[Windows](SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1), 
but they perform the same function for their respective OS.)

- [Linux Salt Install *Content* script](SystemContent/Linux/Salt/SystemPrep-LinuxSaltInstall.py)
- [Windows Salt Install *Content* script](SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1)

## Included Use Cases

Pulling all of this together, **SystemPrep** includes one use case today, 
System Hardening, and may include more in the future.

- [System Hardening](#system-hardening)

### System Hardening

A very common workflow when provisioning systems includes the usage of a 
static system image, e.g. gold disk, with a number of baked-in configuration 
settings intended to harden the system. Often, this gold disk is the only 
image of the OS that is approved for usage in an environment. However, gold 
disks are static and difficult to update. Technology moves fast, but gold 
disks do not. 

We use **SystemPrep** to distribute a programmatic approach to hardening a 
system. This approach is far more dynamic, and far easier to extend or update, 
than a static gold disk. 

To implement this use case, *Bootstrap* scripts and *Master* scripts were 
developed that leverage the Salt *Content* script. In addition, we distribute
a handful of files that instruct Salt how to apply the system hardening 
configuration. These files leverage Salt formulas developed to implement 
pieces of the configuration.

    [Salt formulas][1] are a set of stand-alone Salt states purpose-built to 
    implement a specific bit of functionality.

**Required Salt Formulas:**

- [Automated System Hardening - Windows (ash-windows) Formula](../../../ash-windows-formula)
- [Automated System Hardening - Linux (ash-linux) Formula](../../../ash-linux-formula)
- [Microsoft EMET Formula](../../../emet-formula)
- [Microsoft Netbanner Formula](../../../netbanner-formula)

**Implementation Details:**

The [provided *Master* scripts](MasterScripts) include the set of parameters 
and values to pass to the Salt *Content* scripts. (There is one of each script 
type for Windows and one for Linux.) These parameters include the URL to the 
Salt *Content* script, the URL source of the salt-content.zip file (containing 
the Salt configuration files), and the URL sources of the Salt formulas listed 
above. Parameters passed from a *Master* script to a *Content* script override 
any default values that may exist in the *Content* script. **Adjust the 
parameters as necessary for the environment.**

*Master* Script Parameters for the Salt *Content* Script (Windows):

```
ScriptUrl  = "https://url/to/SystemPrep-WindowsSaltInstall.ps1"
SaltWorkingDir = "${SystemPrepWorkingDir}\SystemContent\Windows\Salt" 
SaltContentUrl = "https://url/to/salt-content.zip" 
FormulasToInclude = @(
                    "https://url/to/ash-windows-formula-master.zip",
                    "https://url/to/dotnet4-formula-master.zip"
                    "https://url/to/emet-formula-master.zip",
                    "https://url/to/netbanner-formula-master.zip"
                   )
FormulaTerminationStrings = @( "-latest", "-master" )
AshRole = "MemberServer"
NetBannerLabel = "Unclass"
SaltStates = "Highstate"
```

There are several [provided *Bootstrap* scripts](BootStrapScripts), the 
differences being the infrastructure environment and the system role. The 
system roles (Windows-only) are based on the `role` parameter of the 
ash-windows formula. Bootstrap scripts also contain parameters that
are passed through the *Master* script to the *Content* script. Parameters 
set in a *Bootstrap* script override parameter values in a *Master* script, 
and they override default values that may exist in a *Content* script. This 
behaviour reduces the need to have multiple *Master* scripts. These parameters
may be modified as necessary to adjust the behaviour of the system being
provisioned.

*Bootstrap* Script Parameters for the *Master* Script (Windows):

```
$SystemPrepParams = @{
    AshRole = "MemberServer"
    NetBannerLabel = "Unclass"
    SaltStates = "Highstate"
    NoReboot = $false
}
```

## References
- [SaltStack Salt - Community Edition][0]
- [Salt Formulas][1]
- [Python Docs on **kwargs][2]
- [Another Description of **kwargs[3]

[0]: https://github.com/saltstack/salt
[1]: http://docs.saltstack.com/en/latest/topics/development/conventions/formulas.html
[2]: https://docs.python.org/3.4/tutorial/controlflow.html#keyword-arguments
[3]: http://agiliq.com/blog/2012/06/understanding-args-and-kwargs/
