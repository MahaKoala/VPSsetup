<div id="top">

<!-- HEADER STYLE: CLASSIC -->
<div align="center">


# VPSSETUP

<em>Secure, Simplify, Scale Your Server Infrastructure Effortlessly</em>

<!-- BADGES -->
<img src="https://img.shields.io/github/last-commit/MahaKoala/VPSsetup?style=flat&logo=git&logoColor=white&color=0080ff" alt="last-commit">
<img src="https://img.shields.io/github/languages/top/MahaKoala/VPSsetup?style=flat&color=0080ff" alt="repo-top-language">
<img src="https://img.shields.io/github/languages/count/MahaKoala/VPSsetup?style=flat&color=0080ff" alt="repo-language-count">

<em>Built with the tools and technologies:</em>

<img src="https://img.shields.io/badge/JSON-000000.svg?style=flat&logo=JSON&logoColor=white" alt="JSON">
<img src="https://img.shields.io/badge/Markdown-000000.svg?style=flat&logo=Markdown&logoColor=white" alt="Markdown">
<img src="https://img.shields.io/badge/GNU%20Bash-4EAA25.svg?style=flat&logo=GNU-Bash&logoColor=white" alt="GNU%20Bash">
<img src="https://img.shields.io/badge/YAML-CB171E.svg?style=flat&logo=YAML&logoColor=white" alt="YAML">

</div>
<br>

---

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Installation](#installation)
    - [Usage](#usage)
    - [Testing](#testing)
- [Features](#features)
- [Project Structure](#project-structure)
    - [Project Index](#project-index)

---

## Overview

VPSsetup is a comprehensive toolkit designed to automate the secure deployment and management of VPS instances, ensuring consistency and resilience across your infrastructure. The core features include:

- 🛡️ **Security Hardening:** Automates firewall rules, intrusion prevention, kernel tuning, and automatic updates to keep your servers secure.
- 🔑 **SSH Key Management:** Securely add and update SSH keys from sshid.io, simplifying user onboarding and access control.
- ⚙️ **Automated Initialization:** Supports idempotent setup scripts for quick, repeatable server provisioning across multiple providers.
- 🌐 **Network Integration:** Manages server tags and SSH permissions with Tailscale, ensuring organized and secure remote access.
- 🧰 **Tooling & Monitoring:** Installs essential development tools and performs health checks to maintain optimal server performance.

---

## Features

|      | Component          | Details                                                                                     |
| :--- | :----------------- | :------------------------------------------------------------------------------------------ |
| ⚙️  | **Architecture**   | <ul><li>Modular scripts for VPS setup automation</li><li>Uses cloud-init for initial provisioning</li></ul> |
| 🔩 | **Code Quality**   | <ul><li>Clear separation of concerns</li><li>Consistent naming conventions</li></ul>     |
| 📄 | **Documentation**  | <ul><li>README provides overview and usage instructions</li><li>Includes sample configs</li></ul> |
| 🔌 | **Integrations**    | <ul><li>Integrates with Tailscale via `tailscale.json`</li><li>Uses cloud-init YAML for cloud provisioning</li></ul> |
| 🧩 | **Modularity**      | <ul><li>Scripts organized into distinct files for setup, configuration, and cleanup</li></ul> |
| 🧪 | **Testing**         | <ul><li>No explicit testing framework detected; relies on manual validation</li></ul> |
| ⚡️  | **Performance**     | <ul><li>Lightweight scripts optimized for quick execution</li><li>Minimal dependencies reduce startup time</li></ul> |
| 🛡️ | **Security**        | <ul><li>Uses cloud-init for secure initial setup</li><li>Minimal external dependencies reduce attack surface</li></ul> |
| 📦 | **Dependencies**    | <ul><li>Python modules: `markdown`</li><li>Configuration files: `tailscale.json`, `shell` scripts, `cloud-init.yaml`</li></ul> |

---

## Project Structure

```sh
└── VPSsetup/
    ├── README.md
    ├── README_SSHIDscript.md
    ├── README_SingleFileVPSinit.md
    ├── README_VPSscripts.md
    ├── VerifyChecklist.sh
    ├── addnew-sshid-key.sh
    ├── addupdate-sshid-key.sh
    ├── bootstrap.env
    ├── cloud-init.yaml
    ├── firstrun.sh
    ├── tailscale.json
    ├── vps-bootstrap.sh
    ├── vps-harden.sh
    ├── vps-init.sh
    └── vps-tools.sh
```

---

### Project Index

<details open>
	<summary><b><code>VPSSETUP/</code></b></summary>
	<!-- __root__ Submodule -->
	<details>
		<summary><b>__root__</b></summary>
		<blockquote>
			<div class='directory-path' style='padding: 8px 0; color: #666;'>
				<code><b>⦿ __root__</b></code>
			<table style='width: 100%; border-collapse: collapse;'>
			<thead>
				<tr style='background-color: #f8f9fa;'>
					<th style='width: 30%; text-align: left; padding: 8px;'>File Name</th>
					<th style='text-align: left; padding: 8px;'>Summary</th>
				</tr>
			</thead>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/vps-harden.sh'>vps-harden.sh</a></b></td>
					<td style='padding: 8px;'>- Provides automated hardening and security configuration for VPS instances by managing SSH access, firewall rules, intrusion prevention, automatic updates, system kernel settings, and optional Tailscale integration<br>- Ensures a secure, resilient, and manageable environment, aligning with best practices for server security and network connectivity within the overall infrastructure architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/addnew-sshid-key.sh'>addnew-sshid-key.sh</a></b></td>
					<td style='padding: 8px;'>- Automates the secure addition of SSH public keys from sshid.io to specified user accounts, with optional user creation and sudo privileges<br>- Ensures idempotent key installation, manages user setup, permissions, and reloads SSH service as needed<br>- Facilitates streamlined, repeatable onboarding of SSH keys for secure, passwordless access across server environments.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/README_SingleFileVPSinit.md'>README_SingleFileVPSinit.md</a></b></td>
					<td style='padding: 8px;'>- Provides a comprehensive, self-contained script to automate VPS initialization across various providers lacking cloud-init<br>- It streamlines setup by configuring user access, hostname, SSH keys, system hardening, and Tailscale integration, ensuring idempotent re-runs and secure handling of sensitive data<br>- Facilitates quick, consistent deployment and easy reconfiguration of VPS environments with minimal manual intervention.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/tailscale.json'>tailscale.json</a></b></td>
					<td style='padding: 8px;'>- Defines access control policies for managing server tags and SSH permissions within the infrastructure<br>- It specifies ownership of environment tags such as vps, staging, and production, and grants SSH access to designated users from administrative groups<br>- This configuration ensures secure, organized, and consistent management of server environments and remote access across the entire architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/vps-tools.sh'>vps-tools.sh</a></b></td>
					<td style='padding: 8px;'>- Sets up AI and agent tooling on a VPS environment by installing essential development, terminal, and automation tools, and configuring system services<br>- Facilitates seamless integration of AI agents, code assistants, and productivity utilities, ensuring a ready-to-use infrastructure for AI-driven workflows and development automation within the broader system architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/README_SSHIDscript.md'>README_SSHIDscript.md</a></b></td>
					<td style='padding: 8px;'>- Provides a secure, idempotent mechanism to manage SSH access by installing SSH keys and optionally creating and configuring users with sudo privileges<br>- Enhances overall system security and accessibility by automating user setup, key validation, and sudo configuration, ensuring consistent, safe, and repeatable SSH key deployment across the infrastructure.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/README.md'>README.md</a></b></td>
					<td style='padding: 8px;'>- Provides an overview of the VPSsetup project, outlining its primary goal of automating the configuration and deployment of virtual private servers<br>- Facilitates streamlined server setup, ensuring consistent environments across deployments<br>- Serves as a foundational component within the broader infrastructure, enabling efficient management and scaling of server resources across various environments.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/cloud-init.yaml'>cloud-init.yaml</a></b></td>
					<td style='padding: 8px;'>- Automates the initial setup and hardening of cloud-based VPS instances across multiple providers by configuring system packages, security settings, and essential tools<br>- Ensures consistent, secure, and ready-to-use environments tailored for development or deployment roles, integrating custom environment variables and security enhancements to streamline provisioning within the overall infrastructure architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/VerifyChecklist.sh'>VerifyChecklist.sh</a></b></td>
					<td style='padding: 8px;'>- VerifyChecklist.sh performs a comprehensive health and security audit of a server environment<br>- It verifies SSH access, system configuration, network status, firewall rules, security tools, and system updates, providing a consolidated overview of the server’s operational state<br>- This ensures the server remains secure, properly configured, and ready for production or further deployment within the overall infrastructure.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/vps-bootstrap.sh'>vps-bootstrap.sh</a></b></td>
					<td style='padding: 8px;'>- Automates initial server setup on Ubuntu 24.04 by provisioning essential packages, configuring hostname, managing user accounts and SSH keys, and optionally installing development tools like Homebrew, Node.js, and Docker<br>- Ensures a secure, consistent environment ready for deployment or development, streamlining the first-boot process and establishing a solid foundation within the overall infrastructure architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/vps-init.sh'>vps-init.sh</a></b></td>
					<td style='padding: 8px;'>- Vps-init.shThis script serves as a comprehensive, one-shot provisioning tool for Ubuntu 24.04 VPS instances across various cloud providers<br>- Its primary purpose is to automate the initial setup process, ensuring consistent and secure configuration of new virtual private servers<br>- Designed to be idempotent and safe to rerun, it streamlines the deployment workflow by handling essential system preparations, making it ideal for both manual and automated provisioning scenarios within the broader infrastructure architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/firstrun.sh'>firstrun.sh</a></b></td>
					<td style='padding: 8px;'>- Facilitates manual VPS setup by automating environment configuration, security hardening, and initial provisioning without cloud-init<br>- Ensures consistent deployment through scripted steps that install necessary tools, apply security measures, and prepare the server for remote management via Tailscale<br>- Integrates seamlessly into the broader infrastructure to streamline initial server setup and hardening processes.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/addupdate-sshid-key.sh'>addupdate-sshid-key.sh</a></b></td>
					<td style='padding: 8px;'>- Facilitates secure, automated management of SSH access by fetching public keys from sshid.io and integrating them into user authorized_keys files<br>- Ensures idempotent updates, proper permissions, and optional SSH daemon reloads, supporting multiple key types<br>- Integrates seamlessly into deployment workflows to streamline user access provisioning across the infrastructure.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/README_VPSscripts.md'>README_VPSscripts.md</a></b></td>
					<td style='padding: 8px;'>- Provides a comprehensive, idempotent provisioning framework for Ubuntu 24.04 VPSs, enabling automated setup, security hardening, and optional tooling installation<br>- It streamlines initial deployment, enforces best practices for SSH, network, and system security, and supports environment-specific configurations, facilitating scalable, secure, and maintainable cloud infrastructure aligned with modern DevOps workflows.</td>
				</tr>
			</table>
		</blockquote>
	</details>
</details>

---

## Getting Started

### Prerequisites

This project requires the following dependencies:

- **Programming Language:** Shell
- **Package Manager:** Bash

### Installation

Build VPSsetup from the source and install dependencies:

1. **Clone the repository:**

    ```sh
    ❯ git clone https://github.com/MahaKoala/VPSsetup
    ```

2. **Navigate to the project directory:**

    ```sh
    ❯ cd VPSsetup
    ```

3. **Install the dependencies:**

**Using [bash](https://www.gnu.org/software/bash/):**

```sh
❯ chmod +x {entrypoint}
```

### Usage

Run the project with:

**Using [bash](https://www.gnu.org/software/bash/):**

```sh
./{entrypoint}
```

### Testing

Vpssetup uses the {__test_framework__} test framework. Run the test suite with:

**Using [bash](https://www.gnu.org/software/bash/):**

```sh
bats *.bats
```

---

<div align="left"><a href="#top">⬆ Return</a></div>

---
