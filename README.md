# Infra-Optimization
Create a DevOps infrastructure for an e-commerce application to run on high-availability mode.
## Steps to be Taken
1. Manually create a controller VM on Google Cloud and install Ansible, Docker, and Kubernetes on it
2. On the controller VM, use Ansible to automate the provisioning of a Kubernetes cluster with Docker
3. Create a new user with permissions to create, list, get, update, and delete pods
4. Configure application on the pod
5. Take snapshot of ETCD database
6. Set criteria such that if the memory of CPU goes beyond 50%, environments automatically get scaled up and configured

## Manually create a controller VM on Google Cloud and install Terraform, Ansible, Docker, and Kubernetes on it
Inside Google Cloud, create an e2-medium machine with the following:
1. Ubuntu OS 
2. 10GB storage 
3. enable HTTP / HTTPS traffic

### Update the VM
```
sudo apt-get update
sudo apt-get upgrade
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
## On the controller VM, use Terraform to automate the provisioning of a Kubernetes cluster with Docker installed
### Set up and initialize the Terraform workspace
Clone the following respository on the controller VM
```
git clone https://github.com/hashicorp/learn-terraform-provision-gke-cluster
```
Change to the newly created directory
```
cd learn-terraform-provision-gke-cluster
```
Edit the terraform.tfvars file with your Google Cloud project_id and region value
```
# terraform.tfvars
project_id = "sl-capstone-project"
region     = "us-west1"
```
Edit the gke.tf file and add your gke cluster username where prompted. Change the number of VMs to reflect the initial desired cluster size (3).
```
variable "gke_username" {
  default     = "guyfridge"
  description = "gke username"
}
variable "gke_num_nodes" {
  default     = 3
  description = "number of gke nodes"
}
```
Ensure that Compute Engine API and Kubernetes Engine API are enabled on your Google Cloud project. Also ensure a minimum of 1000Gb available space in your designated region for provisioning a three node cluster. 

### Install Ansible and Verify
```
sudo apt-add-repository ppa:ansible/ansible
sudo apt install ansible
ansible --version
```
### Edit the Config File
```
sudo vi /etc/ansible/ansible.cfg
```
Uncomment the following lines
```
inventory = /etc/ansible/hosts
host_key_checking = False
```
### Create Ansible role to configure Master node and worker node
Create workspace
```
mkdir infra_optimization
cd infra_optimization
```
Create Ansible master role
```
ansible-galaxy init master
```
### Write tasks in the main.yaml
```
sudo vi master/tasks/main.yml
```
```
---
# tasks file for master

- name: Add repository for kubeadm
  yum_repository:
    name: Kubernetes
    description: YUM repo for kubeadm 
    baseurl: https://packages.cloud.google.com/yum/repos/kubernetes-el7-$basearch
    enabled: yes
    gpgcheck: no
           
- name: Add repository for docker
  yum_repository:
    name: docker-repo
    description: repo for docker
    baseurl: https://download.docker.com/linux/centos/7/x86_64/stable/
    enabled: yes
    gpgcheck: no

- name: Installing the docker software for k8s Cluster
  command: yum install docker-ce --nobest -y

- name: Installing the Prerequisite software for k8s Cluster
  package:
          name: "{{ item }}"      
          state: present
  loop:
          - iproute-tc
          - kubeadm   


- name: Starting the Docker & Kubelet Services
  service:
         name:  "{{ item }}"
         state: started
         enabled: yes
  loop:
          - docker
          - kubelet  

- name: Changing the Docker Cgroup Driver
  copy: 
        dest: /etc/docker/daemon.json
        content: |
            {
                "exec-opts": ["native.cgroupdriver=systemd"]
            } 
- name: Restarting the Docker Services
  service:
        name: docker 
        state: restarted

- name: stopping firewall service
  command: systemctl stop firewalld

- name: Download All Docker Images for k8s Cluster
  shell: "kubeadm config images pull" 
  

- name: Updating the iptables
  copy: 
        dest: /etc/sysctl.d/k8s.conf
        content: |
         net.bridge.bridge-nf-call-ip6tables = 1
         net.bridge.bridge-nf-call-iptables = 1
- name: Change the value to ipv4 tables 
  shell: "echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf"

- name: Enable the ipv4 tables 
  shell: "sudo sysctl -p /etc/sysctl.conf"  

- name: Loading the iptables
  shell: "sysctl --system"  

- name: Initializng k8s Master Node
  shell: "kubeadm init --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=NumCPU --ignore-preflight-errors=Mem"
  


- name: Creating a Directory for kubectl config file
  shell: "mkdir -p $HOME/.kube"

- name: Copying the config file to workspace
  shell: "cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"

- name: Changing the Ownership
  shell: "chown $(id -u):$(id -g) $HOME/.kube/config"  
  ignore_errors: yes

- name: Setting up Overlay Network with CNI Plugin Flannel
  shell: "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
  

- name: Generate the token 
  shell: "kubeadm token create --print-join-command"
  register: token

- name: Print the token 
  debug:
       var: token.stdout_lines
```
### Create Ansible worker role
```
ansible-galaxy init worker
```
### Edit the tasks in the main.yaml for the worker role
```
vim worker/tasks/main.yml
```
```
---
# tasks file for worker

- name: Add repository for kubeadm
  yum_repository:
    name: Kubernetes
    description: YUM repo for kubeadm 
    baseurl: https://packages.cloud.google.com/yum/repos/kubernetes-el7-$basearch
    enabled: yes
    gpgcheck: no

- name: Add repository for docker
  yum_repository:
    name: docker-repo
    description: repo for docker
    baseurl: https://download.docker.com/linux/centos/7/x86_64/stable/
    enabled: yes
    gpgcheck: no

- name: Installing the docker software for k8s Cluster
  command: yum install docker-ce --nobest -y 

- name: Installing the Prerequisite software for k8s Cluster
  package:
          name: "{{ item }}"      
          state: present
  loop:
          - iproute-tc
          - kubeadm   

- name: Starting the Docker & Kubelet Services
  service:
         name:  "{{ item }}"
         state: started
         enabled: yes
  loop:
          - docker
          - kubelet  

- name: Changing the Docker Cgroup Driver
  copy: 
       dest: /etc/docker/daemon.json
       content: |
            {
                "exec-opts": ["native.cgroupdriver=systemd"]
            } 
- name: Restarting the Docker Service
  service:
          name: docker 
          state: restarted


- name: Stopping firewall
  command: systemctl stop firewalld

- name: Updating the iptables
  copy:
        dest: /etc/sysctl.d/k8s.conif
        content: |
         net.bridge.bridge-nf-call-ip6tables = 1
         net.bridge.bridge-nf-call-iptables = 1


- name: Loading the iptables
  shell: "sysctl --system"
          
- name: Change the value to ipv4 tables
  shell: "echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf"

- name: Enable the ipv4 tables
  shell: "sudo sysctl -p /etc/sysctl.conf"
  

- name: Joining the master node
  shell: "{{ master_token }}"
```
### Create ansible playbook to configure VMs in GCP
```
sudo vi master.yaml
```
```
---
    - name: Create Compute Engine instances
      hosts: localhost
      gather_facts: no
      vars:
        gcp_project: keen-alignment-321607
        gcp_cred_kind: serviceaccount
        gcp_cred_file: credentials.json
        zone: "us-central1-a"
        region: "us-central1"
        machine_type: "n1-standard-1"
        image: "projects/centos-cloud/global/images/family/centos-8"
    
      tasks:
        - name: Create an IP address for Master Node
          gcp_compute_address:
            name: master-ip
            region: "{{ region }}"
            project: "{{ gcp_project }}"
            service_account_file: "{{ gcp_cred_file }}"
            auth_kind: "{{ gcp_cred_kind }}"
          register: master_ip
      
        - name: Creating VM for Master Node 
          gcp_compute_instance:
            name: masternode
            machine_type: "{{ machine_type }}"
            disks:
              - auto_delete: true
                boot: true
                initialize_params:
                  source_image: "{{ image }}"
            network_interfaces:
              - access_configs:
                  - name: External NAT
                    nat_ip: "{{ master_ip }}"
                    type: ONE_TO_ONE_NAT
            tags:
              items:
                - kube-master
            zone: "{{ zone }}"
            project: "{{ gcp_project }}"
            service_account_file: "{{ gcp_cred_file }}"
            auth_kind: "{{ gcp_cred_kind }}"
          register: master

      post_tasks:
        - name: Wait for SSH for instance
          wait_for: delay=5 sleep=5 host={{ master_ip.address }} port=22 state=started timeout=100
        - name: Save host data for Masternode
          add_host: hostname={{ master_ip.address }} groupname=gce_masternode
        - name: Pause for 1 minutes to ready instance
          pause:
             minutes: 1


    - name: Configuring Kubernetes Master
      hosts: gce_masternode
      become: yes
      become_method: sudo
      remote_user: guyfridge
      roles:
         - roles/master
```
### Write a playbook to configure the Kubernetes Worker node VM
```
vi worker.yaml
```
```
---
    - name: Create Compute Engine instances
      hosts: localhost
      gather_facts: no
      vars:
        gcp_project: keen-alignment-321607
        gcp_cred_kind: serviceaccount
        gcp_cred_file: credentials.json
        zone: "us-central1-a"
        region: "us-central1"
        machine_type: "n1-standard-1"
        image: "projects/centos-cloud/global/images/family/centos-8"
    
      tasks:
        - name: Create an IP address for Worker
          gcp_compute_address:
            name: worker-ip
            region: "{{ region }}"
            project: "{{ gcp_project }}"
            service_account_file: "{{ gcp_cred_file }}"
            auth_kind: "{{ gcp_cred_kind }}"
          register: worker_ip
      
        - name: Creating VM for worker node 
          gcp_compute_instance:
            name: workernode
            machine_type: "{{ machine_type }}"
            disks:
              - auto_delete: true
                boot: true
                initialize_params:
                  source_image: "{{ image }}"
            network_interfaces:
              - access_configs:
                  - name: External NAT
                    nat_ip: "{{ worker_ip }}"
                    type: ONE_TO_ONE_NAT
            tags:
              items:
                - kube-worker
            zone: "{{ zone }}"
            project: "{{ gcp_project }}"
            service_account_file: "{{ gcp_cred_file }}"
            auth_kind: "{{ gcp_cred_kind }}"
          register: worker

      post_tasks:
        - name: Wait for SSH for instance
          wait_for: delay=5 sleep=5 host={{ worker_ip.address }} port=22 state=started timeout=100
        - name: Save host data for Worker Node
          add_host: hostname={{ worker_ip.address }} groupname=gce_worker

    - name: Configuring Kubernetes Worker Node
      hosts: gce_worker
      remote_user: guyfridge
      become: yes
      become_method: sudo
      vars_prompt:
          - name: master_token
            prompt: Please Enter the master token no
            private: no      
      roles:
         - roles/worker
```
### Create a script which runs both of these playbooks
```
sudo vi main.sh
```
```
ansible-playbook master.yaml -e 'ansible_python_interpreter=/usr/bin/python3'
ansible-playbook worker.yaml -e 'ansible_python_interpreter=/usr/bin/python3'
```
save + exit
### Make main.sh executable
```
sudo chmod +x main.sh
```
### Generate SSH Private / Public Key Pair
```
ssh-keygen
```
Edit /etc/ansible/ansible.cfg to reflect the path of the newly generated private key
```
sudo vi /etc/ansible/ansible.cfg
```
Uncomment the following line and enter the correct path for the private key
```
private_key_file = /home/guyfridge/.ssh/id_rsa
```
### Install pip3 and pre-requisites like google-auth and requests
```
apt install python3-pip
pip3 install google-auth requests
```
### Execute main.sh
```
./main.sh
```


