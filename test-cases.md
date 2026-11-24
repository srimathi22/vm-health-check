# Test Cases

The automated checks in `tests/test_vm_health_check.sh` exercise the health decision logic using fixed values. The remaining cases describe integration and error handling checks.

## Positive Cases

| ID | Input or condition | Expected result |
| --- | --- | --- |
| P-01 | CPU 0%, memory 42.5%, disk 59.99% | `HEALTHY` |
| P-02 | CPU, memory, and disk all 0% | `HEALTHY` |
| P-03 | Any one metric is exactly 60% | `NOT HEALTHY` |
| P-04 | Any one metric is greater than 60% | `NOT HEALTHY` |
| P-05 | Run on supported Linux or macOS with required tools available | Print all three percentages and an overall status |

## Negative Cases

| ID | Input or condition | Expected result |
| --- | --- | --- |
| N-01 | Utilization is non-numeric | Classifier rejects the value; script reports an error if encountered during a check |
| N-02 | Utilization is outside the 0% to 100% range | Classifier rejects the value |
| N-03 | A required command is missing | Print the missing command and exit nonzero |
| N-04 | Linux proc metric files are missing or unreadable | Print a metric-specific error and exit nonzero |
| N-05 | Host OS is neither Linux nor macOS | Print an unsupported-OS error and exit nonzero |
| N-06 | Pass an argument to the script | Print an argument error and exit nonzero |
| N-07 | One metric is exactly 60% while the others are below 60% | Overall status is `NOT HEALTHY` |

## Run Automated Cases

```bash
bash -n vm-health-check.sh tests/test_vm_health_check.sh
bash tests/test_vm_health_check.sh
```

For host integration coverage, run `./vm-health-check.sh` on each supported operating system and verify that the printed measurements are plausible for that machine.