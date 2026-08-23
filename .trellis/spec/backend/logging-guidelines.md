# Logging Guidelines

## API And Ownership

Use `OSLog.Logger` directly in the type that owns the event. Define one private
static logger with the App bundle identifier and a stable category matching the
owning component. Do not add a logging wrapper while the native API covers the
required privacy and level semantics.

```swift
private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.wxy.ClipAll",
    category: "SelectionMonitor"
)
```

## Levels

- `debug`: diagnostic path selection and expected recoverable failures.
- `info`: normal capture decisions, policy suppression, and resolved metadata.
- `notice`: application or long-lived service lifecycle transitions.
- `error`: unexpected failures and contract violations that prevent an action.

Cancellation and unsupported selection are normal control flow. Do not promote
them to errors solely to make them more visible.

## Structured Metadata

Log stable structural fields such as category, trigger, bundle identifier,
policy, capability identifier, error enum or error type, boolean state, bounds
presence, count, and duration. Mark intentionally visible structural values with
`privacy: .public`; leave uncertain values private rather than interpolating
their description publicly.

```swift
Self.logger.info(
    "Selection capture requested: trigger=\(trigger.name, privacy: .public), fallbackPolicy=\(trigger.fallbackPolicy.rawValue, privacy: .public)"
)
```

## Sensitive Data

Never log:

- selected text or any `SelectionContext.text` value;
- clipboard item contents or restored pasteboard bytes;
- translation input or output;
- plugin configuration values or runtime results;
- API keys, Keychain secrets, authorization headers, or request bodies;
- temporary file, pipe, or process payload contents.

Errors should expose a stable enum, code, or type. Do not stringify an error if
its description can contain user text, configuration, secrets, or response
bodies.

## Review

Before commit, search changed logging code for sensitive model fields and verify
that every `.public` interpolation is structural metadata. Existing product
verification remains authoritative; do not add a separate logging framework or
an empty test target.
