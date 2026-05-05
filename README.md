# 🧰 Bash Scripts – Essential Tools for DevOps & Cloud Engineers

This repository contains a collection of **Bash scripts** designed to automate the installation, configuration, and troubleshooting of key tools used in **DevOps** and **Cloud Engineering**.  
They help save time, standardize environments, and simplify the setup of reproducible infrastructures.

---

## 🚀 Purpose

The goal of this repository is to provide a simple yet powerful toolkit to:
- Automate installation of Cloud Native technologies (Terraform, Docker, Kubernetes, etc.)
- Standardize development and production environments.
- Simplify deployment and maintenance of CI/CD and configuration management tools.
- Speed up the setup of a complete DevOps environment on any Linux machine.

---

## 📂 Repository Structure
```bash
├── ansible.sh
├── cloud-cli.sh
├── docker-cleanup.sh
├── docker.sh
├── git-switch.sh
├── helm.sh
├── installed-packages.sh
├── jenkins.sh
├── kopia.sh
├── kubectl.sh
├── minikube.sh
├── terraform.sh
├── troubleshoot.sh
├── user-group.sh
├── zip-disk.sh
├── ssh/
│   ├── create_and_deploy_ssh_key.sh
│   └── setup-ssh.sh
└── zabbix/
    ├── grafana-zabbix.sh
    ├── remove-grafana-zabbix.sh
    ├── remove-zabbix-agent.sh
    ├── remove-zabbix-server.sh
    ├── zabix-agent.sh
    └── zabix-server.sh
```
## 🧑‍💻 Usage

Run any script individually:
```bash
sudo chmod +x <script-name>.sh
sudo ./<script-name>.sh
```