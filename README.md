# vm-health-check

A small Bash utility that reports CPU, memory, and root-disk utilization for a Linux or macOS machine. It prints `HEALTHY` only when every utilization value is below 60%. A value of exactly 60% is `NOT HEALTHY`.

## Project Overview

`vm-health-check.sh` gathers current system utilization, prints each percentage, and summarizes the result. It exits with an error and a useful message when a required system metric cannot be read. This is a lightweight snapshot check, not a monitoring agent or a replacement for a metrics platform.

## Architecture

- CPU: Linux reads `/proc/stat` twice one second apart; macOS reads the idle percentage from `top` and converts it to utilization.
- Memory: Linux uses `MemTotal` and `MemAvailable` from `/proc/meminfo`; macOS estimates available memory from free, inactive, and speculative pages reported by `vm_stat`.
- Disk: `df` measures the root filesystem (`/`).
- Decision: the shared classifier validates all values and returns `HEALTHY` only if CPU, memory, and disk are each less than 60%.

## Prerequisites

- Linux or macOS.
- Bash 3.2 or newer.
- `awk`, `df`, and `uname` on `PATH`.
- On macOS, `top`, `sysctl`, and `vm_stat` on `PATH`.
- On Linux, readable `/proc/stat` and `/proc/meminfo`, plus `sleep`.

The script does not require root privileges.

## Installation

Clone or download the project, then enter its directory. If the executable bit was not preserved, set it with:

```bash
chmod +x vm-health-check.sh
```

## Usage

Run the check from the project directory:

```bash
./vm-health-check.sh
```

The script does not accept arguments. It checks CPU, memory, and disk in sequence and returns a nonzero exit status if a prerequisite or metric check fails. A successful check prints its measurements and overall health status; the status itself does not change the process exit code.

## Sample Output

```text
VM Health Check
CPU utilization:    12.34%
Memory utilization: 48.21%
Disk utilization:   35.67%
Overall status:     HEALTHY
```

If any metric is 60% or higher, the final line is:

```text
Overall status:     NOT HEALTHY
```

## Testing

Run the deterministic classification tests and a Bash syntax check:

```bash
bash -n vm-health-check.sh tests/test_vm_health_check.sh
bash tests/test_vm_health_check.sh
```

Run `./vm-health-check.sh` for an integration check against the current machine. The test cases in `test-cases.md` also describe failure and boundary scenarios for review or manual testing.

## Troubleshooting

- **`Required command not found`**: Install the named system utility or add its location to `PATH`.
- **Cannot read `/proc/...`**: Run on Linux with the standard proc filesystem mounted and readable.
- **Could not read CPU or memory utilization**: Confirm the host provides the documented system interfaces and that the utilities are available.
- **Unsupported operating system**: The script currently supports Linux and macOS only.
- **`NOT HEALTHY`**: At least one measured value is 60% or higher. Check the printed metrics and free the relevant resource or adjust the operational threshold in the script if your policy differs.
- **Disk check looks unexpected**: The disk metric is for the root filesystem (`/`), not every mounted volume.