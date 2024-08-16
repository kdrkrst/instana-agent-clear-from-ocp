# Clear Leftovers from Instana Agent & Autotrace Webhook Uninstallation
This script scans OpenShift projects and pods to identify resources associated with **Instana**, including labels, annotations, and init container images. It can optionally output the results to a CSV file and supports `dry-run` mode to preview changes without making modifications.

## Prerequisites
* You must have the `oc` command-line tool installed and be logged into your OpenShift cluster.
* `jq` must be installed to handle JSON parsing.

## Usage
```bash
./instana-ocp-agent-clear-from-projects.sh
```

### Options
* `--dry-run`: Runs the script without making any changes, displaying the actions that would be taken.
* `--output-file=<file>`: Writes the foundings to the specified file in CSV format.
* `--no-confirm`: By default script is asking for confirmation before each modification on the resources, if it is not started using `--dry-run`. You can tell script to skip prompting confirmation.

## What Script Does
* **Project Label** & Annotation Scan: Scans all non-system projects for labels and annotations containing the word "instana".
* **Pod Label Scan**: Scans all pods for labels containing the word "instana", including their owner references (e.g., Deployments, DaemonSets, StatefulSets, Jobs, CronJobs).
* **Pod Init Container Scan**: Checks all pods for init containers with images containing "instana".
* **Output**: Prints the results to the console and optionally writes them to a CSV file with the following columns:  
  Project  
  Owner Kind  
  Owner Name  
  Pod  
  Label/InitContainerImage  

## Notes
The script skips projects and namespaces starting with `openshift-`.
