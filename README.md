# Infra-Optimization
Create a DevOps infrastructure for an e-commerce application to run on high-availability mode.
## Steps to be Taken
1. Manually create a controller VM on Google Cloud and install Terraform and Kubernetes
2. On the controller VM, use Terraform to automate the provisioning of a GKE cluster with Docker installed
3. Create a new user with permissions to create, list, get, update, and delete pods
4. Configure application on the pod
5. Install Backup for GKE and plan a set of backups
6. Set criteria such that if the CPU exceeds 50%, environments automatically get scaled up and configured

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
### Install gcloud CLI
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
### Retrieve the access credentials for your gke cluster
Typically with GKE, all of the nodes in the cluster are worker nodes and the master node is hidden and managed for you by Google. Instead, you interface with your cluster via Cloud Shell which acts as a kind of control plane. This step will allow us to use our e2-medium machine to control and manage the GKE cluster we will be provisioning in the next steps. 
1. Install gke-gcloud-auth-plugin to configure your gke cluster with kubectl from the controller vm
`gcloud components install gke-gcloud-auth-plugin`
8. Connect to your GKE cluster from the master
`gcloud container clusters get-credentials <your-project-name>-gke --region <region> --project <your-project-name>`
9. Verify master-gke cluster connectivity. You will not be able to see any nodes yet as we will create the cluster in the next section using Terraform.
`kubectl get nodes`

## On the controller VM, use Terraform to automate the provisioning of a GKE cluster with Docker installed
### Set up and initialize the Terraform workspace
1. Clone the following respository on the controller VM
```
git clone https://github.com/hashicorp/learn-terraform-provision-gke-cluster
```
2. Change to the newly created directory 
`cd learn-terraform-provision-gke-cluster`
3. Edit the terraform.tfvars file with your Google Cloud project_id and region value. This file specifies the Google Cloud Project where the resources will be deployed and also determines what region the VMs/nodes in the cluster will be using.
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
5. Edit the gke.tf file and add the following inside the google_container_cluster resource. This ensures that Terraform will allow the cluster creation process to continue uninterrupted for 60 minutes. The process is unlikely to require this much time.
```
# GKE cluster
resource "google_container_cluster" "primary" {
  ...
  timeouts {
    create = "60m"
  }
}
```
6.  Ensure that Compute Engine API and Kubernetes Engine API are enabled on your Google Cloud project. Additionally, ensure a minimum of 700Gb available space in your designated region for provisioning a six node cluster. 
```
terraform init
terraform plan
terraform apply
```
## Create a new user with permissions to create, list, get, update, and delete pods
1. Go to your google cloud account 
2. navigate to you project
3. Click 'IAM Admin' from main menu
4. Click the user associated with your master VM
5. Click 'Edit principal'
6. Change role to 'Kubernetes Engine Admin'
7. Click save
8. Go back to your VM. Create a ClusterRole YAML file that grants permissions to create, list, get, update, and delete pods across all namespaces
`vi pod-management-clusterRole.yaml`
```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-management-clusterrole
rules:
- apiGroups: ["*"]
  resources: ["pods", "deployments", "nodes", "replicasets", "services"]
  verbs: ["get", "list", "delete", "create", "update"]
```
9. Create a ClusterRoleBinding YAML file to assign the ClusterRole to a specific user
`vi pod-management-clusterRoleBinding.yaml`
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
  name: pod-management-clusterrole
  apiGroup: rbac.authorization.k8s.io
```
10. Create the ClusterRole using the YAML file we wrote
`kubectl create -f pod-management-clusterRole.yaml`
11. Create the ClusterRoleBinding using the YAML we wrote
`kubectl create -f pod-management-clusterRoleBinding.yaml`
12. Verify the user's permissions. You should be able to see all six nodes in the cluster after entering the following.
`kubectl get nodes --as=user1`

## Configure an application on the pod
We will deploy a simple web server containerized application to our GKE cluster.
1. Build a deployment on the cluster by pulling a docker image for a containerized web server application
```
kubectl create deployment hello-server \
>     --image=us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
```
2. Verify the successful creation of the deployment
```
kubectl get deployment
kubectl get pods
```
3. Expose the application to the internet by creating a LoadBalancer service that directs external traffic to a given port on the application
`kubectl expose deployment hello-server --type LoadBalancer --port 80 --target-port 8080`
4. Verify the successful creation of the service
`kubectl get service hello-server`
5. Obtain external IP of the 'hello-server' service from the above command and use with the exposed port to view the web application from the browswer
`https://<external-IP>:port#`

## Install Backup for GKE and plan a set of backups
GKE uses 'Backup for GKE' to backup and restore workloads in clusters.
1. Launch the cloud shell from inside your google cloud project. Enable the Backup for GKE API by entering the following:
`gcloud services enable gkebackup.googleapis.com`
2. Install Backup for GKE on your existing cluster
```
gcloud container clusters update sl-capstone-project-gke \
   --project=sl-capstone-project  \
   --region=us-central1 \
   --update-addons=BackupRestore=ENABLED
```
3. Verify installation of Backup for GKE
```
gcloud container clusters describe sl-capstone-project-gke \
    --project=sl-capstone-project  \
    --region=us-central1
```
The output should include:
```
addonsConfig:
  gkeBackupAgentConfig:
    enabled: true
 ```
4. Create a backup plan to initiate a backup of the cluster
```
gcloud beta container backup-restore backup-plans create first-backup \
    --project=sl-capstone-project \
    --location=us-central1 \
    --cluster=projects/sl-capstone-project/locations/us-central1/clusters/sl-capstone-project-gke \
    --all-namespaces \
    --include-secrets \
    --include-volume-data \
```
hit 'enter'

## Set criteria such that if the CPU exceeds 50%, environments automatically get scaled up and configured
1. Create a HorizontalPodAutoscaler object that targets the CPU utilization of the 'hello-server' deployment such that when CPU exceeds 50%, a minimum of one and a maximum of ten replicas are deployed
`kubectl autoscale deployment hello-server --cpu-percent=50 --min=1 --max=10` 

## Resources
1. https://github.com/lerndevops/educka/blob/3b04283dc177204ec2dc99dd58617cee2d533cf7/1-intall/install-kubernetes-with-docker-virtualbox-vm-ubuntu.md
2. https://cloud.google.com/kubernetes-engine/docs/tutorials/hello-app
3. https://developer.hashicorp.com/terraform/tutorials/kubernetes/gke
4. https://cloud.google.com/kubernetes-engine/docs/deploy-app-cluster
5. https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/how-to/install#enable_the_api
6. https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/how-to/backup-plan#create
7. https://cloud.google.com/kubernetes-engine/docs/how-to/horizontal-pod-autoscaling#kubectl-autoscale

