# Introduction

The Security Controls Traceability Matrix (SCTM) relates requirements from
requirement source documents to the security assessment and authorization
process. It ensures that all security requirements are identified and
investigated. Each entry of the matrix identifies a specific requirement and
provides the details of how it was implemented, and how it was tested or
analyzed and the results.

The matrix is arranged to display the system security requirements from the
applicable regulation documents, which are listed below:

- [NIST 800-53, Revision 4](
http://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r4.pdf),
Security and Privacy Controls for Federal Information Systems and Organizations
- [CNSSI 1253, 27 March 2014](
https://www.cnss.gov/CNSS/openDoc.cfm?Mks5eBBtYkCVcXNhRPhlIA==),
Security Categorization and Control Selection for National Security Systems

The data elements of the SCTM are defined as follows:

- **Project Name**
    - Refers to the name of the project that implements the security controls.
- **Targets**
    - Refers to the list of Operating System or application versions to which
    the project or configuration item applies.
- **Control Ref.**
    - Refers to the ID or paragraph number of the listed control or
    requirement.
- **Control Name**
    - Short title describing the security control or requirement (and the
    text of the control/requirement, which may be paraphrased for brevity).
- **Control Type**
    - **Common**. Auto-populated if the requirement is designated to one or
    more
    information systems.
    - **Hybrid**. Auto-populated if the requirement is identified with two
    security control types: common and system-specific; i.e., a part of the
    requirement is identified as common type and another part of it is
    system-specific.
    - **System-Specific**. Auto-populated if the requirement is assigned to a
    specific information system.
    - **Inherited**. Auto-populated if the requirement is inherited from
    another system.
    - **Not Specified**. Auto-populated if the requirement does not require any
    security control.
- **Implementation**
    - Describes how the security control is implemented.
- **Source Ref**
    - Describes the source proscribing the requirement configuration or value.

The SCTM is formatted using a markup language, *Yet Another Markup Language*
(YAML). YAML is structured, which means it is machine readable, but it is
also designed be human readable. This means it is easy to read directly, as
well as trivial to ingest and manipulate with a software program. Further,
being simple text, YAML files may be managed in a version control system (i.e.,
git) to track changes over time.

The data structure of the YAML SCTM is as follows:

```
datamodel: <string containing the version of the data model>
projects: <dictionary of projects>
  <project name>:
    targets: <list of target OS or application versions for the project as a whole>
    controls:
      <control ref>:
        name: <control name>
        type: <control type>
        source_ref: <list of common source references for the configuration>
        implementation: <list of dictionaries containing implementation details>
          - action: <string describing the configuration being applied>
            parameters: <list of parameters to apply to the action>
            targets: <optional list of targets for this specific configuration, overrides control targets>
            source_ref: <optional list of source reference overrides for the configuration>
          - action: <string describing the configuration being applied>
            parameters: <list of parameters to apply to the action>
            targets: <optional list of targets for this specific configuration, overrides control targets>
            source_ref: <optional list of source reference overrides for the configuration>
      <control ref>:
        name: <control name>
        type: <control type>
        source_ref: <list of common source references for the configuration>
        implementation: <list of dictionaries containing implementation details>
          - action: <string describing the configuration being applied>
            parameters: <list of parameters to apply to the action>
            targets: <optional list of targets for this specific configuration, overrides control targets>
            source_ref: <optional list of source reference overrides for the configuration>
          - action: <string describing the configuration being applied>
            parameters: <list of parameters to apply to the action>
            targets: <optional list of targets for this specific configuration, overrides control targets>
            source_ref: <optional list of source reference overrides for the configuration>

  <project name>:
    targets: <list of target OS or application versions for the project as a whole>
    controls:
      <control ref>:
        name: <control name>
        type: <control type>
        source_ref: <list of common source references for the configuration>
        implementation: <list of dictionaries containing implementation details>
          - action: <string describing the configuration being applied>
            parameters: <list of parameters to apply to the action>
            targets: <optional list of targets for this specific configuration, overrides control targets>
            source_ref: <optional list of source reference overrides for the configuration>
          - action: <string describing the configuration being applied>
            parameters: <list of parameters to apply to the action>
            targets: <optional list of targets for this specific configuration, overrides control targets>
            source_ref: <optional list of source reference overrides for the configuration>
      <control ref>:
        name: <control name>
        type: <control type>
        source_ref: <list of common source references for the configuration>
        implementation: <list of dictionaries containing implementation details>
          - action: <string describing the configuration being applied>
            parameters: <list of parameters to apply to the action>
            targets: <optional list of targets for this specific configuration, overrides control targets>
            source_ref: <optional list of source reference overrides for the configuration>
          - action: <string describing the configuration being applied>
            parameters: <list of parameters to apply to the action>
            targets: <optional list of targets for this specific configuration, overrides control targets>
            source_ref: <optional list of source reference overrides for the configuration>
```

The SCTM data may be found in the [SCTM.yml](SCTM.yml) file.
