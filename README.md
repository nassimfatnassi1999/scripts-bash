# Linux DevOps Toolbox

A portable Bash toolbox for common Linux, DevOps, cloud, container, Kubernetes, backup, security, monitoring, and troubleshooting workflows.

The scripts are organized around a shared library in `lib/common.sh` and a central launcher in `main.sh`.

## Supported Systems

The toolbox targets common Linux distributions and package managers:

- Ubuntu / Debian with `apt`
- Fedora / RHEL / CentOS with `dnf` or `yum`
- Arch Linux with `pacman`
- openSUSE with `zypper`
- Alpine Linux with `apk`

Some tool-specific upstream installers may still have their own architecture or distribution limits.

## Usage

Run the central menu:

```bash
chmod +x main.sh scripts/*.sh lint.sh
./main.sh
```

Enable dry-run mode for supported actions:

```bash
./main.sh --dry-run
```

Run a script directly:

```bash
./scripts/docker.sh
./scripts/terraform.sh
./scripts/network-tools.sh
```

## Structure

```text
.
├── lib/
│   └── common.sh
├── main.sh
├── lint.sh
├── .shellcheckrc
└── scripts/
    ├── ansible.sh
    ├── backup-restore.sh
    ├── cloud-cli.sh
    ├── cron-manager.sh
    ├── dev-tools.sh
    ├── docker-cleanup.sh
    ├── docker.sh
    ├── firewall.sh
    ├── git-switch.sh
    ├── helm.sh
    ├── installed-packages.sh
    ├── jenkins.sh
    ├── k8s-tools.sh
    ├── kopia.sh
    ├── kubectl.sh
    ├── minikube.sh
    ├── monitoring.sh
    ├── network-tools.sh
    ├── secrets-manager.sh
    ├── service-manager.sh
    ├── setup-dev-linux.sh
    ├── ssh-manager.sh
    ├── system-update.sh
    ├── terraform.sh
    ├── troubleshoot.sh
    ├── user-group.sh
    ├── vm-tools.sh
    └── zip-disk.sh
```

## Categories

- System: updates, users, services, installed packages, developer tools, VM tools.
- Docker: Docker installation, cleanup, inspection and archive operations.
- Kubernetes: kubectl, minikube, Helm and extra Kubernetes tools.
- Cloud: AWS, Azure and Google Cloud CLI management.
- IaC: Terraform, OpenTofu and Ansible workflows.
- CI/CD: Jenkins installation and management.
- Backup: local archive/restore, Kopia and zip/tar utilities.
- Network and Security: network diagnostics, SSH, firewall, secrets and Git account switching.
- Monitoring: system monitoring and troubleshooting.
- Automation: cron management.

## Validation

Run:

```bash
./lint.sh
```

The linter always runs `bash -n`. It also runs ShellCheck and shfmt when those tools are installed.

## Safety

Scripts use confirmations before destructive operations such as deleting users, pruning backups, destroying infrastructure, disabling firewall protection, removing secrets, or cleaning caches.

Set `DRY_RUN=1` or use `./main.sh --dry-run` to preview supported commands without applying changes.
