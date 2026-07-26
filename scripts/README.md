# Repository Scripts

This directory contains repository-level setup, checking, and demo commands. Component-specific scripts belong inside their respective component folders.

## Planned Scripts

### `setup-demo.sh`

**Purpose:** Initialize the hackathon demo environment on a fresh checkout.

**What it does:**
- Validates Python 3 and Jac toolchain versions
- Creates local configuration files (`.env`, coordinator URL, worker registration credentials)
- Seeds the initial profiles dataset into the sandbox
- Registers demo worker machines on the local network
- Initializes the Jac graph database (or verifies it's empty)
- Prints a summary: coordinator URL, worker count, ready-to-submit message

**When to run:**
- First time after cloning the repository
- When resetting the demo environment for a fresh start

---

### `run-demo.sh`

**Purpose:** Execute the end-to-end hackathon demonstration workflow.

**What it does:**
- Verifies the demo environment is set up (`setup-demo.sh` has run)
- Submits a sample embedding job via the Job Submission API (Contract A)
- Polls job status at regular intervals
- Collects task execution metadata (worker assignments, resource usage, timing)
- Waits for result completion and verification
- Fetches and displays the final embedding results + payment receipt
- Prints timing, cost, and worker reputation updates

**When to run:**
- After `setup-demo.sh` to execute a complete job from submission to payment
- Repeatable: can be run multiple times to test parallel jobs and worker scheduling

---

### `check-all.sh`

**Purpose:** Validate the entire repository and all component codebases.

**What it does:**
- Syntax checks: JSON files in `contracts/`, Jac files in `src/`, Python files (if any)
- Linting: Component-specific linters (Jac, Python, etc.)
- Unit tests: Runs all component test suites (`platform/*/tests`, `apps/*/tests`, `workloads/*/tests`, `sandbox/tests`)
- Contract validation: Validates example JSON files against schemas
- Integration checks: Verifies cross-component interfaces (API endpoints, contract shapes)
- Reports: Summarizes pass/fail, coverage, and any deprecation warnings

**When to run:**
- Before submitting a pull request
- In CI/CD pipelines for automated validation
- Periodically during development to catch cross-component breakage early
