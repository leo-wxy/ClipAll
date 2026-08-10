# Backend Quality Guidelines

## Scenario: Sensitive Runner Process I/O

### 1. Scope / Trigger

Apply this contract whenever the host launches a child process whose standard
streams carry selected text, plugin configuration, results, secrets, or other
user-sensitive data. The current owner is
`ClipAll/PluginHost/Runtime/PluginRunnerClient.swift`.

### 2. Signatures

```swift
PluginRunnerClient.execute(
    _ request: PluginRuntimeRequest
) async throws -> PluginRunnerExecution
```

The child process contract remains one JSON request on stdin and one JSON
response on stdout. `PluginRuntimeLimits` owns protocol and byte limits.

### 3. Contracts

- Sensitive request, response, and stderr transport uses anonymous `Pipe`
  instances only. Never stage process standard streams through files.
- Close the host stdin writer after the full request is sent so a runner using
  `readDataToEndOfFile()` receives EOF.
- Drain stdout and stderr while the process is running. Waiting for process
  termination before reading either stream can deadlock on pipe backpressure.
- Retain at most `maximumResponseBytes + 1` bytes from stdout. After crossing
  the limit, continue draining and discard the remainder.
- Drain and discard process stderr. JavaScript debug logs come only from the
  bounded `PluginRuntimeResponse.logs` field; stderr is not a product log.
- Preserve cancellation, timeout, termination, exit-code, response-size, JSON,
  protocol-version, and structural-validation ordering.
- I/O workers must have bounded shutdown. Closing or cancelling a process must
  not leave the caller waiting indefinitely for inherited pipe descriptors.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Runner is missing or not executable | `PluginRunnerClientError.runnerMissing` |
| Encoded request exceeds `maximumRequestBytes` | `requestTooLarge`; do not launch |
| `Process.run()` fails | `launchFailed` |
| Task is cancelled | terminate the child and throw `CancellationError` |
| Runner exceeds the configured deadline | terminate/SIGKILL fallback, then `timedOut` |
| Runner exits non-zero | `invalidResponse`, before response parsing |
| Successful stdout exceeds `maximumResponseBytes` | `responseTooLarge` |
| stdout is empty, invalid JSON, wrong protocol, or structurally inconsistent | `invalidResponse` |
| stdin writer receives EPIPE after child exit | keep the exit/response error semantics; do not add a public error |

### 5. Good / Base / Bad Cases

- Good: write request data through stdin Pipe, close for EOF, concurrently
  drain bounded stdout and discard stderr, then validate the response.
- Base: a small valid response exits successfully and preserves duration and
  `PluginRuntimeResponse.logs` behavior.
- Bad: use `temporaryDirectory`, `stdin.json`, `stdout.json`, or `stderr.log`
  for process transport, even when permissions are restrictive or cleanup is
  scheduled.
- Bad: merge stderr into stdout, because stdout owns exactly one JSON response.
- Bad: stop reading stdout immediately after the limit is crossed; the child
  can block before it exits.

### 6. Tests Required

- `Scripts/verify-runner-client.sh` must assert:
  - stdin EOF completes a valid runner request;
  - no `ClipAllPluginRunner-*` transport directory appears while running;
  - simultaneous oversized stdout and stderr do not deadlock;
  - cancellation under output pressure completes in under one second;
  - existing missing, invalid, non-zero, oversized, timeout, cancellation, and
    request-too-large errors remain stable.
- `Scripts/verify-plugin.sh` must pass all real runner fixtures.
- `Scripts/verify-all.sh` and SwiftPM build/test must pass before commit.
- Static review of `PluginRunnerClient.swift` must find no process transport
  file paths or `FileManager.default.temporaryDirectory` usage.

### 7. Wrong vs Correct

#### Wrong

`try requestData.write(to: temporaryURL)`

#### Correct

`process.standardInput = Pipe()`
