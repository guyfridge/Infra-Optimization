# Infra-Optimization
Create a DevOps infrastructure for an e-commerce application to run on high-availability mode.
## Steps to be Taken
1. Manually create a controller VM on Google Cloud and install Terraform and Kubernetes
2. On the controller VM, use Terraform to automate the provisioning of a GKE cluster with Docker installed
3. Create a new user with permissions to create, list, get, update, and delete pods
4. Configure application on the pod
5. Take snapshot of ETCD database
6. Set criteria such that if the memory of CPU goes beyond 50%, environments automatically get scaled up and configured

## Manually create a controller VM on Google Cloud and install Terraform, Docker, and Kubernetes on it
Inside Google Cloud, create an e2-medium machine with the following:
1. Ubuntu OS 
2. 10GB storage 
3. enable HTTP / HTTPS traffic
4. Allow full access to all Cloud APIs

### Update the VM
```
sudo apt-get update
sudo apt-get upgrade
```
### Install Docker
1. Download the executable from the repository 
`sudo wget https://raw.githubusercontent.com/lerndevops/labs/master/scripts/installDocker.sh -P /tmp`
2. Change the permissions on the executable
`sudo chmod 755 /tmp/installDocker.sh`
3. Execute the file
`sudo bash /tmp/installDocker.sh`
4. Restart the docker service
`sudo systemctl restart docker.service`

### Install CRI-Docker
1. Download the executable from the repository
`sudo wget https://raw.githubusercontent.com/lerndevops/labs/master/scripts/installCRIDockerd.sh -P /tmp`
2. Change the executable's permissions
`sudo chmod 755 /tmp/installCRIDockerd.sh`
3. Execute the file
`sudo bash /tmp/installCRIDockerd.sh`
4. Restart the service
`sudo systemctl restart cri-docker.service`

### Install Kubernetes with Kubectl, Kubeadm, Kubelet
1. Download the executable from this repo
`sudo wget https://raw.githubusercontent.com/lerndevops/labs/master/scripts/installK8S.sh -P /tmp`
2. Change the permissions on the executable
`sudo chmod 755 /tmp/installK8S.sh`
3. Execute the file to install Kubernetes
`sudo bash /tmp/installK8S.sh`
4. Initialize Kubernetes master node
`sudo kubeadm init --cri-socket unix:///var/run/cri-dockerd.sock --ignore-preflight-errors=all`
5. To start using your cluster, run the following as a regular user:
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Verify installation of Docker and Kubernetes
```
docker -v
cri-dockerd --version
kubeadm version -o short
kubelet --version
kubectl version --short --client
```
### Install Terraform and Verify
```
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update

sudo apt-get install terraform

terraform -help
```
### Install gcloud CLI and connect to your gcloud account
1. download the Linux 64-bit archive file
`curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-433.0.0-linux-x86_64.tar.gz`
2. Extract the tar file
`tar -xf google-cloud-cli-433.0.0-linux-x86_64.tar.gz`
3. Add the gcloud SDK to your path and run the installation
`./google-cloud-sdk/install.sh`
4. Restart SSH connection to controller VM for changes to take place
5. Initialize gcloud CLI
`./google-cloud-sdk/bin/gcloud init`
6. Verify the installation
`gcloud --version`
7. Enter your account credentials (Unnecessary)
`gcloud auth application-default login`

## On the controller VM, use Terraform to automate the provisioning of a Kubernetes cluster with Docker installed
### Set up and initialize the Terraform workspace
1. Clone the following respository on the controller VM
```
git clone https://github.com/hashicorp/learn-terraform-provision-gke-cluster
```
2. Change to the newly created directory 
`cd learn-terraform-provision-gke-cluster`
3. Edit the terraform.tfvars file with your Google Cloud project_id and region value
```
# terraform.tfvars
project_id = "sl-capstone-project"
region     = "us-west1"
```
4. Edit the gke.tf file and add your gke cluster username where prompted.
```
# gke.tf
variable "gke_username" {
  default     = "guyfridge"
  description = "gke username"
}
```
5. Edit the gke.tf file and add the following inside the google_container_cluster resource.
```
# GKE cluster
resource "google_container_cluster" "primary" {
  ...
  timeouts {
    create = "60m"
  }
}
```
6.  Ensure that Compute Engine API and Kubernetes Engine API are enabled on your Google Cloud project. Also ensure a minimum of 1000Mb available space in your designated region for provisioning a six node cluster.
```
terraform init
terraform plan
terraform apply
```
### Retrieve the access credentials for your gke cluster
1. Install gke-gcloud-auth-plugin to configure your gke cluster with kubectl from the controller vm
`gcloud components install gke-gcloud-auth-plugin`
8. Connect to your GKE cluster from the master
`gcloud container clusters get-credentials <your-project-name>-gke --region <region> --project <your-project-name>`
9. Verify master-gke cluster connectivity
`kubectl get nodes -o wide`

## Create a new user with permissions to create, list, get, update, and delete pods
1. Create a ClusterRole with permissions to create, list, get, update, and delete pods across all namespaces
`sudo vi pod-management-clusterRole.yaml`
```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-management-clusterrole
rules:
- apiGroups: ["*"]
  resources: ["pods","deployments", "replicasets", "services"]
  verbs: ["get", "list", "delete", "create", "update"]
```
2. Create a ClusterRoleBinding to Assign the ClusterRole to a specific user
`sudo vi pod-management-clusterRoleBinding.yaml`
```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pod-management-clusterrolebinding
subjects:
- kind: User
  name: user1 # name of your service account
roleRef: # referring to your ClusterRole
  kind: ClusterRole
  name: pod-management
  apiGroup: rbac.authorization.k8s.io
```
3. Create a directory for storing the user1 cert
```
sudo mkdir -p /home/certs
cd /home/certs
```
4. Comment out `RANDFILE = $ENV::HOME/.rnd` in openssl config file `/etc/ssl/openssl.cnf`
5. Create a private key for your user
`sudo openssl genrsa -out user1.key 2048`
6. Create a certificate sign request, user1.csr, using the private key we just created 
`sudo openssl req -new -key user1.key -out user1.csr`
7. Generate user1.crt by approving the user1.csr we made earlier
`sudo openssl x509 -req -in user1.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out user1.crt -days 1000 ; ls -ltr`
### Create kubeconfig file
1. Add cluster details to config file
`sudo kubectl config --kubeconfig=user1.conf set-cluster production --server=https://10.138.0.6:6443 --certificate-authority=/etc/kubernetes/pki/ca.crt`
2. Add user details to config file
`sudo kubectl config --kubeconfig=user1.conf set-credentials user1 --client-certificate=/home/user1/certs/user1.crt --client-key=/home/user1/certs/user1.key`
3. Add context details to config file
`sudo kubectl config --kubeconfig=user1.conf set-context prod --cluster=production --namespace=prod --user=user1`
4. Set prod context for use
`sudo kubectl config --kubeconfig=user1.conf use-context prod` 
5. Validate API access
`sudo kubectl --kubeconfig user1.conf version --short`

## Resources
1. https://github.com/lerndevops/educka/blob/3b04283dc177204ec2dc99dd58617cee2d533cf7/1-intall/install-kubernetes-with-docker-virtualbox-vm-ubuntu.md
2. https://cloud.google.com/kubernetes-engine/docs/tutorials/hello-app
3. https://developer.hashicorp.com/terraform/tutorials/kubernetes/gke
4. 
