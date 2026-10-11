# Discarded terminal trials

These trials used Bash EPOCHREALTIME, which measures wall time. WSL adjusted that
clock during execution; one result was **negative 862.658 ms**. Forward steps
could also inflate durations. None of these files supports the final latency
conclusions, including apparent outliers or preview differences.

They are retained for transparency. The parent directory contains the complete
replacement matrix measured with monotonic Linux uptime and 10 ms resolution.
