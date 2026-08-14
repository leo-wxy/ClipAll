# Configuration And Lifecycle Inventory

## Current Ownership

- `PluginConfigurationStore` persists non-secret values in UserDefaults under
  `pluginID + fieldID`, merges descriptor defaults, validates field/value types,
  filters secret and stale descriptor fields, and owns reset/unregister/remove
  (`ClipAll/Infrastructure/Persistence/PluginConfigurationStore.swift:23-125`).
- `PluginSecretStore` stores values in Keychain using service
  `com.wxy.ClipAll.plugin-config` and account `<pluginID>.<fieldID>`
  (`ClipAll/Infrastructure/Security/PluginSecretStore.swift:25-93`).
- The configuration form already renders built-in and external descriptor fields
  through one UI; non-secret write errors are currently swallowed with `try?`, while
  secret fields display Keychain results
  (`ClipAll/Features/PluginConfiguration/PluginConfigurationForm.swift:1-195`).

## Current Consumers

- Search and Translation read concrete fields directly from the Store.
- `SelectionOverlayStore` separately reads the Translation target language.
- `ExternalPluginExecutor` and `PluginDebugSession` both convert
  `resolvedValues(pluginID:)` into Runtime configuration maps.
- Lifecycle owns register/unregister and is the correct place to coordinate plugin
  package state with configuration state.

## Residual Data Finding

- The uninstall UI defaults `removesConfiguration` to false, so uninstall normally
  leaves UserDefaults values behind
  (`PluginsSettingsView.swift:655-680`).
- When deletion is selected, lifecycle only calls
  `PluginConfigurationStore.removeData(pluginID:)`; it never deletes Keychain data
  (`PluginLifecycleController.swift:251-278`).
- `PluginSecretStore` only has per-field deletion; no pluginID-wide cleanup exists.

## Minimal Direction

- Reuse `PluginConfigurationStore`; do not add another service, protocol, cache, or
  persistence model.
- Keep built-in Swift consumers on the existing typed Store reads; they already share
  the same pluginID isolation and persistence semantics. Only Runtime snapshot
  consumers need the resolved environment map.
- Keep field-level settings writes and existing descriptor/type validation.
- Keep secret out of Runtime and expose it only to trusted native code through the
  existing Keychain store.
- Disable and upgrade retain configuration. Installed-plugin uninstall always removes
  package, ordinary configuration, plugin state references, and all Keychain entries
  belonging to the exact pluginID. The uninstall UI no longer offers preservation.
- Keychain does not support account-prefix deletion directly. Cleanup must enumerate
  attributes under the fixed service, filter accounts with the exact
  `<pluginID>.` boundary, then delete exact accounts. Because external v2 still cannot
  declare secret fields, secret cleanup can run before package mutation; a failure
  aborts uninstall without creating a partial managed/package state.
