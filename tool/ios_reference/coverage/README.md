# Native coverage inventory

- `catalog.json`: the families a complete Liquid Glass UI kit needs (58),
  including the ones morph does not have yet (text input, pickers, sidebar,
  refresh control, swipe actions, collection, system adapters). A roadmap,
  not a fidelity record; each family's passport in `../spec/` holds the
  measurements.

The public API itself (every exported name with its signature, parameters and
defaults) is `test/api/public_api.txt`, written by `tool/api/public_api.dart`
and checked by `test/api/public_api_test.dart`:

```sh
dart run tool/api/public_api.dart > test/api/public_api.txt
```
