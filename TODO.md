# talos gitops TODOs

## the workflow from end to end should be

- new-site.sh
- new-cluster(s)
- prepare-omni-iso.sh (one for each verion required by clusters)
- update-tfvars.sh
- provision-nodes.sh
- apply-clusters.sh to trigger machine registration (verifies or adds new machine classes with filters for site, plaform, and size_class)
- monitor omni and wait for machines to register and join the cluster
- verify kubernetes is up and download the kubeconfig-{site}
[x] update documentation to reflect the workflow more concisely.  Rename complete-workflow.md to just workflow.md

[x] prepare-omni-iso.sh should not mofify the tfvars files, only create the iso images
[x] update-tfvars.sh should add the versioned iso image urls to the tfvars files for each site.  
[x] Each cluster can use a different talos_version but all nodes in a cluster must use the same talos_version.

[] update-gitops-repo.sh to add new clusters to the gitops repo
[] trigger gitops sync to deploy workloads to new clusters
[] verify workloads are deployed

[x] remove extra tfvars files that don't conform to the per site strategy.
[x] update documentation to reflect the per site tfvars strategy.