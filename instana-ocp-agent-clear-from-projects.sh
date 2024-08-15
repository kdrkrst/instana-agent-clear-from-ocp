#!/bin/bash

# Check for --dry-run and --output-file arguments
dry_run=false
output_file=""
search_keyword="instana"

for arg in "$@"; do
    case $arg in
        --dry-run)
            dry_run=true
            ;;
        --output-file=*)
            output_file="${arg#*=}"
            ;;
    esac
done

echo ""

if [[ $dry_run == false ]]; then
    # Print warning if not in dry-run mode
    echo -e "Warning: Execution is going to modify the resources in your OCP environment. If you want to list what resources are going to change, you can consider running the script using --dry-run!"
else
    # In dry-run mode, print a dry-run message
    echo "Dry-run is started. This execution is not going to change resources in your OCP environment."
fi

if [[ -n $output_file ]]; then

    # Write that we are going to use a file
    echo "Found labels, annotations and init-containers will be written to the $output_file"

    # Write the title line to the output file
    echo "FoundTrace,Project,OwnerKind,OwnerName,Pod,Label/Annotation/InitContainerImage" > "$output_file"
fi

echo ""

# Print message
echo "Scanning Projects for Labels & Annotations containing $search_keyword"

# Iterate through all projects
for project in $(oc get projects -o jsonpath='{.items[*].metadata.name}'); do
    # Skip projects starting with "openshift-"
    if [[ $project != openshift* ]]; then
        # Get project labels
        labels=$(oc get project "$project" -o jsonpath='{.metadata.labels}' | jq -r 'to_entries[] | "\(.key):\(.value)"')

        # Check for labels containing "$search_keyword"
        while IFS= read -r label; do
            if [[ $label == *$search_keyword* ]]; then
                if [[ -n $output_file ]]; then
                    # Write to output file in comma-separated format
                    echo "LABEL,$project,-,-,-,$label" >> "$output_file"
                fi

                if [[ $dry_run == false ]]; then
                    # Print project name and label in tab-separated format
                    echo -e "Label found:\t\t$project\t$label"

                    echo -e "Label removed:\t\t$project\t$label"
                else
                    echo -e "\tDry-run: $project\t$label"
                fi
                break  # Break if we found a matching label
            fi
        done <<< "$labels"  # Process labels as newline-separated format

        # Get project annotations
        annotations=$(oc get project "$project" -o jsonpath='{.metadata.annotations}' | jq -r 'to_entries[] | "\(.key):\(.value)"')

        # Check for annotations containing "$search_keyword"
        while IFS= read -r annotation; do
            if [[ $annotation == *$search_keyword* ]]; then
                if [[ -n $output_file ]]; then
                    # Write to output file in comma-separated format
                    echo "ANNOTATION,$project,-,-,-,$annotation" >> "$output_file"
                fi

                if [[ $dry_run == false ]]; then
                    # Print project name and annotation in tab-separated format
                    echo -e "Annotation found:\t$project\t$annotation"

                    echo -e "Annotation removed:\t$project\t$annotation"
                else
                    echo -e "\tDry-run: $project\t$annotation"
                fi
                break  # Break if we found a matching annotation
            fi
        done <<< "$annotations"  # Process annotations as newline-separated format
    fi
done

echo ""

# Print message
echo "Scanning Pods for Labels & Annotations containing $search_keyword"

# Iterate through all projects
for project in $(oc get projects -o jsonpath='{.items[*].metadata.name}'); do
    
    # Skip namespaces starting with "openshift-"
    if [[ $project != openshift* ]]; then

        # Get pods with labels containing "instana"
        pods=$(oc get pods -n "$project" -o jsonpath='{.items[*].metadata.name}' --no-headers)
        
        for pod in $pods; do
            # Get pod labels
            labels=$(oc get pod "$pod" -n "$project" -o jsonpath='{.metadata.labels}' 2>/dev/null | jq -r 'to_entries[] | "\(.key):\(.value)"')

            # Check for labels containing "instana"
            while IFS= read -r label; do

                if [[ $label == *instana* ]]; then

                    # Try to find the kind and name of the owner from ownerReference
                    read -r ownerReferenceKind ownerReferenceName < <(
                        oc get pod $pod -n $project -o jsonpath='{range .metadata.ownerReferences[*]}{.kind} {.name}{"\n"}{end}' | 
awk '$1 == "DaemonSet" || $1 == "ReplicaSet" || $1 == "StatefulSet" || $1 == "Job" || $1 == "CronJob" {print $1, $2; exit}'

                    )

                    remove_from_the_owner=false

                    # If no ownerReference is found, set default values
                    if [[ -z $ownerReferenceKind ]]; then
                        ownerReferenceKind="-"
                        ownerReferenceName="-"
                    elif [ "$ownerReferenceKind" == "ReplicaSet" ]; then
                        # Check if the owner reference is a ReplicaSet and get the Deployment name
                        ownerReferenceName=$(oc get rs "$ownerReferenceName" -n "$project" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}')
                        ownerReferenceKind="Deployment"
                        remove_from_the_owner=true
                    elif [ "$ownerReferenceKind" == "Job" ]; then
                        # Check if the owner reference is a Job and get the CronJob name if it exists
                        cronJobName=$(oc get job "$ownerReferenceName" -n "$project" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="CronJob")].name}')

                        if [[ -n "$cronJobName" ]]; then
                            ownerReferenceName="$cronJobName"
                            ownerReferenceKind="CronJob"
                        fi

                        remove_from_the_owner=true
                    fi

                    if [[ -n $output_file ]]; then
                        # Write to output file in comma-separated format
                        echo "LABEL,$project,$ownerReferenceKind,$ownerReferenceName,$pod,$label" >> "$output_file"
                    fi

                    if [[ $dry_run == false ]]; then
                        # Print project name, owner kind, owner name, pod name, and label in tab-separated format
                        echo -e "Label found:\t\t$project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$label"

                        # extract label key and label value
                        IFS=":" read -r label_key label_value <<< "$label"

                        oc patch pod $pod -n $project --type=json -p='[
                            {"op": "remove", "path": "/metadata/labels/'$label_key'"}
                        ]'

                        # if we detect an owner, remove the labels from there too
                        if [[ $remove_from_the_owner == true ]]; then
                            oc patch $ownerReferenceKind $ownerReferenceName -n $project --type=json -p='[
                                {"op": "remove", "path": "/spec/template/metadata/labels/'$label_key'"}
                            ]'
                        fi

                        echo -e "Label removed:\t\t$project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$label"
                    else
                        echo -e "\tDry-Run: $project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$label"
                    fi
                fi
            done <<< "$labels"  # Process labels as newline-separated format

            # Get pod annotations
            annotations=$(oc get pod "$pod" -n "$project" -o jsonpath='{.metadata.annotations}' 2>/dev/null | jq -r 'to_entries[] | "\(.key):\(.value)"')

            # Check for annotations containing "$search_keyword"
            while IFS= read -r annotation; do

                if [[ $annotation == *$search_keyword* ]]; then

                    # Try to find the kind and name of the owner from ownerReference
                    read -r ownerReferenceKind ownerReferenceName < <(
                        oc get pod $pod -n $project -o jsonpath='{range .metadata.ownerReferences[*]}{.kind} {.name}{"\n"}{end}' | 
awk '$1 == "DaemonSet" || $1 == "ReplicaSet" || $1 == "StatefulSet" || $1 == "Job" || $1 == "CronJob" {print $1, $2; exit}'

                    )

                    # If no ownerReference is found, set default values
                    if [[ -z $ownerReferenceKind ]]; then
                        ownerReferenceKind="-"
                        ownerReferenceName="-"
                    elif [ "$ownerReferenceKind" == "ReplicaSet" ]; then
                        # Check if the owner reference is a ReplicaSet and get the Deployment name
                        ownerReferenceName=$(oc get rs "$ownerReferenceName" -n "$project" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}')
                        ownerReferenceKind="Deployment"
                    elif [ "$ownerReferenceKind" == "Job" ]; then
                        # Check if the owner reference is a Job and get the CronJob name if it exists
                        cronJobName=$(oc get job "$ownerReferenceName" -n "$project" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="CronJob")].name}')
                        
                        if [[ -n "$cronJobName" ]]; then
                            ownerReferenceName="$cronJobName"
                            ownerReferenceKind="CronJob"
                        fi
                    fi

                    if [[ -n $output_file ]]; then
                        # Write to output file in comma-separated format
                        echo "ANNOTATION,$project,$ownerReferenceKind,$ownerReferenceName,$pod,$annotation" >> "$output_file"
                    fi

                    if [[ $dry_run == false ]]; then
                        # Print project name, owner kind, owner name, pod name, and annotation in tab-separated format
                        echo -e "Annotation found:\t$project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$annotation"

                        echo -e "Annotation removed:\t$project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$annotation"
                    else
                        echo -e "\tDry-Run: $project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$annotation"
                    fi
                fi
            done <<< "$annotations"  # Process annotations as newline-separated format
        done
    fi
done

echo ""
echo "Scanning Pods for Init Containers with '$search_keyword' in Image Name"

# Iterate through all projects
for project in $(oc get projects -o jsonpath='{.items[*].metadata.name}'); do
    
    # Skip namespaces starting with "openshift-"
    if [[ $project != openshift* ]]; then

        # Get pods in the project
        pods=$(oc get pods -n "$project" -o jsonpath='{.items[*].metadata.name}' --no-headers)
        
        for pod in $pods; do
            # Get init container images
            init_images=$(oc get pod "$pod" -n "$project" -o jsonpath='{range .spec.initContainers[*]}{.image}{"\n"}{end}')

            # Check for init container images containing "$search_keyword"
            while IFS= read -r image; do

                if [[ $image == *$search_keyword* ]]; then

                    # Try to find the kind and name of the owner from ownerReference
                    read -r ownerReferenceKind ownerReferenceName < <(
                        oc get pod $pod -n $project -o jsonpath='{range .metadata.ownerReferences[*]}{.kind} {.name}{"\n"}{end}' | 
awk '$1 == "DaemonSet" || $1 == "ReplicaSet" || $1 == "StatefulSet" || $1 == "Job" || $1 == "CronJob" {print $1, $2; exit}'

                    )

                    # If no ownerReference is found, set default values
                    if [[ -z $ownerReferenceKind ]]; then
                        ownerReferenceKind="-"
                        ownerReferenceName="-"
                    elif [ "$ownerReferenceKind" == "ReplicaSet" ]; then
                        # Check if the owner reference is a ReplicaSet and get the Deployment name
                        ownerReferenceName=$(oc get rs "$ownerReferenceName" -n "$project" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}')
                        ownerReferenceKind="Deployment"
                    elif [ "$ownerReferenceKind" == "Job" ]; then
                        # Check if the owner reference is a Job and get the CronJob name if it exists
                        cronJobName=$(oc get job "$ownerReferenceName" -n "$project" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="CronJob")].name}')
                        
                        if [[ -n "$cronJobName" ]]; then
                            ownerReferenceName="$cronJobName"
                            ownerReferenceKind="CronJob"
                        fi
                    fi

                    if [[ -n $output_file ]]; then
                        # Write to output file in comma-separated format
                        echo "INIT-CONTAINER,$project,$ownerReferenceKind,$ownerReferenceName,$pod,$image" >> "$output_file"
                    fi

                    if [[ $dry_run == false ]]; then
                        # Print project name, owner kind, owner name, pod name, and init container image in tab-separated format
                        echo -e "Init-container found:\t$project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$image"

                        echo -e "Init-container removed:\t$project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$image"
                    else
                        echo -e "\tDry-Run: $project\t$ownerReferenceKind\t$ownerReferenceName\t$pod\t$image"
                    fi
                fi
            done <<< "$init_images"  # Process init container images as newline-separated format
        done
    fi
done


# Print a final message if output_file was used
if [[ -n $output_file ]]; then
    echo "Results have been written to $output_file."
fi
