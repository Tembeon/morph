# Context boundary ground

Base65b080d3, owner WIP from prior input-ownership artifacts untouched. No native/device/GUI run. Installed public SDK and own repository source only.

Source supplies WidgetBuilder, but its call happens below root popup policy mount. It currently inherits root themes and root system environment; source-local themes vanish. Initial6 checks reproduce4failures and2passes. Expanded9 checks reproduce5failures and4passes. Logs initial-before and expanded-before are pre-implementation, same production prototype. Framework compiles/runs, no harness-only compile failure included.

Recorded live-local theme requirement is source-control fact, not a new arbitrary API. The planned SDK capture needs a real source dependency bridge; capture itself is nonreactive. Root MediaQuery, locale/delegates and direction must remain live; arbitrary page services stay below their page unless explicitly provided to builder. No wholesale context cloning.

Test usage stays ProbeMenuSource(menuBuilder: (popupContext) => editor). Data first: captured theme snapshot belongs to each presentation; source alone may refresh it while mounted; publisher must not setState on popup during a sibling source build or update an obsolete route. Fixed theme kinds or a bounded topology limitation must be explicit.

Throughput: parent owns tests/code, independent read-only design roles; no shared writers, no multiple heavy jobs. Prototype only. Existing motion/time/tuning/reference fixtures remain exact. Accessibility semantics and geometry are separate claims and do not close from inherited-context tests.
