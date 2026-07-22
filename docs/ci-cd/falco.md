# CI/CD — Falco (Runtime Threat Detection)

## What This Adds
Everything built so far either inspects something static (code, an
image, a config file) or gates something at a single moment in time
(admission, deployment). Falco is different in kind: it watches the
cluster continuously, while things are actually running, and alerts on
suspicious *behavior* as it happens. This is the last layer in the
defense-in-depth chain, catching what got past every earlier stage,
scanning missed it, the gate let it through, Gatekeeper admitted it,
NetworkPolicies didn't stop it, and something is now actually doing
something bad inside a running container.

## Why This Is Fundamentally Different From Every Prior Stage
| Stage | When it acts | What it does |
|---|---|---|
| Scanning (SAST, Trivy, Checkov, etc.) | Before merge | Reports on static artifacts |
| Gatekeeper | At admission (`kubectl apply` time) | Blocks the request outright |
| NetworkPolicies | Continuously, at the network layer | Blocks specific traffic paths |
| **Falco** | **Continuously, at the syscall layer** | **Observes and alerts; does not block** |

Falco cannot prevent a bad action from happening, by the time it fires
an alert, the syscall already occurred. Its job is fast, reliable
detection: turning "a container silently did something suspicious" into
"a container did something suspicious, and here is exactly what,
when, and in which pod," ideally fast enough for a human or automated
response to act on it.

## How Falco Actually Works
Falco runs as a **DaemonSet**, one Falco pod per node, watching every
syscall made by every process on that node, correlated with container
and Kubernetes metadata (which pod, namespace, image made this call).
It evaluates each syscall against a library of rules, most from Falco's
own well-maintained default ruleset, covering common attacker behavior:
spawning a shell in a container, reading credential files, unexpected
outbound connections, writing below `/etc`, package managers running
inside an app container, and many more.

### Driver: modern_ebpf
Falco needs a way to actually observe syscalls at the kernel level.
This project uses `driver.kind: modern_ebpf`, Falco's newest,
CO-RE-based (Compile Once, Run Everywhere) eBPF driver. Chosen
specifically because it requires no kernel module compilation and no
privileged `driver-loader` init container trying to build or download a
matching driver for the exact kernel, which works reliably as long as
the kernel is 5.8+. GitHub Actions runners qualify, and since kind's
nodes are containers sharing the runner's host kernel, Falco (running
inside the kind cluster) can actually observe syscalls made by other
containers on that same shared kernel, including the application pods.

## The Two Test Events
Chosen specifically because they're reliable without a real TTY,
`kubectl exec` from a non-interactive CI shell doesn't have one, which
rules out the classic "spawn an interactive shell" demo many Falco
tutorials use, since that specific default rule checks for an actual
allocated terminal.

1. **`cat /etc/shadow`** inside `auth-service` → triggers Falco's
   default `Read sensitive file untrusted` rule. `/etc/shadow` holds
   password hashes; an application container reading it has no
   legitimate reason to and is a strong compromise indicator.
2. **`apt-get update`** inside `auth-service` → triggers `Launch
   Package Management Process in Container`. A running application
   container invoking a package manager live is unusual behavior;
   images should be built once and not modified at runtime. This is
   also a common step in real attacker toolchains, installing tools
   after gaining a foothold.

## How the Workflow Verifies Detection
Rather than just checking Falco's pod is `Running`, the workflow:
1. Streams Falco's logs to a file in the background (captured via PID,
   not shell job control, which doesn't survive across separate
   workflow steps)
2. Triggers both test events inside a real running application pod
3. Waits for Falco to process and emit alerts
4. Greps the captured log for both expected rule names
5. Fails the job if either expected alert is missing, this test would
   be meaningless if it only checked "Falco started successfully"

## Known Limitations
- This project's default Falco ruleset is used as-is. A real production
  deployment typically layers custom rules specific to the
  application's actual expected behavior (e.g., explicitly alerting if
  `auth-service` ever makes an outbound connection to anything other
  than `auth-db`), which this stage doesn't build.
- Falco alerts here only go to its own pod logs. A real deployment
  routes alerts somewhere actionable, Falcosidekick (explicitly
  disabled here, `falcosidekick.enabled: false`) forwards to Slack,
  PagerDuty, a SIEM, etc. Wiring that up is a reasonable next step, not
  done in this stage.
- Falco detects; it does not respond. Automated response (killing a
  pod, isolating it via a NetworkPolicy) requires either Falcosidekick
  with a response plugin, or a separate controller watching Falco's
  output, neither of which exists in this project yet.
- Single-node kind cluster means one Falco pod. On a real multi-node
  cluster, the DaemonSet runs one Falco instance per node, each only
  seeing syscalls on its own node, this project's test doesn't exercise
  that multi-node behavior.