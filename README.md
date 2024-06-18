# Kubernetes in a Box

Turn key Terraform repo to build a greenfield k8s cluster on Equinix Metal.  

This will deploy a master_node, plus n (min 3) worker nodes.  Networking is delivered via Calico and storage leveraging Portworx CSI.  This does require a portworx account but one can be created for free: *insert link*

For the Calico networking, the default network of 192.168.0.0/16 will be used.  If you want to change this, you should update the ./locals/kubelet.tftpl and well as the calico Yaml file.  The latter is out of scope of this repository as the control script automatically applies the default Calico configuration.


The output of this build is a kubeconfig file.  You can either SSH to the master node of the cluster and run commands locally, or merge this file with a local context and use that:

```console
KUBECONFIG=~/.kube/config:/path/to/your/kube_config kubectl config view --merge --flatten > ~/.kube/config
```
```console

```

The endpoint for this cluster, master.k8s.dev, is not publicly registered.  You should add an entry for this in your local hosts file / DNS.  
The master and worker IPs and Hostnames can be found in ./locals/hosts after a successful build