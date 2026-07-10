## [0.4.0] - 2026-07-10

### 🚀 Features

- *(Breeze.Server)* Support alt_screen option
- *(Breeze.ErrorView)* Add crash detail clipboard export
- *(Breeze.Blocks)* Add textarea input and enhanced keyboard support
- *(Breeze.View)* Add switch_theme and cycle_theme functions
- *(Breeze.Storybook)* Add theme switching shortcuts
- *(Breeze.Server)* Support running apps from IEx
- *(Breeze.Blocks)* Add table component
- *(input)* Support focused implicit key capture
- *(Breeze.Server)* Support deferred renders from event replies
- *(Breeze.Blocks)* Add navigable tree component
- *(Breeze.Blocks)* Add virtual tree rendering support
- *(Breeze.Inspector)* Adds render tree inspection
- *(Breeze.Inspector)* Try to start distributed erlang on launch
- *(Breeze.Server)* Allow passing `render_errors` module
- *(Breeze.Style)* Add a square border variant
- *(Breeze.Flash)* Add stackable flash messages
- *(Breeze.Markdown)* Support custom reset sequences
- *(Breeze.Server)* Keep focus on focusable live roots
- *(Breeze.View)* Add put_implicit function for setting state
- *(Breeze.Server)* Add live child snapshot and input APIs
- *(Breeze.Blocks)* Virtualize list and table rendering
- *(Breeze.Implicit)* [**breaking**] Require init/3 callback
- *(Breeze.Server)* Supervise live views per Breeze session
- *(Breeze.Logger)* Add supervised capture and inspector logs
- *(Breeze.IO)* Naive alias of IO to allow IO.inspect, etc.

### 🐛 Bug Fixes

- *(Breeze.Theme)* Ensure theme probe runs if system theme is used
- *(Breeze.Server)* Pass root metadata to reload option refresh
- *(Breezer.Server)* Animation flicker in frame composer
- *(Breeze.Server)* Preserve inspector row repair for overlays
- *(Breeze.Server)* Render decorations in viewport
- Handle ctrl-c and shift-tab input sequences
- *(Breeze.ErrorView)* Ensure "q" quits inside of crash handler
- *(Breeze.Server)* Preserve private-use glyphs in server output
- *(input)* Honor F10 global stop keybindings
- *(Breeze.Template)* Apply declared component defaults and local helpers
- *(Breeze.Input)* Handle multi-grapheme printable paste input
- *(Breeze.Template)* Preserve root caller assigns for nested components
- *(Breeze.ChildServer)* Route preview mouse events through live children
- *(Breeze.Renderer)* Preserve live child patch origins
- *(Breeze.LoggerHandler)* Normalize Unicode logger chardata
- *(Breeze.KeyDecoder)* Support Escape keybind
- *(Breeze.Renderer)* Keep screen dim default fills compact
- *(Breeze.Renderer)* Ensure compatibility with back_breeze 0.4.1
- *(Breeze.Renderer)* Preserve live child and overlay dimensions
- *(Breeze.Input)* Centralize printable key handling
- *(Breeze.Renderer)* Stabilize overlays and animation scheduling
- *(Breeze.Style)* Normalize invalid border values
- *(Breeze.Server.RenderTracking)* Bind ETS state to server lifetime
- *(Breeze.RemoteInspector)* Fix tab width and palette viewport
- *(Breeze)* Replace first argument of handle_event with :input

### 🚜 Refactor

- *(Breeze.Server)* Split runtime state helpers
- *(Breeze.Storybook)* Remove missing story inventory
- *(Breeze.Router)* [**breaking**] Remove routing helpers
- *(Breeze.Theme)* [**breaking**] Internalize built-in theme constructors
- *(Breeze.Storybook)* [**breaking**] Promote the browser to the public entrypoint

### 📚 Documentation

- *(README.md)* Update for v0.3.0
- *(README.md)* Fix example
- *(Breeze.Docs.Assets)* Use Cascadia mono for consistent docs
- Restructure documentation to be more user friendly
- *(guides)* Add some guides for building a breeze todo list

### ⚡ Performance

- *(Breeze.Template)* Streamline slot evaluation

### 🧪 Testing

- Fix intermittent test failures in CI
- *(Breeze.Storybook)* Fix race condition in tests
- *(Breeze.Storybook)* Explicitly start each story under test
- *(RemoteInspector)* Fix remove inspector and debug test races
- *(posting)* Update test for CI
- *(examples/docs)* Hide __functions__

### ⚙️ Miscellaneous Tasks

- Update ssh demos
- *(ci)* Ignore formatting
- *(Breeze.Server)* Document start opts and remove internal options
- Fix elixir 1.20 compilation errors
- Add CHANGELOG.md
- Fix elixir 1.20 compilation error
- Update posting_benchmarks to use latest breeze state
## [0.3.0] - 2026-04-17

### 🚀 Features

- *(Breeze.Template)* Add internal ~H template runtime
- *(Breeze.HTMLFormatter)* Add mix format plugin for ~H
- *(viewport)* Add structured scroll modifiers and viewport metrics
- *(listview)* Add built-in implicit for keyboard list navigation
- *(Breeze.Implicit)* Move List and Scroll into implicit namespace
- *(Breeze.Blocks)* Implement predefined components using implicits
- *(Breeze.Renderer)* Support grid with apply_style
- *(Breeze.Renderer)* Support rounded borders
- *(Breeze.Markdown)* Support rendering markdown text
- *(Breeze.ChildServer)* Support nested views
- *(Breeze.Server)* Allow child servers to update async
- *(Breeze.Router)* Add a helper module to support routing
- *(Breeze.Logger)* Add a Breeze.View for logging
- *(Breeze.Implicit.Tab)* Add a tabs implicit
- *(Breeze.Server)* Support global keybindings
- *(Breeze.Implicit.Modal)* Add a modal component
- *(Breeze.Server)* Split rendering from lifecycle
- *(Breeze.Test)* Module for snapshot testing
- *(Breeze.Implicit.Dropdown)* Add dropdown menu implicit
- *(Breeze.Implicit.Input)* Add input implicit and overlays
- *(Breeze.Mouse)* Add mouse support for views
- *(Breeze.Server)* Route terminal input through InputRouter
- *(Breeze.Renderer)* Support fixed positioning
- *(Breeze.Debug)* Emit render profiling through telemetry
- *(Breeze.Blocks)* Update modal to use fixed positioning
- *(Breeze.Server)* Render a crash screen on view failures
- *(Breeze.InputRouter)* Support hup signal for SSH support
- *(Breeze.Server)* Add live reload support
- *(Breeze.Style)* Support both inline text styles and map overrides
- *(Breeze.Theme)* Add semantic theme support
- *(Breeze.Theme)* Add runtime system palette probing
- *(Breeze.Style)* Add semantic input styling and placeholders
- *(Breeze.Blocks)* Add public input block
- *(Breeze.Blocks)* Make  dropdown use semantic styling
- *(examples)* Update all examples to use border-box sizing
- *(Breeze.Inspector)* Add inspector overlay and coverage
- *(Breeze.RemoteInspector)* Add remote inspector app and task
- *(Breeze.Blocks)* Add underline tab variant
- *(Breeze.Renderer)* Add screen-dim backdrops for modals
- *(Breeze.Style)* Support gaps on grid
- *(Breeze.Storybook)* Add a storybook style widget viewer
- *(Breeze.Block)* Add a button component
- *(Breeze.Renderer)* Support focus-within for panels
- *(Breeze.Blocks.List)* Switch to faded out variant with indicator
- *(Breeze.Storybook)* Support variants on stories
- *(Breeze.KeyDecoder)* Decode structured ctrl key events
- *(Breeze.Storybook)* Add modal variants
- *(Breeze.Keybindings)* Add footer keybinding support
- *(Breeze.Renderer)* Support rich and virtual text content surfaces
- *(Breeze.View)* Support component attr and slot docs

### 🐛 Bug Fixes

- Tighten formatter whitespace handling and slot API docs
- *(examples)* Fix focus example
- *(Breeze.Server)* Prevent screen flickering on re-renders
- *(Breeze.Server)* Don't schedule input flush with no input
- *(Breeze.Implicit.Input)* Fix ctrl + w inserting gibberish
- *(Breeze.Debug)* Stop debug stats from repainting themselves
- *(Breeze.Server)* Write patched rows before clearing the remainder
- *(Breeze.Server)* Clear patched row remainder after content
- *(Breeze.Blocks)* Use background color for modal surfaces
- *(Breeze.Theme)* Retry system probes and preserve probed surfaces
- *(Breeze.Implicit.Input)* Ensure implicit keys handled first
- *(Breeze.Server)* Batch printable input bursts safely
- *(Breeze.Server)* Patch live children from their root viewport
- *(Breeze.Keybindings)* Match ctrl bindings against decoded key events
- *(Breeze.Storybook)* Stabilize preview and support file loading

### 💼 Other

- *(Breeze.Implicit.Input)* Render wide characters by cell width
- 0.3.0

### 🚜 Refactor

- *(Breeze.Renderer)* Remove NimbleParsec and render tree directly
- *(Breeze.ChildServer)* Extract common functionality with Server
- *(Breeze.Input)* Make input styling class-driven

### 📚 Documentation

- Add Phoenix LiveView prior-art links
- Generate built-in component previews

### ⚡ Performance

- *(Breeze.Renderer)* Remove implicit reconcile callbacks
- *(Breeze.Server)* Reduce redraw flicker
- *(Breeze.Server)* Patch fixed live child invalidations
- *(Breeze.Server)* Patch frame rows and resync on sigwinch
- *(Breeze.ChildServer)* Retain hidden implicit state across remounts

### 🧪 Testing

- *(Breeze.Template)* Expand template and formatter coverage
- *(docs)* Update snapshots for the docs test
- *(Breeze.Server)* Fix snake example
- *(posting)* Add a snapshot test for the open modal

### ⚙️ Miscellaneous Tasks

- Remove phoenix_live_view dependency
- *(Breeze.Template)* Use eval_quoted for bindings
- Add locals_without_parens to formatter
- *(.github)* Ci workflow
- *(.ci)* Remove branches from triggers
- Add a posting example to show off a complicated UI
- Update back_breeze
- Upgrade back_breeze to support render cache
## [0.2.1] - 2025-05-23

### 💼 Other

- 0.2.1

### ⚙️ Miscellaneous Tasks

- Upgrade termite and live_view
## [0.2.0] - 2024-08-09

### 🚀 Features

- *(Breeze.Server)* Add focusable elements
- *(Breeze.Server)* Allow passing change events from implicit
- *(Breeze.Server)* Add handle_modfiers for implicits

### 💼 Other

- 0.2.0
## [0.1.0] - 2024-06-13

### ⚙️ Miscellaneous Tasks

- Initial setup
