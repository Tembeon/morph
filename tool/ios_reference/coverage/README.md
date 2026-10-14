# Native coverage inventory

- `catalog.json`: the families a complete Liquid Glass UI kit needs (58),
  including the ones morph does not have yet (text input, pickers, sidebar,
  refresh control, swipe actions, collection, system adapters). A roadmap,
  not a fidelity record; each family's passport in `../spec/` holds the
  measurements.
- `export_api.dart`: prints the resolved public API (exports, constructors,
  parameters, defaults) as JSON. The gallery coverage test uses it to find
  public API the gallery does not show.

```sh
dart run tool/ios_reference/coverage/export_api.dart > /tmp/morph-api.json
```
