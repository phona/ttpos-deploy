#!/usr/bin/env python3
"""
CD Machine Orchestration Script for TTPOS

Polls Git repository for changes and triggers Ansible playbooks to reconcile state.
Simulates GitOps behavior for Docker Compose environments.

Usage:
    python3 cd-runner.py [--config CONFIG_FILE] [--once]

Environment Variables:
    POLL_INTERVAL      Polling interval in seconds (default: 60)
    GIT_REPO           Git repository URL
    GIT_BRANCH         Git branch to track (default: main)
    DEPLOY_PATH        Local path for repository checkout
    ANSIBLE_PATH       Path to Ansible directory
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Set

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('cd-runner')


class CDRunner:
    """CD Machine orchestration for TTPOS deployments."""

    def __init__(self, config: Dict):
        self.config = config
        self.poll_interval = config.get('poll_interval', 60)
        self.git_repo = config.get('git_repo', '')
        self.git_branch = config.get('git_branch', 'main')
        self.deploy_path = Path(config.get('deploy_path', '/opt/ttops-deploy'))
        self.ansible_path = self.deploy_path / 'ansible'
        self.last_commit = None

    def run_cmd(self, cmd: str, cwd: Optional[Path] = None) -> tuple:
        """Run shell command and return (returncode, stdout, stderr)."""
        logger.debug(f"Running: {cmd}")
        result = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()

    def init_repo(self) -> bool:
        """Initialize or clone the repository."""
        if not self.deploy_path.exists():
            logger.info(f"Cloning repository to {self.deploy_path}")
            returncode, stdout, stderr = self.run_cmd(
                f"git clone --branch {self.git_branch} {self.git_repo} {self.deploy_path}"
            )
            if returncode != 0:
                logger.error(f"Failed to clone repository: {stderr}")
                return False
        else:
            logger.info(f"Repository exists at {self.deploy_path}")

        # Get current commit
        returncode, stdout, stderr = self.run_cmd(
            "git rev-parse HEAD",
            cwd=self.deploy_path
        )
        if returncode == 0:
            self.last_commit = stdout
            logger.info(f"Current commit: {self.last_commit[:8]}")

        return True

    def check_for_changes(self) -> bool:
        """Check if there are new commits in the repository."""
        logger.debug("Checking for changes...")

        # Fetch latest
        returncode, stdout, stderr = self.run_cmd(
            f"git fetch origin {self.git_branch}",
            cwd=self.deploy_path
        )
        if returncode != 0:
            logger.warning(f"Failed to fetch: {stderr}")
            return False

        # Compare local and remote
        returncode, local, stderr = self.run_cmd(
            "git rev-parse HEAD",
            cwd=self.deploy_path
        )
        returncode, remote, stderr = self.run_cmd(
            f"git rev-parse origin/{self.git_branch}",
            cwd=self.deploy_path
        )

        return local != remote

    def pull_changes(self) -> bool:
        """Pull latest changes from Git."""
        logger.info("Pulling latest changes...")

        returncode, stdout, stderr = self.run_cmd(
            f"git reset --hard origin/{self.git_branch}",
            cwd=self.deploy_path
        )

        if returncode != 0:
            logger.error(f"Failed to pull changes: {stderr}")
            return False

        logger.info("Changes pulled successfully")
        return True

    def detect_changed_environments(self) -> Set[str]:
        """Detect which environments have changed."""
        logger.debug("Detecting changed environments...")

        # Get list of changed files
        returncode, stdout, stderr = self.run_cmd(
            "git diff HEAD~1 --name-only",
            cwd=self.deploy_path
        )

        if returncode != 0:
            logger.warning(f"Failed to get diff: {stderr}")
            return set()

        environments = set()

        for line in stdout.split('\n'):
            if line.startswith('environments/'):
                parts = line.split('/')
                if len(parts) >= 2:
                    environments.add(parts[1])
            elif line.startswith('services/'):
                # Service changes affect all environments
                environments.add('staging')
                environments.add('production')
            elif line.startswith('ansible/'):
                # Ansible changes affect all environments
                environments.add('staging')
                environments.add('production')

        logger.info(f"Changed environments: {environments}")
        return environments

    def detect_changed_services(self) -> Set[str]:
        """Detect which services have changed."""
        logger.debug("Detecting changed services...")

        returncode, stdout, stderr = self.run_cmd(
            "git diff HEAD~1 --name-only",
            cwd=self.deploy_path
        )

        if returncode != 0:
            return set()

        services = set()

        for line in stdout.split('\n'):
            if line.startswith('services/'):
                parts = line.split('/')
                if len(parts) >= 2:
                    services.add(parts[1])

        return services

    def run_ansible(self, environment: str, service: str = "all",
                    tag: Optional[str] = None) -> bool:
        """Run Ansible playbook for specific environment."""
        logger.info(f"Running Ansible for {environment}/{service}...")

        cmd = f"ansible-playbook -i inventories/{environment}/hosts.yml playbooks/deploy.yml"
        cmd += f" -e 'service_name={service}'"
        cmd += f" -e 'env={environment}'"

        if tag:
            cmd += f" -e 'tag={tag}'"

        returncode, stdout, stderr = self.run_cmd(
            cmd,
            cwd=self.ansible_path
        )

        if returncode == 0:
            logger.info(f"Deployed {service} to {environment}")
            return True
        else:
            logger.error(f"Failed to deploy {service} to {environment}: {stderr}")
            return False

    def run_health_check(self, environment: str) -> bool:
        """Run health check for environment."""
        logger.info(f"Running health check for {environment}...")

        cmd = f"ansible-playbook -i inventories/{environment}/hosts.yml playbooks/health-check.yml"

        returncode, stdout, stderr = self.run_cmd(
            cmd,
            cwd=self.ansible_path
        )

        if returncode == 0:
            logger.info(f"Health check passed for {environment}")
            return True
        else:
            logger.error(f"Health check failed for {environment}: {stderr}")
            return False

    def send_notification(self, status: str, environment: str,
                          service: str = "all", tag: str = ""):
        """Send notification (calls notify.sh script)."""
        notify_script = self.deploy_path / "scripts" / "notify.sh"

        if not notify_script.exists():
            logger.warning("notify.sh script not found")
            return

        cmd = f"{notify_script} --status {status} --env {environment} --service {service}"
        if tag:
            cmd += f" --tag {tag}"

        self.run_cmd(cmd)

    def reconcile(self):
        """Reconcile state by detecting changes and deploying."""
        logger.info("Starting reconciliation...")

        if not self.check_for_changes():
            logger.debug("No changes detected")
            return

        logger.info("Changes detected, pulling...")
        if not self.pull_changes():
            logger.error("Failed to pull changes")
            return

        # Detect what changed
        changed_envs = self.detect_changed_environments()
        changed_services = self.detect_changed_services()

        if not changed_envs:
            logger.info("No environment changes detected")
            return

        # Deploy to each changed environment
        for env in changed_envs:
            # Only auto-deploy staging
            if env == 'staging':
                logger.info(f"Auto-deploying to {env}...")

                if changed_services:
                    for service in changed_services:
                        success = self.run_ansible(env, service)
                        if not success:
                            self.send_notification("failure", env, service)
                else:
                    success = self.run_ansible(env, "all")
                    if not success:
                        self.send_notification("failure", env)

                # Run health check
                self.run_health_check(env)
                self.send_notification("success", env)

            elif env == 'production':
                # Production requires manual approval
                logger.info(f"Production changes detected - manual approval required")
                self.send_notification("pending", env, "production changes require approval")

    def run_once(self):
        """Run a single reconciliation pass."""
        logger.info("Running single reconciliation pass...")
        self.reconcile()

    def run_forever(self):
        """Run continuous reconciliation loop."""
        logger.info(f"Starting CD runner (poll interval: {self.poll_interval}s)")

        while True:
            try:
                self.reconcile()
            except Exception as e:
                logger.error(f"Error during reconciliation: {e}")

            logger.debug(f"Sleeping for {self.poll_interval}s...")
            time.sleep(self.poll_interval)


def load_config() -> Dict:
    """Load configuration from environment variables."""
    return {
        'poll_interval': int(os.getenv('POLL_INTERVAL', '60')),
        'git_repo': os.getenv('GIT_REPO', 'https://github.com/your-org/ttops-deploy.git'),
        'git_branch': os.getenv('GIT_BRANCH', 'main'),
        'deploy_path': os.getenv('DEPLOY_PATH', '/opt/ttops-deploy'),
    }


def main():
    parser = argparse.ArgumentParser(description='TTPOS CD Runner')
    parser.add_argument('--once', action='store_true',
                        help='Run single reconciliation pass')
    parser.add_argument('--config', type=str,
                        help='Path to configuration file')
    parser.add_argument('--debug', action='store_true',
                        help='Enable debug logging')
    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    # Load configuration
    config = load_config()

    if args.config:
        with open(args.config) as f:
            config.update(json.load(f))

    # Create runner
    runner = CDRunner(config)

    # Initialize repository
    if not runner.init_repo():
        logger.error("Failed to initialize repository")
        sys.exit(1)

    # Run
    if args.once:
        runner.run_once()
    else:
        runner.run_forever()


if __name__ == '__main__':
    main()
