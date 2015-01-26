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

**SystemPrep** abstracts the provisioning and configuration process into three 
components:

- [*Bootstrap* scripts](#bootstrap-scripts)
- [*Master* scripts](#master-scripts)
- [*Content* scripts](#content-scripts)


### Bootstrap Scripts

*Bootstrap* scripts are very lightweight and relatively static. Their primary 
task is to download and execute the *Master* script. They may also establish a 
log file. They may also pass parameters to the *Master* script (and the 
*Master* script may, in turn, [\*\*kwargs-style][1], pass them to a *Content* 
script). *Bootstrap* scripts are tailored slightly to account for differences 
in provisioning mechanisms (E.g. Amazon EC2 instances, VMware templates, 
Microsoft Azure, Microsoft SCCM, PXE boot, etc). However, once created for the 
environment they should rarely require any modification. This fixed, static 
nature is a key feature of a *Bootstrap* script, and makes them suitable for 
embedding into an image, if required by the environment. We make a handful of 
*Bootstrap* scripts available [here](BootStrapScripts)(see the [Use Case]
(#included-use-cases) section before using them), and also provide templates 
for creating others.

**Bootstrap Script Templates:**
- [Linux *Bootstrap* script Template](TemplateScripts/SystemPrep-Bootstrap-Template-Linux.sh)
- [Windows *Bootstrap* script Template](TemplateScripts/SystemPrep-Bootstrap-Template-Windows.ps1)


### Master Scripts

*Master* scripts orchestrate the execution of *Content* scripts. A *Master* 
script contains a list of all the *Content* scripts to execute and any 
required parameters, and it executes the *Content* scripts accordingly. 
Separating the *Bootstrap* script and the *Master* script in this manner makes 
it simple to adjust the provisioning framework as requirements change, without 
changing the OS image in any way. Further, it also streamlines the process for 
providing new OS versions or updating OS images with patches, as there is no 
impact to any embedded components of the provisioning and configuration 
framework.

The [included *Master* scripts](MasterScripts) may be used as templates for 
creating alternative *Master* scripts. Dedicated *Master* script templates
will be added a later time.


### Content Scripts

*Content* scripts are the workhorses of the **SystemPrep** capability. 
*Content* scripts download content, install software, and perform 
configuration actions. While *Content* scripts can be utilized to perform 
configuration actions directly, we would recommend utilizing a *Content* 
script to initialize a configuration management solution and apply a specific 
configuration state. **SystemPrep** provides *Content* script templates that 
can be modified as necessary.

**Content Script Templates:**
- [Windows *Content* script Template](TemplateScripts/SystemPrep-Content-WindowsTemplate.ps1)
- A Linux *Content* script Template will be added later

In addition, to demonstrate the capability, **SystemPrep** includes a single 
*Content* script that installs [Salt][0] and configures Salt for masterless 
operations. Optionally, the Salt *Content* script will also:

- Download salt formulas and configure the `file_roots` parameter accordingly
- Execute one or more Salt states
 
(Technically, there's one *Content* script for 
[Linux](SystemContent/Linux/Salt/SystemPrep-LinuxSaltInstall.py) and one for 
[Windows](SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1), 
but they perform the same function for their respective OS.)

**Included Content Scripts:**

- [Linux Salt Install *Content* script](SystemContent/Linux/Salt/SystemPrep-LinuxSaltInstall.py)
- [Windows Salt Install *Content* script](SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1)


## Included Use Cases

Pulling all of this together, **SystemPrep** includes one use case today, 
_System Hardening_. Additional use cases may be developed in the future.

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
developed that leverage the Salt *Content* script (described above). In 
addition, we distribute a handful of files that instruct Salt how to apply 
the system hardening configuration. These files leverage [Salt formulas][1] 
developed to implement pieces of the configuration.

> **NOTE**: Salt formulas are a set of stand-alone Salt states purpose-built 
to implement a specific bit of functionality.

**Required Salt Formulas:**

- [Automated System Hardening - Windows (ash-windows) Formula][4]
- [Automated System Hardening - Linux (ash-linux) Formula][5]
- [Microsoft EMET Formula](../../../emet-formula)
- [Microsoft Netbanner Formula](../../../netbanner-formula)


####Implementation Details

The [provided *Master* scripts](MasterScripts) include the set of parameters 
and values to pass to the Salt *Content* scripts. (There is one of each script 
type for Windows and one for Linux.) These parameters include the URL to the 
Salt *Content* script, the URL source of the salt-content.zip file (containing 
the Salt configuration files), and the URL sources of the Salt formulas listed 
above, plus a few other script parameters. Parameters passed from a *Master* 
script to a *Content* script override any default values that may exist in the 
*Content* script. **Adjust the parameters as necessary for the environment.**

<b>*Master* Script Parameters for the Salt *Content* Script (Windows)</b>:

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
differences among them being the target infrastructure environment and the 
system role. The system roles (Windows-only) are based on the `role` parameter 
of the [ash-windows formula][4]. *Bootstrap* scripts also contain parameters 
that are passed through the *Master* script to the *Content* script. Parameters 
set in a *Bootstrap* script override parameter values in a *Master* script, 
and they override default values that may exist in a *Content* script. This 
behaviour reduces the need to have multiple *Master* scripts. **These 
parameters may be modified as necessary at runtime to adjust the behaviour of 
the system being provisioned.**

<b>*Bootstrap* Script Parameters for the *Master* Script (Windows)</b>:

```
$SystemPrepParams = @{
    AshRole = "MemberServer"
    NetBannerLabel = "Unclass"
    SaltStates = "Highstate"
    NoReboot = $false
}
```

- `AshRole`: Configures the system according to the system role. This parameter
is based on the `role` setting from the [ash-windows Formula][4]. Any value 
other than those listed will revert to the system default:
  - `"Memberserver"`
  - `"DomainController"`
  - `"Workstation"`

- `NetBannerLabel`: Applies the Netbanner settings associated with the 
specified label. See the [Netbanner Formula][7] for details.

- `SaltStates`: Comma-separated list of Salt states to apply to the system. 
This parameter is passed through to the Salt Install *Content* script. 
`"Highstate"` is a special keyword that applies the [Salt Highstate][13]. 

- `NoReboot`: Boolean parameter that controls whether the *Master* script will 
reboot the system upon completion of the script. Acceptable values are `$true`
or `$false`.

#### Usage Details

With the *Master* script, the *Content* script, and any required content 
properly hosted on a web server (see [Dependencies](#dependencies)), using the 
**SystemPrep** framework is simply a matter of executing the *Bootstrap* script
on the system. The method by which that is accomplished depends on the 
infrastructure environment.

- **Amazon EC2**: Use the *Bootstrap* script as `user data` when creating the 
instance. Amazon's documentation on this is rather lacking, but hints on how 
it works can be found [here][8] and [here][9]. There are a number of other 
sites with more helpful examples, for example, [here][10], [here][11], and 
[here][12]. If using the AWS Console, simply paste the contents of the 
*Bootstrap* script into the "User data" section (*Step 3*->*Advanced Details*) 
of the "Launch Instance" wizard.

- **VMware vCenter/vSphere**: Inject the *Bootstrap* script into the template 
and call it with a run-once script. For Windows, calling the script can be 
accomplished via a Customization Specification; Linux customization 
specifications lack the run-once capability, so it would need to be executed 
via the `init` system. (Either case requires managing the template, which is 
basically a static image, so this is sub-optimal, but it's still better than 
managing all of the configuration settings within the static image itself.)

- **PXE-boot**: On a Linux system, the *Bootstrap* script could be integrated 
into a `%post` kickstart script. Windows systems support similar capability 
via Microsoft WDS, MDT, and ADK.


## References
- [SaltStack Salt - Community Edition][0]
- [Salt Formulas][1]
- [Salt Highstate][13]
- [Python Docs on **kwargs][2]
- [Another Description of **kwargs][3]
- [Automated System Hardening - Windows (ash-windows)][4]
- [Automated System Hardening - Linux (ash-linux) Formula][5]
- [Microsoft EMET Formula][6]
- [Microsoft Netbanner Formula][7]
- [AWS - Running Commands at Instance Launch][8]
- [AWS - Using the EC2Config Service for Windows][9]
- [Automate EC2 Instance Setup with user-data Scripts][10]
- [Automatically provisioning Amazon EC2 instances with Tentacle installed][11]
- [Bootstrapping Windows Servers][12]

[0]: https://github.com/saltstack/salt
[1]: http://docs.saltstack.com/en/latest/topics/development/conventions/formulas.html
[2]: https://docs.python.org/3.4/tutorial/controlflow.html#keyword-arguments
[3]: http://agiliq.com/blog/2012/06/understanding-args-and-kwargs/
[4]: ../../../ash-windows-formula
[5]: ../../../ash-linux-formula
[6]: ../../../emet-formula
[7]: ../../../netbanner-formula
[8]: http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html
[9]: http://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/UsingConfig_WinAMI.html
[10]: http://alestic.com/2009/06/ec2-user-data-scripts
[11]: http://octopusdeploy.com/blog/auto-provision-ec2-instances-with-tentacle-installed
[12]: http://www.masterzen.fr/2014/01/11/bootstrapping-windows-servers-with-puppet/
[13]: http://docs.saltstack.com/en/latest/ref/states/highstate.html