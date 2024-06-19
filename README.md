# Kubernetes in a Box

Turn key Terraform repo to build a greenfield k8s cluster on Equinix Metal.  

This will deploy a master node, plus n (min 3) worker nodes.  Networking is delivered via Calico.

## Using this repo

The cluster construction is contolled by a shell script ```console k8s_env.sh```.  Once this repo is cloned, make sure you add executable permissions to the file
```console
chmod + x ./k8s_env.sh
```

For the rest of this documentation, this file will be referred to as the control script.

## Understanding the control script

The control script allows for the build (and destruction) of a kubernetes environment on Equinix Metal.  It does this with a combination of Terraform, to build the infrastructures, and then some local controls and files that complete the configuration of the cluster itself.

### Setting up variables

The control script is responsible for building the infrastructure as well as configuring the cluster, in combination with a cloud-init file stored here: 
The cluster build only requires two main inputs:
1. Equinix Metal API key
2. Equinix Metal Org ID

These can be set as command line flags, or environment variables.  A future consideration will also be to check for a local *.tfvars files and extract them from there to create a "native" Terraform variable handler as well.

### Setting with command line

To setup the variables with the command line, the auth_token and org_id flags can be set

```console
./k8s_env build --auth_token "XXXXXX" --org_id "XXXXXXX"
```


For the Calico networking, the default network of 192.168.0.0/16 will be used.  If you want to change this, you should update the ./locals/kubelet.tftpl and well as the calico Yaml file.  The latter is out of scope of this repository as the control script automatically applies the default Calico configuration.


The output of this build is a kubeconfig file.  You can either SSH to the master node of the cluster and run commands locally, or merge this file with a local context and use that:

```console
KUBECONFIG=~/.kube/config:/path/to/your/kube_config kubectl config view --merge --flatten > ~/.kube/config
```
```console

```

The endpoint for this cluster, master.k8s.dev, is not publicly registered.  You should add an entry for this in your local hosts file / DNS.  
The master and worker IPs and Hostnames can be found in ./locals/hosts after a successful build
