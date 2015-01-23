# SystemPrep
**SystemPrep** helps provision a system from its initial installation to its 
final configuration. It consists of a framework of highly-customizable scripts. 
For Linux systems, the scripts are written in python; for Windows systems, the 
scripts are written in PowerShell. As it leverages OS-native capabilities to 
bootstrap a system, **SystemPrep** has very few inherent dependencies. More 
complex configuration management (CM) environments may be layered in as part 
of the **SystemPrep** framework. We use Salt to demonstrate how to layer in a 
CM tool and build a functioning system hardening capability, but feel free to 
use any CM tool of your choice.

## Goals
- Provide a system provisioning framework that is portable, agile, and 
extensible.
- Enable rapid deployment of new Operating System (OS) versions and patches.
- Apply overarching policy requirements to new OS instances (security 
hardening, management policies, management agents and tools, etc).
- Support centralized and de-centralized management environments and any 
infrastructure environment
  - Physical, virtual, or cloud
  - Domain-joined or standalone
  - Connected or disconnected
- Eliminate licensing costs and overhead concerns with configuration 
management tools

## Design Principles
- Decouple a system's configuration from its underlying OS image (AMI, ISO, 
template, etc).
- Conversely, *never* bake configuration items into the OS image.
- Utilize system-native tools to bootstrap the system into a configuration 
management framework.
- Leverage a cross-platform configuration management solution to apply required 
policies to the OS instance.
- Modularize the framework so it may support multiple OS-types, infrastructure 
types (physical, virtual, cloud), configuration management solutions, etc. 
- Integrate with a version control system to manage framework content

## SystemPrep Components
**SystemPrep** scripts are divided into three components:

- Bootstrap scripts
- Master scripts
- Content scripts

*Bootstrap scripts* are very lightweight and static. Their primary task is to 
download and execute the master script. They may also establish a log file. 
Bootstrap scripts are tailored slightly to account for differences in 
provisioning mechanisms (E.g. Amazon EC2 instances, VMware templates, 
Microsoft Azure, Microsoft SCCM, PXE boot, etc), but once created for the 
environment they should rarely require any modification. This fixed, static 
nature is a key feature of a bootstrap script, and makes them suitable for
embedding into an image, if required by the environment.

*Master scripts* orchestrate the execution of content scripts. A master script 
contains a list of all the content scripts to execute and any required 
parameters, and it executes the content scripts accordingly. Separating the 
bootstrap script and the master script in this manner makes it simple to 
adjust the provisioning framework as requirements change, without 
changing the OS image in any way. Further, it also streamlines the process for 
providing new OS versions or updating OS images with patches, as there is no 
impact to embedded components of the provisioning and configuration framework.

*Content scripts* are where the work happens. Content scripts download content, 
install software, and perform configuration actions. While content scripts can 
be utilized to perform configuration actions directly, we would recommend 
utilizing a content script to initialize a configuration management solution 
and apply a specific configuration state.




