ansible-playbook master.yaml -e 'ansible_python_interpreter=/usr/bin/python3' -vvv
ansible-playbook worker.yaml -e 'ansible_python_interpreter=/usr/bin/python3' -vvv
