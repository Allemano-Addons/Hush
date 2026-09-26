# Hush module API

Modules are separate addons with `## Dependencies: Hush` and use the global `Hush` table.
The API grows during 0.1.x. This file is completed in the final step.

## Available now

| Function | Description |
|---|---|
| `Hush.apiVersion` | API version number (currently `1`). |
| `Hush.GetVersion()` | Hush version string. |
| `Hush.IsReady()` | `true` after `PLAYER_LOGIN`, once saved data is loaded. |
| `Hush.RegisterCallback(event, fn, owner)` | Listen to a Hush event. `fn(event, ...)`. |
| `Hush.UnregisterCallback(event, owner)` | Remove all listeners for `event` registered by `owner`. |

## Events

| Event | Arguments |
|---|---|
| `READY` | – (saved data loaded, UI can be built) |
