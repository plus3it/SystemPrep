[![Build Status](https://travis-ci.org/plus3it/SystemPrep.svg)](https://travis-ci.org/plus3it/SystemPrep)

# SystemPrep

**SystemPrep** helps provision a system from its initial installation to its
final configuration. It was inspired by a desire to eliminate static system
images with embedded configuration settings (e.g. gold disks) and the pain
associated with maintaining them.

**SystemPrep** consists of a framework of highly-customizable scripts. For
Linux systems, the scripts are written primarily in python (the one exception
is that *[Bootstrap scripts](#bootstrap-scripts)* are written in bash); for
Windows systems, the scripts are written in PowerShell. As it leverages
OS-native capabilities to bootstrap a system, **SystemPrep** has very few
inherent dependencies. More complex configuration management (CM) environments
may be layered in as part of the **SystemPrep** framework. We use [Salt][0] to
demonstrate how to layer in a CM tool and build a functioning system hardening
capability, but feel free to use any CM tool of your choice.


## Quick Start

If you are not interested in the messy details and just want to know how to
apply this framework to an instance, this section is for you. The resulting
instance will have the full OS security lockdown described by the DISA STIG.

We are going to use AWS for this Quick Start, so first make sure you have an
account with permissions to launch an instance before continuing. You will
also want to have either the `awscli` or `AWS Tools for PowerShell`, as the
commands below utilize one of those tools.

For Linux instances, we are using the AMI named
"*RHEL-6.7_HVM_GA-20150714-x86_64-1-Hourly2-GP2*" (ami-0d28fe66), which we
know has the `cloud-init` package, which is required to process user-data. You
should be able to use most any RHEL6 Marketplace AMI. CentOS6 AMIs from the
Marketplace are typically insufficient, as they lack the `cloud-init` package.

For Windows instances, we are using the first AMI returned with an AMI Name
that matches the pattern, "*Windows_Server-2012-R2_RTM-English-64Bit-Base-**".
Feel free to adjust the search pattern as you like; any Windows AMI provided
by Amazon directly should work.


### From a Linux Terminal

The quick start commands here use the command-line utility, [`awscli`]
(https://aws.amazon.com/cli/). Make sure you have it installed and configured,
or these commands will not work.

1. Find the name of the key-pair you want to associate with the instance.

    ```
    aws ec2 describe-key-pairs
    ```

2. From the output, identify the key-pair to use, and note the value in the
`KeyName` field. Save the value in a variable named `key`.

    ```
    key="<KeyName>"
    ```

3. Find the security group you want to assign to the instance. For the purpose
of this Quick Start, you probably want to use a security group that allows
inbound port 22 (for a Linux instance), or inbound port 3389 (for a Windows
instance).

    ```
    aws ec2 describe-security-groups
    ```

4. From the output, identify the security group to use, and note the value in
the `GroupId` field. Save the value in a variable named `sg`.

    ```
    sg="<GroupId>"
    ```

5. Launch the Linux instance by pasting the code-block below into the bash
shell.

    ```
    userdata="https://s3.amazonaws.com/systemprep/BootStrapScripts/SystemPrep-Bootstrap--Linux.sh"
    region="us-east-1"
    amipattern="RHEL-6.7_HVM_GA-*-x86_64-1-Hourly2-GP2"
    ami=$(aws ec2 describe-images --region $region --filters Name="name",Values="$amipattern" --query 'Images[0].ImageId' --out text)

    aws ec2 run-instances \
    --image-id $ami \
    --user-data $userdata \
    --key-name $key \
    --security-group-ids $sg \
    --instance-type t2.micro \
    --associate-public-ip-address \
    --region $region
    ```

6. Next we will launch a Windows instance. If you would like to change the key-pair
or security group, repeat steps 1 through 4 as needed.

    ```
    userdata="https://s3.amazonaws.com/systemprep/BootStrapScripts/SystemPrep-Bootstrap-EC2-Windows.txt"
    region="us-east-1"
    amipattern="Windows_Server-2012-R2_RTM-English-64Bit-Base-*"
    ami=$(aws ec2 describe-images --region $region --filters Name="name",Values="$amipattern" --query 'Images[0].ImageId' --out text)

    aws ec2 run-instances \
    --image-id $ami \
    --user-data $userdata \
    --key-name $key \
    --security-group-ids $sg \
    --instance-type t2.micro \
    --associate-public-ip-address \
    --region $region
    ```

It will take 5-15 minutes for the instance to launch, apply the security
baseline, and reboot, but that is all there is to it! Login to the instance
and look around.


### From a Windows PowerShell Terminal

The quick start commands here use the utility [`AWS Tools for PowerShell`]
(https://aws.amazon.com/powershell/). Make sure you have it installed and
configured, or these commands will not work.

1. Open a PowerShell windows and find the name of the key-pair you want to
associate with the instance.

    ```
    Get-EC2KeyPair
    ```

2. From the output, identify the key-pair to use, and note the value in the
`KeyName` field. Save the value in a variable named `key`.

    ```
    $key="<KeyName>"
    ```

3. Find the security group you want to assign to the instance. For the purpose
of this Quick Start, you probably want to use a security group that allows
inbound port 22 (for a Linux instance), or inbound port 3389 (for a Windows
instance).

    ```
    Get-EC2SecurityGroup
    ```

4. From the output, identify the security group to use, and note the value in
the `GroupId` field. Save the value in a variable named `sg`.

    ```
    $sg="<GroupId>"
    ```

5. Launch the Linux instance by pasting the code-block below into the
PowerShell window.

    ```
    $userdata_uri="https://s3.amazonaws.com/systemprep/BootStrapScripts/SystemPrep-Bootstrap--Linux.sh"
    $userdata=[System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -URI $userdata_uri).Content)
    $region="us-east-1"
    $amipattern="RHEL-6.7_HVM_GA-*-x86_64-1-Hourly2-GP2"

    New-EC2Instance -Region $region `
    -ImageId $ami `
    -KeyName $key `
    -SecurityGroupId $sg `
    -UserData $userdata -EncodeUserData `
    -InstanceType t2.micro `
    -AssociatePublicIp $true
    ```

6. Next we will launch a Windows instance. If you would like to change the key-pair
or security group, repeat steps 1 through 4 as needed.

    ```
    $userdata_uri="https://s3.amazonaws.com/systemprep/BootStrapScripts/SystemPrep-Bootstrap-EC2-Windows.txt"
    $userdata=(Invoke-WebRequest -URI $userdata_uri).Content
    $region="us-east-1"
    $amipattern="Windows_Server-2012-R2_RTM-English-64Bit-Base-*"
    $ami=$((Get-EC2ImageByName -Region $region -Names "$amipattern")[0].ImageId)

    New-EC2Instance -Region $region `
    -ImageId $ami `
    -KeyName $key `
    -SecurityGroupId $sg `
    -UserData $userdata -EncodeUserData `
    -InstanceType t2.micro `
    -AssociatePublicIp $true
    ```

It will take 5-15 minutes for the instance to launch, apply the security
baseline, and reboot, but that is all there is to it! Login to the instance
and look around.


### Cloudformation Templates

We also provide AWS Cloudformation templates that are integrated with the
SystemPrep framework. Feel free to use them as quick start examples to get a
feel for the framework, or as reference examples for building your own
templates.

- [Deploy a single RHEL6 instance]
(Utils/cfn/systemprep-lx-instance.template)
- [Deploy an Autoscaling Group of one or more RHEL6 instances]
(Utils/cfn/systemprep-lx-autoscale.template)
- [Deploy a single Windows 2012 R2 instance]
(Utils/cfn/systemprep-win-instance.template)
- [Deploy an Autoscaling Group of one or more Windows 2012 R2 instances]
(Utils/cfn/systemprep-win-autoscale.template)

These CloudFormation templates support a handful of additional parameters
intended to offer a simple option for application lifecycle management and
sustainment.

- Use the parameter `SystemPrepEnvironment` to specify the environment in
which the instance is deploying and take advantage of any custom SystemPrep
integrations with enterprise services. Leave this parameter at the default
value of `false` to apply only the common SystemPrep hardening formulas.
- Use the parameter `SystemPrepOuPath` to specify the full DN of the OU in
which to place the instance. Used only when the environment specified includes
a domain join task. If blank and `SystemPrepEnvironment` enforces a domain
join, the instance will be placed in a default container. Leave blank if not
joining a domain, or if `SystemPrepEnvironment` is `false`.
- Three parameters support the ability to execute a script specified by the
application owner. Use cases for this script include installing an application,
managing application configuration, updating application versions, or really
whatever else you can think of: `AppScriptUrl`, `AppScriptShell`, and
`AppScriptParams`.
- The templates all use AWS resource metadata and the [CloudFormation
Init utilities][16] to execute tasks during a stack launch or a stack update.
  - Use the parameter `ToggleCfnInitUpdate` during a stack update to force a
  change to metadata, resulting in the execution of the 'update' tasks.
  - Use the parameter `ToggleNewInstances` (**Autoscale only**) to deploy new
  instances during a stack update (by changing the userdata, which triggers
  the UpdatePolicy on the AutoScale group and initiates a RollingUpdate).
- Control whether the instance reboots after executing the cfn-init tasks
using the parameter `NoReboot`.
- Control whether to assign a public IP to the instance(s) using the parameter
`NoPublicIp`. Recommend leaving the value at the default `true` _unless_
launching in a public subnet. If launching into a public subnet, then it is
required to set this to `false` or the instance will not have the necessary
network connectivity outside the VPC.
- (**Linux only**) Control whether to install patches with `yum -y update`
during a stack update with the parameter `NoUpdates`. (**NOTE**: This
parameter controls _only_ the stack update behaviour. During a stack launch,
the SystemPrep ash-linux formula _always_ installs patches.)


# Messy Details

## Dependencies

- A web-accessible service to host the *Master* script(s) and *Content*
script(s), as well as any content (binaries, config files, etc) that must be
distributed to the system. The service must be reachable from the system
executing the *Bootstrap* script
  - If using a basic web server to host the files, the web server must not
    require authentication.
  - If using an S3 bucket to host the files, and running **SystemPrep** from
    an EC2 instance, the instance must have an IAM role that grants it the
    `GetObject` privilege to the bucket. Set `SourceIsS3Bucket` to `true` in
    the *Bootstrap* script. See [Implementation Details]
    (#implementation-details).


## SystemPrep Components

**SystemPrep** abstracts the provisioning and configuration process into three
components:

- *[Bootstrap scripts](#bootstrap-scripts)*
- *[Master scripts](#master-scripts)*
- *[Content scripts](#content-scripts)*


### Bootstrap Scripts

*Bootstrap* scripts are very lightweight and relatively static. Their primary
task is to download and execute the *Master* script. They may also establish a
log file. They may also pass parameters to the *Master* script (and the
*Master* script may, in turn, [\*\*kwargs-style][2], pass them to a *Content*
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
- [Linux Bootstrap script Template](TemplateScripts/SystemPrep-Bootstrap-Template-Linux.sh)
- [Windows Bootstrap script Template](TemplateScripts/SystemPrep-Bootstrap-Template-Windows.ps1)


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

The [included Master scripts](MasterScripts) may be used as templates for
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
- [Windows Content script Template](TemplateScripts/SystemPrep-Content-WindowsTemplate.ps1)
- A Linux *Content* script Template will be added later

In addition, to demonstrate the capability, **SystemPrep** includes a single
*Content* script that installs [Salt][0] and configures Salt for masterless
operations. Optionally, the Salt *Content* script will also:

- Download salt formulas and configure the `file_roots` parameter accordingly
- Execute one or more Salt states

(Technically, there's one *Content* script for
[Linux](ContentScripts/SystemPrep-LinuxSaltInstall.py) and one for
[Windows](ContentScripts/SystemPrep-WindowsSaltInstall.ps1),
but they perform the same function for their respective OS.)

**Included Content Scripts:**

- [Linux Salt Install Content script](ContentScripts/SystemPrep-LinuxSaltInstall.py)
- [Windows Salt Install Content script](ContentScripts/SystemPrep-WindowsSaltInstall.ps1)


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

> **NOTE**: A Salt formula is a set of one or more stand-alone Salt states
purpose-built to implement a specific bit of functionality.

**Required Salt Formulas:**

- [Automated System Hardening - Windows (ash-windows) Formula][4]
- [Automated System Hardening - Linux (ash-linux) Formula][5]
- [Microsoft dotnet4 Formula][14]
- [Microsoft EMET Formula][6]
- [Microsoft Netbanner Formula][7]


#### Implementation Details

The [provided Master scripts](MasterScripts) include the set of parameters
and values to pass to the Salt *Content* scripts. (There is one of each script
type for Windows and one for Linux.) These parameters include the URL to the
Salt *Content* script, the URL source of the salt-installer.zip file (containing
the binaries required to install Salt), the URL source of the salt-content.zip
file (containing the Salt configuration files), and the URL sources of the Salt
formulas listed above, plus a few other script parameters. Parameters passed
from a *Master* script to a *Content* script override any default values that
may exist in the *Content* script. **Adjust the parameters as necessary for the
environment.**

<b>*Master* Script Parameters for the Salt *Content* Script (Windows)</b>:

```
ScriptUrl  = "https://url/to/SystemPrep-WindowsSaltInstall.ps1"
SaltWorkingDir = "${SystemPrepWorkingDir}\SystemContent\Windows\Salt"
SaltInstallerUrl = "https://url/to/salt-installer.zip"
SaltContentUrl = "https://url/to/salt-content.zip"
FormulasToInclude = @(
                    "https://url/to/systemprep-formula-master.zip",
                    "https://url/to/ash-windows-formula-master.zip",
                    "https://url/to/dotnet4-formula-master.zip"
                    "https://url/to/emet-formula-master.zip",
                    "https://url/to/netbanner-formula-master.zip"
                    "https://url/to/mcafee-agent-windows-formula-master.zip"
                    "https://url/to/ntp-client-windows-formula-master.zip"
                    "https://url/to/splunkforwarder-windows-formula-master.zip"
                    "https://url/to/windows-update-agent-formula-master.zip"
                    "https://url/to/join-domain-formula-master.zip"
                    "https://url/to/scc-formula-master.zip"
                   )
FormulaTerminationStrings = @( "-latest", "-master" )
AshRole = "MemberServer"
EntEnv = $false
SaltStates = "Highstate"
SourceIsS3Bucket = $SourceIsS3Bucket
AwsRegion = $AwsRegion
```

There are several [provided Bootstrap scripts](BootStrapScripts), the
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
$SystemPrepMasterScriptUrl = 'https://url/to/SystemPrep-WindowsMaster.ps1'
$SourceIsS3Bucket = $true
$SystemPrepParams = @{
    AshRole = "MemberServer"
    EntEnv = $false
    SaltStates = "Highstate"
    SaltContentUrl = 'https://url/to/salt-content.zip'
    NoReboot = $false
    SourceIsS3Bucket = $SourceIsS3Bucket
    AwsRegion = "us-east-1"
}
```

- `SystemPrepMasterScriptUrl`: The URL hosting the *Master* script. This URL
must be accessible to the system when it runs the *Bootstrap* script.

- `SourceIsS3Bucket`: The **SystemPrep** framework supports using an S3 bucket
to host all files. If an S3 bucket is the source, set this parameter to `$true`
(the default). Otherwise, set it to `$false`. Note that **ALL** files must be
hosted in an S3 bucket (though they could be in different buckets). Also, the
EC2 instance must have an IAM role that grants it the `GetObject` privilege to
access objects in the bucket.

  The bucket URL format must use the path-style syntax:
  - `https://<s3endpoint>/<bucketname>/path/to/file`

  Path-style syntax means the `<bucketname>` is in the URI path after the
  `<s3endpoint>`. The **SystemPrep** scripts currently do not support using the
  virtual-host syntax. See Amazon's [S3 documentation on virtual hosting][15].

- `AshRole`: Configures the system according to the system role. This parameter
is based on the `role` setting from the [ash-windows Formula][4]. Any value
other than those listed will revert to the system default:
  - `"Memberserver"`
  - `"DomainController"`
  - `"Workstation"`

- `EntEnv`: Applies enterprise integration according to the environment in which the system is operating. This accepts a tri-state value:
  - `"True"`:  Attempt to detect the environment automatically. WARNING: Currently this value is non-functional.
  - `"False"`:  (Default) Do not set an environment. Any content that is dependent on the environment will not be available to this system.
  - `<string>`:  Set the environment to the value of `"<string>"`. Note that uppercase values will be converted to lowercase.
				  
- `SaltStates`: Comma-separated list of Salt states to apply to the system.
This parameter is passed through to the Salt Install *Content* script.
`"Highstate"` is a special keyword that applies the [Salt Highstate][13].

- `SaltContentUrl`: URL hosting an archive zip file of the salt content to apply to the system.
  - `<string>`:  Default is `"https://url/to/salt-content.zip"`.
	
- `NoReboot`: Boolean parameter that controls whether the *Master* script will
reboot the system upon completion of the script. Acceptable values are `$true`
or `$false`.

- `AwsRegion`: The region hosting the bucket containing the data. Option value is ignored unless `'-u|--use-s3-utils'` is set.
  - `<string>`:  Default is `"us-east-1"`.

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
into a `%post` kickstart script. Windows systems support similar functionality
via a combination of Microsoft WDS, MDT, and ADK.


## References
- [SaltStack Salt - Community Edition][0]
- [Salt Formulas][1]
- [Salt Highstate][13]
- [Python Docs on **kwargs][2]
- [Another Description of **kwargs][3]
- [Automated System Hardening - Windows (ash-windows)][4]
- [Automated System Hardening - Linux (ash-linux) Formula][5]
- [Microsoft dotnet Formula][14]
- [Microsoft EMET Formula][6]
- [Microsoft Netbanner Formula][7]
- [AWS - Running Commands at Instance Launch][8]
- [AWS - Using the EC2Config Service for Windows][9]
- [AWS - S3 documentation on virtual hosting][15]
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
[14]: ../../../dotnet4-formula
[15]: http://docs.aws.amazon.com/AmazonS3/latest/dev/VirtualHosting.html
[16]: http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-init.html
