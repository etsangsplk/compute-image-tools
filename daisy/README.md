# What is Daisy?
Daisy is a solution for running complex, multi-step workflows on GCE.

[![GoDoc](https://godoc.org/github.com/GoogleCloudPlatform/compute-image-tools/daisy?status.svg)](https://godoc.org/github.com/GoogleCloudPlatform/compute-image-tools/daisy)

The current Daisy stepset includes support for creating/deleting GCE resources,
waiting for signals from GCE VMs, streaming GCE VM logs, uploading local files
to GCE and GCE VMs, and more.

For example, Daisy is used to create Google Official Guest OS images. The
workflow:
1. Creates a Debian 8 disk and another empty disk.
2. Creates and boots a VM with the two disks.
3. Runs and waits for a script on the VM.
4. Creates an image from the previously empty disk.
5. Automatically cleans up the VM and disks.

Other use-case examples:
* Workflows for importing external physical or virtual disks to GCE.
* GCE environment deployment.
* Ad hoc GCE testing environment deployment and test running.

## Table of contents
  * [Setup](#setup)
    * [Prebuilt binaries](#prebuilt-binaries)
    * [Daisy container](#daisy-container)
    * [Build from source](#build-from-source)
  * [Running Daisy](#running-daisy)
  * [Workflow Config Overview](#workflow-config-overview)
    * [Sources](#sources)
    * [Steps](#steps)
      * [AttachDisks](#type-attachdisks)
      * [CreateDisks](#type-createdisks)
      * [CreateImages](#type-createimages)
      * [CreateInstances](#type-createinstances)
      * [CopyGCSObjects](#type-copygcsobjects)
      * [DeleteResources](#type-deleteresources)
      * [IncludeWorkflow](#type-includeworkflow)
      * [RunTests](#type-runtests)
      * [SubWorkflow](#type-subworkflow)
      * [WaitForInstancesSignal](#type-waitforinstancessignal)
    * [Dependencies](#dependencies)
    * [Vars](#vars)
      * [Autovars](#autovars)
  * [Glossary of Terms](#glossary-of-terms)
    * [GCE](#glossary-gce)
    * [GCP](#glossary-gcp)
    * [GCS](#glossary-gcs)
    * [Partial URL](#glossary-partialurl)
    * [Workflow](#glossary-workflow)

## Setup
### Prebuilt binaries
Prebuilt Daisy binaries are available for Windows, macOS, and Linux distros.
Two versions are available, one built with the v1 (stable) Compute api, and the
other with the beta Compute API. 

Built from the latest GitHub release (all 64bit):
+ [Windows](https://storage.googleapis.com/compute-image-tools/release/windows/daisy.exe)
+ [Windows beta](https://storage.googleapis.com/compute-image-tools/release/windows/daisy_beta.exe)
+ [macOS](https://storage.googleapis.com/compute-image-tools/release/darwin/daisy)
+ [macOS beta](https://storage.googleapis.com/compute-image-tools/release/darwin/daisy_beta)
+ [Linux](https://storage.googleapis.com/compute-image-tools/release/linux/daisy)
+ [Linux beta](https://storage.googleapis.com/compute-image-tools/release/linux/daisy_beta)

Built from the latest commit to the master branch (all 64bit):
+ [Windows](https://storage.googleapis.com/compute-image-tools/latest/windows/daisy.exe)
+ [Windows beta](https://storage.googleapis.com/compute-image-tools/latest/windows/daisy_beta.exe)
+ [macOS](https://storage.googleapis.com/compute-image-tools/latest/darwin/daisy)
+ [macOS beta](https://storage.googleapis.com/compute-image-tools/latest/darwin/daisy_beta)
+ [Linux](https://storage.googleapis.com/compute-image-tools/latest/linux/daisy)
+ [Linux beta](https://storage.googleapis.com/compute-image-tools/latest/linux/daisy_beta)

### Daisy container
Daisy containers are available at gcr.io/compute-image-tools/daisy. All the 
workflows in `compute-image-tools/daisy_workflows` are put in the `workflows` 
directory at the root of the container.
+ Built from the latest GitHub release: gcr.io/compute-image-tools/daisy:release
+ Built from the latest commit to the master branch: gcr.io/compute-image-tools/daisy:latest

Daisy containers built with the beta Compute api
+ Built from the latest GitHub release: gcr.io/compute-image-tools/daisy_beta:release
+ Built from the latest commit to the master branch: gcr.io/compute-image-tools/daisy_beta:latest

### Build from source
Daisy can be easily built from source with the [Golang SDK](https://golang.org)
```shell
go get github.com/GoogleCloudPlatform/compute-image-tools/daisy/daisy
```
This will place the Daisy binary in $GOPATH/bin.

## Running Daisy
The basic use case for Daisy looks like:
```shell
daisy [path to workflow config file]
```

Workflow variables can be set using the  `-variables` flag or the 
`-var:VARNAME` flag. The `-variables` flag takes a comma separated list
of `key=value` pairs. Both of these examples set the workflow variables 
`foo=bar` and `baz=gaz`:
```shell
daisy -variables foo=bar,baz=gaz wf.json
```

```shell
daisy -var:foo bar -var:baz gaz wf.json
```

For additional information about Daisy flags, use `daisy -h`.

## Workflow Config Overview
A workflow is described by a JSON config file and contains information for the
workflow's steps, step dependencies, GCE/GCP/GCS credentials/configuration,
and file resources. The config has the following fields (**NOTE: all
workflow and step field names are case-insensitive, but we suggest upper camel case.**):

| Field Name | Type | Description |
|-|-|-|
| Name | string | The name of the workflow. Must be between 1-20 characters and match regex **[a-z]\([-a-z0-9]\*[a-z0-9])?**|
| Project | string | The GCE and GCS API enabled GCP project in which to run the workflow, if no project is given and Daisy is running on a GCE instance, that instances project will be used. |
| Zone | string | The GCE zone in which to run the workflow, if no zone is given and Daisy is running on a GCE instance, that instances zone will be used. |
| OAuthPath | string | A local path to JSON credentials for your Project. These credentials should have full GCE permission and read/write permission to GCSPath. If credentials are not provided here, Daisy will look for locally cached user credentials such as are generated by `gcloud init`. |
| GCSPath | string | Daisy will use this location as scratch space and for logging/output results, if no GCSPath is given and Daisy will create a bucket to use in the project, subsequent runs will reuse this bucket. **NOTE**: Your workflow VMs need access to this location, use a bucket in the same project that you will launch instances in or grant your Project's default service account read/write permissions.|
| Sources | map[string]string | A map of destination paths to local and GCS source paths. These sources will be uploaded to a subdirectory in GCSPath. The sources are referenced by their key name within the workflow config. See [Sources](#sources) below for more information. |
| Vars | map[string]string | A map of key value pairs. Vars are referenced by "${key}" within the workflow config. Caution should be taken to avoid conflicts with [autovars](#autovars). |
| Steps | map[string]Step | A map of step names to Steps. See [Steps](#steps) below for more information. |
| Dependencies | map[string]list(string) | A map of step names to a list of step names. This defines the dependencies for a step. Example: a step "foo" has dependencies on steps "bar" and "baz"; the map would include "foo": ["bar", "baz"]. |

Example workflow config:
```json
{
  "Name": "my-wf",
  "Project": "my-project",
  "Zone": "us-central1-f",
  "OAuthPath": "path/to/my/creds.json",
  "GCSPath": "gs://my-bucket/some/path/",
  "Sources": {
    "foo": "local/path/to/file1",
    "bar": "gs://gcs/path/to/file2"
  },
  "Vars": {
    "step1": "step1 name",
    "step2": "step2 name"
  },
  "Steps": {
    "${step1}": ...,
    "${step2}": ...,
    "step3 name": ...
  },
  "Dependencies": {
    "${step2}": ["${step1}"],
    "step3-name": ["${step2}"]
  }
}
```

### Sources

Daisy will upload any workflow sources to the sources directory in GCS
prior to running the workflow. The `Sources` field in a workflow
JSON file is a map of 'destination' to 'source' file. Sources can be a local
or GCS file or directory. Directories will be recursively copied into
destination. The GCS path for the sources directory is available via the
[autovar](#autovars) `${SOURCESPATH}`.

In this example the local file `./path/to/startup.sh` will be copied to
`startup.sh` in the sources directory. Similarly the GCS file
`gs://my-bucket/some/path/install.py` will be copied to `install.py`.
The contents of paths referencing directories like
`./path/to/drivers_folder` and  `gs://my-bucket/my-files` will be
recursively copied to the directories `drivers` and `files` in GCS
respectively.

```json
"Sources": {
  "startup.sh": "./path/to/startup.sh",
  "install.py": "gs://my-bucket/some/path/install.py",
  "drivers": "./path/to/drivers_folder",
  "files": "gs://my-bucket/my-files"
}
```

### Steps
Step types are defined here:
https://godoc.org/github.com/GoogleCloudPlatform/compute-image-tools/daisy/workflow#Step

The `Steps` field is a named set of executable steps. It is a map of
a step's name to the step's type and configuration. Step names must begin with
a letter and only contain letters, numbers and hyphens.

For each individual 'step', you set one 'step type' and the type's
associated fields. You may optionally set a step timeout using
`Timeout`. `Timeout` uses [Golang's time.Duration string
format](https://golang.org/pkg/time/#Duration.String) and defaults
to "10m" (10 minutes). As with workflow fields, step field names are
case-insensitive, but we suggest upper camel case.

This example has steps named "step 1" and "step 2". "step 1" has a type
of "<STEP 1 TYPE>" and a timeout of 2 hours. "step2" has a type of
"<STEP 2 TYPE>" and a timeout of 10 minutes, by default.
```json
"Steps": {
  "step1": {
    "<STEP 1 TYPE>": {
      ...
    },
    "Timeout": "2h"
  },
  "step2": {
    "<STEP 2 TYPE>": {
      ...
    }
  }
}
```

#### Type: AttachDisks
Not implemented yet.

#### Type: CreateDisks
Creates GCE disks. A list of GCE Disk resources. See https://cloud.google.com/compute/docs/reference/latest/disks for
the Disk JSON representation. Daisy uses the same representation with a few modifications:

| Field Name | Type | Description of Modification |
| - | - | - |
| Name | string | If ExactName is false, the **literal** disk name will have a generated suffix for the running instance of the workflow. |
| SourceImage | string | Either image [partial URLs](#glossary-partialurl) or workflow-internal image names are valid. |
| Type | string | *Optional.* Defaults to "pd-standard". Either disk type [partial URLs](#glossary-partialurl) or disk type names are valid. |

Added fields:

| Field Name | Type | Description |
| - | - | - |
| Project | string | *Optional.* Defaults to workflow's Project. The GCP project in which to create the disk. |
| Zone | string | *Optional.* Defaults to workflow's Zone. The GCE zone in which to create the disk. |
| NoCleanup | bool | *Optional.* Defaults to false. Set this to true if you do not want Daisy to automatically delete this disk when the workflow terminates. |
| ExactName | bool | *Optional.* Defaults to false. Set this to true if you want Daisy to name this GCE disk exactly the same as Name. **Be advised**: this circumvents Daisy's efforts to prevent resource name collisions. |

Example: the first is a standard PD disk created from a source image, the second
is a blank PD SSD.
```json
"step-name": {
  "CreateDisks": [
    {
      "Name": "disk1",
      "SourceImage": "projects/debian-cloud/global/images/family/debian-8"
    },
    {
      "Name": "disk2",
      "SizeGb": "200",
      "Type": "pd-ssd"
    }
  ]
}
```

#### Type: CreateImages
Creates GCE images. A list of GCE Image resources. See https://cloud.google.com/compute/docs/reference/latest/images for
the Image JSON representation. Daisy uses the same representation with a few modifications:

| Field Name | Type | Description of Modification |
| - | - | - |
| Name | string | If ExactName is false, the **literal** image name will have a generated suffix for the running instance of the workflow. |
| RawDisk.Source | string | Either a GCS Path or a key from Sources are valid. |
| SourceDisk | string | Either disk [partial URLs](#glossary-partialurl) or workflow-internal disk names are valid. |

Added fields:

| Field Name | Type | Description |
| - | - | - |
| Project | string | *Optional.* Defaults to the workflow Project. The GCP project in which to create this image. |
| NoCleanup | bool | *Optional.* Defaults to false. Set this to true if you do not want Daisy to automatically delete this image when the workflow terminates. |
| ExactName | bool | *Optional.* Defaults to false. Set this to true if you want Daisy to name this GCE image exactly the same as Name. **Be advised**: this circumvents Daisy's efforts to prevent resource name collisions. |

This CreateImages example creates an image from a source disk.
```json
"step-name": {
  "CreateImages": [
    {
      "Name": "image1",
      "SourceDisk": "disk2"
    }
  ]
}
```

This CreateImages example creates three images. `image1` is created from
a source from the workflow's `Sources` and will not be cleaned up by
Daisy. `image2` is created from a source from a GCS Path and will use
the exact name, "image2". Lastly, `image3` is created from a disk from
the workflow and will be created in a different project from the
workflow's specified Project.
```json
"step-name": {
  "CreateImages": [
    {
      "Name": "image1",
      "RawDisk": {
        "Source": "my-source"
      },
      "NoCleanup": true
    },
    {
      "Name": "image2",
      "RawDisk": {
        "Source": "gs://my-bucket/image.tar.gz"
      },
      "ExactName": true
    },
    {
      "Name": "image3",
      "SourceDisk": "my-disk",
      "Project": "my-other-project"
    }
  ]
}
```

#### Type: CreateInstances
Creates GCE instances. A list of GCE Instance resources. See https://cloud.google.com/compute/docs/reference/latest/instances for
the Instance JSON representation. Daisy uses the same representation with a few modifications:

| Field Name | Type | Description of Modification |
| - | - | - |
| Name | string | If ExactName is false, the **literal** instance name will have a generated suffix for the running instance of the workflow. |
| Disks[].Boot | bool | *Now unused.* First disk automatically has boot = true. All others are set to false. |
| Disks[].InitializeParams.DiskType | string | *Optional.* Will prepend "projects/PROJECT/zones/ZONE/diskTypes/" as needed. This allows user to provide "pd-ssd" or "pd-standard" as the DiskType. |
| Disks[].InitializeParams.SourceImage | string | Either image [partial URLs](#glossary-partialurl) or workflow-internal image names are valid. |
| Disks[].Mode | string | *Now Optional.* Now defaults to "READ_WRITE". |
| Disks[].Source | string | Either disk [partial URLs](#glossary-partialurl) or workflow-internal disk names are valid. |
| MachineType | string | *Now Optional.* Now defaults to "n1-standard-1". Either machine type [partial URLs](#glossary-partialurl) or machine type names are valid. |
| Metadata | map[string]string | *Optional.* Instead of the GCE JSON API's more complex object structure, Daisy uses a simple key-value map. Daisy will provide metadata keys `daisy-logs-path`, `daisy-outs-path`, and `daisy-sources-path`. |
| NetworkInterfaces[] | list | *Now Optional.* Now defaults to `[{"network": "global/networks/default", "accessConfigs": [{"type": "ONE_TO_ONE_NAT"}]}`. |
| NetworkInterfaces[].Network | string | Either network [partial URLs](#glossary-partialurl) or network names are valid. |
| NetworkInterfaces[].AccessConfigs[] | list | *Now Optional.* Now defaults to `[{"type": "ONE_TO_ONE_NAT}]`. |

Added fields:

| Field Name | Type | Description |
| - | - | - |
| Scopes | list(string) | *Optional.* Defaults to `["https://www.googleapis.com/auth/devstorage.read_only"]`. Only used if serviceAccounts is not used. Sets default service account scopes by setting serviceAccounts to `[{"email": "default", "scopes": <value of Scopes>}]`.|
| StartupScript | string | *Optional.* A source file from Sources. If provided, metadata will be set for `startup-script-url` and `windows-startup-script-url`.|
| Project | string | *Optional.* Defaults to workflow's Project. The GCP project in which to create the disk. |
| Zone | string | *Optional.* Defaults to workflow's Zone. The GCE zone in which to create the disk. |
| NoCleanup | bool | *Optional.* Defaults to false. Set this to true if you do not want Daisy to automatically delete this disk when the workflow terminates. |
| ExactName | bool | *Optional.* Defaults to false. Set this to true if you want Daisy to name this GCE disk exactly the same as Name. **Be advised**: this circumvents Daisy's efforts to prevent resource name collisions. |

This CreateInstances step example creates an instance with two attached
disks, with machine type n1-standard-4, and with metadata "key" = "value".
The instance will have default scopes and will be attached to the default
network.
```json
"step-name": {
  "CreateInstances": [
    {
      "Name": "instance1",
      "Disks": [
        {"Source": "disk1"},
        {"Source": "zones/foo/disks/disk2", "Mode": "READ_ONLY"}
      ],
      "MachineType": "n1-standard-4",
      "Metadata": {"key": "value"}
    }
  ]
}
```

#### Type: CopyGCSObjects
Copies a GCS files from Source to Destination. Each copy has the following fields:

| Field Name | Type | Description |
| - | - | - |
| Source | string | Source path. |
| Destination | list(string) | Destination path. |
| ACLRules | list(ACLRule) | *Optional.* List of ACLRules to apply to the object. |

An ACLRule has two fields:

+ Entity - Refers to a user or group, see entity in https://cloud.google.com/storage/docs/json_api/v1/objectAccessControls
+ Role - Access level to grant, one of OWNER, READER, or WRITER

This CopyGCSObjects step example copies image.tar.gz from the Daisy OUTSPATH to
gs://project2/my-image.tar.gz and gives the special user "allUsers" read 
permissions.
```json
"step-name": {
  "CopyGCSObjects": [
    {
      "Source": "${OUTSPATH}/image.tar.gz",
      "Destination": "gs://project/my-image.tar.gz",
      "AclRules": [{"Entity": "allUsers", "Role": "READER"}]
    }
  ]
}
```

#### Type: DeleteResources
Deletes GCE resources (images, instances, disks). Resources are deleted in the
order: images, instances, disks.

| Field Name | Type | Description |
| - | - | - |
| Disks | list(string) | *Optional, but at least one of these fields must be used.* The list of disks to delete. Values can be 1) Names of disks created in this workflow or 2) the [partial URL](#glossary-partialurl) of an existing GCE disk. |
| Images | list(string) | *Optional, but at least one of these fields must be used.* The list of images to delete. Values can be 1) Names of images created in this workflow or 2) the [partial URL](#glossary-partialurl) of an existing GCE image. |
| Instances | list(string) | *Optional, but at least one of these fields must be used.* The list of disks to delete. Values can be 1) Names of VMs created in this workflow or 2) the [partial URL](#glossary-partialurl) of an existing GCE VM. |

This DeleteResources step example deletes an image, an instance, and two
disks.
```json
"step-name": {
  "DeleteResources": {
     "Images":["image1"],
     "Instances":["instance1"],
     "Disks":["disk1", "disk2"]
   }
}
```

#### Type: IncludeWorkflow
Includes another Daisy workflow JSON file into this workflow. The included 
workflow's steps will run as if they were part of the parent workflow, but
follow the IncludeWorkflow steps dependency map (all steps from a included 
workflow depend on steps the IncludeWorkflow depends on). 

Included workflows have access to all of their parent workflows resources and 
vice versa. For example the disk `disk1` created in a previous step will be 
available to the included workflow and the instance `instance1` created in the 
included workflow will be available to the parent. The included workflow's 
Sources are similarly merged with the parent workflow and share the same scratch 
directory. The included workflow will not have access to the parent workflows 
variables however, all variable substitutions will come from the `Var` field 
in the IncludeWorkflow step or from the included workflow's JSON file.

IncludeWorkflow step type fields:

| Field Name | Type | Description |
| - | - | - |
| Path | string | The local path to the Daisy workflow file to include. |
| Vars | map[string]string | *Optional.* Key-value pairs of variables to send to the included workflow. |

This IncludeWorkflow step example uses a local workflow file and passes a var,
"foo", to the included workflow.
```json
"step-name": {
  "IncludeWorkflow": {
    "Path": "./some_subworkflow.wf.json",
    "Vars": {
        "foo": "bar"
    }
  }
}
```

#### Type: RunTests
Not implemented yet.

#### Type: SubWorkflow
Runs a Daisy workflow as a step. The subworkflow will have some fields
overwritten. For example, the subworkflow may specify a GCP Project "foo",
but the parent workflow is working in Project "bar". The subworkflow's Project
will be overwritten so that subworkflow is also running in "bar", the same as
the parent. The fields that get modified by the parent:
* Project (copied from parent)
* Zone (copied from parent)
* GCSPath (changed to a subdirectory in parent's GCSPath)
* OAuthPath (not used, parent workflow's credentials will be used)
* Vars (Vars can be passed in via the SubWorkflow step type Vars field)

SubWorkflow step type fields:

| Field Name | Type | Description |
| - | - | - |
| Path | string | The local path to the Daisy workflow file to run as a subworkflow. |
| Vars | map[string]string | *Optional.* Key-value pairs of variables to send to the subworkflow. Analogous to calling the subworkflow via the commandline with the `-variables foo=bar,baz=gaz` flag. |

This SubWorkflow step example uses a local workflow file and passes a var,
"foo", to the subworkflow.
```json
"step-name": {
  "SubWorkflow": {
    "Path": "./some_subworkflow.wf.json",
    "Vars": {
        "foo": "bar"
    }
  }
}
```

#### Type: WaitForInstancesSignal
Waits for a signal from GCE VM instances. This step will fail if its Timeout
is reached or if a failure signal is received. The wait configuration for each
VM has the following fields:

| Field Name | Type | Description |
| - | - | - |
| Name | string | The Name or [partial URL](#glossary-partialurl) of the VM. |
| Interval | string ([Golang's time.Duration format](https://golang.org/pkg/time/#Duration.String)) | The signal polling interval. |
| Stopped | bool | Use the VM stopping as the signal. |
| SerialOutput | SerialOutput (see below) | Parse the serial port output for a signal. |

SerialOutput:

| Field Name | Type | Description |
| - | - | - |
| Port | int64 | The serial port number to listen to. GCE VMs have serial ports 1-4. |
| FailureMatch | string | *Optional, but this or SuccessMatch must be provided.* An expected string in case of a failure. |
| SuccessMatch | string | *Optional, but this or FailureMatch must be provided.* An expected string when the VM performed its task successfully. |

This example step waits for VM "foo" to stop and for a signal from VM "bar":
```json
"step-name": {
    "WaitForInstancesSignal": [
        {
            "Name": "foo",
            "Stopped": true
        },
        {
            "Name": "bar",
            "SerialOutput": {
                "Port": 1,
                "SuccessMatch": "this means I'm done! :)",
                "FailureMatch": "this means I failed... :("
            }
        }
    ]
}
```

### Dependencies

The Dependencies map describes the order in which workflow steps will run.
Steps without any dependencies will run immediately, otherwise a step will
only run once its dependencies have completed successfully.

In this example, step1 will run immediately as it has no dependencies, step2
and step3 will run after step1 completes, and step4 will run after step2 and
step3 complete.
```json
{
  "Steps": {
    "step1": {
      ...
    },
    "step2": {
      ...
    },
    "step3": {
      ...
    },
    "step4": {
      ...
    }
  },
  "Dependencies": {
    "step2": ["step1"],
    "step3": ["step1"],
    "step4": ["step2", "step3"]
  }
}
```

### Vars
Vars are a user-provided set of key-value pairs. Vars are used in string
substitutions in the rest of the workflow config using the syntax `${key}`.
Vars can be hardcoded into the workflow config or passed via the commandline.
Vars passed via the commandline will override the hardcoded Vars.

Vars can be either a simple key:value pairing or with the following fields:
+ Value: (string) value of the variable
+ Description: (string) description of the variable
+ Required: (bool) whether this variable is required to be non empty

In this example `var1` is an optional variable with an empty string as the 
default value, `var2` is an example of an optional variable with a default 
value provided, `var3` is a required variable with no default value. If `var3`
is not set or is set as an empty string the workflow will fail with an error.
```json
{
  "Zone": "${var2}",
  "Vars": {
    "var1": "",
    "var2": {"Value": "foo-zone", "Description": "default zone to run the workflow in"},
    "var3": {"Required": true, "Description": "variable 3"}
  }
}
```
When run, Name will be set to "foo-name" and Zone will be set to "foo-zone".
But, if the user calls Daisy with `daisy wf.json -variables var1=bar-name`,
then Name will be set to "bar-name" and not "foo-name".

#### Autovars
Autovars are used the same as Vars, but are automatically populated by Daisy
out of convenience. Here is the exhaustive list of autovars:

| Autovar key | Description |
| - | - |
| ID | The autogenerated random ID for the current workflow run. |
| NAME | The workflow's Name field. |
| PROJECT | The workflow's Project field. |
| ZONE | The workflow's Zone field. |
| DATE | The date of the current workflow run in YYYYMMDD. |
| DATETIME | The date and time of the current workflow run in YYYYMMDDhhmmss. |
| TIMESTAMP | The Unix epoch of the current workflow run. |
| WFDIR | The directory of the workflow file being run. |
| CWD | The current working directory. |
| GCSPATH | The workflow's GCSPath field. |
| SCRATCHPATH | The scratch subdirectory of GCSPath that the running workflow instance uses. |
| SOURCESPATH | Equivalent to ${SCRATCHPATH}/sources. |
| LOGSPATH | Equivalent to ${SCRATCHPATH}/logs. |
| OUTSPATH | Equivalent to ${SCRATCHPATH}/outs. |
| USERNAME | Username of the user running the workflow. |

## Glossary of Terms
Definitions:
* <a id="glossary-gce"></a>GCE: Google Compute Engine
* <a id="glossary-gcp"></a>GCP: Google Cloud Platform
* <a id="glossary-gcs"></a>GCS: Google Cloud Storage
* <a id="glossary-partialurl"></a>Partial URL: a URL for a GCE resource. Has the
form of "projects/PROJECT/zone/ZONE/RESOURCETYPE/RESOURCENAME"
* <a id="glossary-workflow"></a>Workflow: a graph of executable, blocking steps and their dependency relationships.
