## [0.5.0] - 2026-07-30

### Features

- *(Breeze.Theme)* Add commander built in theme ([de7cd80](https://github.com/gazler/breeze/commit/de7cd80a3f0496bb7b805d11996d96fbcb30e570))
- *(Breeze.Implicit.Dropdown)* Add mouse support ([e7080a2](https://github.com/gazler/breeze/commit/e7080a2a0c1e3fc5059155a1910a7e322f7bf1bb))
- *(Breeze.Storybook)* Show keybindings bar and allow details toggle ([9bb5b91](https://github.com/gazler/breeze/commit/9bb5b91fad481cf8e6e262fb8b09bc295c83d47c))
- *(Breeze.Style)* Support responsive breakpoint ([b709f7d](https://github.com/gazler/breeze/commit/b709f7d8010b5d7db4eae47ca8d1578ca8aeb0ce))
- *(Breeze.RemoteInspector)* Add custom pages ([b905fba](https://github.com/gazler/breeze/commit/b905fbadbab7725043a114502bd4d5e1a66fa929))
- *(Breeze.Runtime)* Add state transfer and lifecycle hooks ([069adb0](https://github.com/gazler/breeze/commit/069adb0909369de1effd740d42a66875f6df3694))
- *(Breeze.Implicit)* Make key batching opt-in ([fe4ed94](https://github.com/gazler/breeze/commit/fe4ed94ac0d504e5ae5ba8d3249b7e553966aa64))
- *(Breeze.Server.Error)* Support hard restarts with "R" ([74f5ac1](https://github.com/gazler/breeze/commit/74f5ac1ec57eac4f138028b13fa07f27147f1bc7))
- *(Breeze.ChildServer)* Pass focus target on click events ([0ad953f](https://github.com/gazler/breeze/commit/0ad953f3df2f244178704afb21bec35f32508dc3))
- [**breaking**] Standardize mouse event payloads ([b1b948d](https://github.com/gazler/breeze/commit/b1b948d0d500755f6bc7911002ddaaf715d4348c))
- *(Breeze.Style)* Support tailwind style classes ([80e10ba](https://github.com/gazler/breeze/commit/80e10ba1e386aae617a6c3fea09b1e7444c50a82))
- *(Breeze.Style)* Support max-height utilities ([a179c48](https://github.com/gazler/breeze/commit/a179c48469a171d1598e4010a7b10f38feac6e21))
- *(Breeze.Storybook)* Add mix task for running storybook ([4eaa052](https://github.com/gazler/breeze/commit/4eaa052e8f240bfbaa75817ac36193f9f7ebb5ef))
- *(Breeze.Theme)* Add a greenscreen theme which only uses 2-colors ([00efa02](https://github.com/gazler/breeze/commit/00efa0219f47e65f5b0cbb25caaa1b1e5dbb116d))
- *(Breeze.Blocks)* Add opt-out indicator to panel ([9c7640c](https://github.com/gazler/breeze/commit/9c7640c4b76535af9a5e9eb79d29b4dbba503ea4))
- *(Breeze.Blocks)* Add a checkbox function component ([1711ebf](https://github.com/gazler/breeze/commit/1711ebfdd1f456ae1aa65f91edfdc9b8bcc932ea))
- *(Breeze.Blocks)* Lazily render virtual list rows ([c7c993d](https://github.com/gazler/breeze/commit/c7c993dff1cc5e623c275897597798ccace3cea7))
- *(Breeze.InputRouter)* Clean up terminal on mix run ([31d67d0](https://github.com/gazler/breeze/commit/31d67d0b72578d2636e924bb4c74da9bb2e058a8))

### Bug Fixes

- *(Breeze.InputRouter)* Harden IEx shell proxy and palette probes ([b04815e](https://github.com/gazler/breeze/commit/b04815e3cbc5c69cb03e36232ca22a5c46ec5b06))
- *(Breeze.Implicit.Dropdown)* Prevent open menus from expanding panels ([5e40f7d](https://github.com/gazler/breeze/commit/5e40f7dae3ccb721bf1cf443d000387283d99dec))
- *(Breeze.Implicit)* Don't emit change events on internal changes ([07c0ca0](https://github.com/gazler/breeze/commit/07c0ca0888b30a5b705cf3326dfa914344ae323c))
- *(Breeze.Server)* Ensure live viewports position nests correctly ([68078f2](https://github.com/gazler/breeze/commit/68078f23579242050319f95892e323812d39b2e3))
- *(Breeze.Server)* Ensure server struct has less than 32 keys ([ac9612e](https://github.com/gazler/breeze/commit/ac9612e1ad8488674d89d5c33285f2c26e7299f5))
- *(Breeze.Markdown)* Use TextSpans to ensure background color on code ([7b539b7](https://github.com/gazler/breeze/commit/7b539b7483ffb02bcaa2c15553a0a79dcf61e3dc))
- *(Breeze.Renderer)* Ensure screen dimming works on system theme ([9296cd8](https://github.com/gazler/breeze/commit/9296cd8241795197fdf8a75b734210edbd811231))
- *(Breeze.Implicit.Tree)* Scroll to externally controlled selection ([950cb47](https://github.com/gazler/breeze/commit/950cb47cfa751fcd57b5abb5ccfa63d75ab40b34))
- *(Breeze.Implicit.List)* Scroll to externally controlled selection ([d4d8220](https://github.com/gazler/breeze/commit/d4d8220ac1ac26ef18476cc3ce28124d3a3d8ad6))
- *(Breeze.Server)* Revent stale overlay state in child patches ([c983541](https://github.com/gazler/breeze/commit/c983541e200a640e1f09061928ff4cfd63d29cc2))
- *(Breeze.CodeReloader)* Only watch paths that exist ([226bb2e](https://github.com/gazler/breeze/commit/226bb2e43695a42f74df5fdb2fab5248c86d993f))
- *(Breeze.ChildServer)* Ensure mouse clicks work on overlapping boxes ([84e2e56](https://github.com/gazler/breeze/commit/84e2e5674a6091622cb9379331c471a7ba30186d))
- *(Breeze.Template)* Require static implicit modules ([bbfe139](https://github.com/gazler/breeze/commit/bbfe139077ef3f978fcab907cd7e73d5bdf550e6))
- *(Breeze.Style)* Ignore unresolved class colors ([0f156db](https://github.com/gazler/breeze/commit/0f156db74ec743c24ef8857646ffa21138ff2b38))
- *(Breeze.Server)* Ensure focused live child input is sync ([fac9231](https://github.com/gazler/breeze/commit/fac92311668f728873fe4d4f0de00e65b90b6439))
- *(Breeze.Server)* Ensure focus move rerenders patches base view ([4c72fe6](https://github.com/gazler/breeze/commit/4c72fe64752530e9e5ad0c342a56b55a308c194f))
- *(Breeze.Implicit.List)* Preserve visible rows on controlled list selection ([940bca2](https://github.com/gazler/breeze/commit/940bca2771d530e1bcceda77358567247643b36c))
- *(Breeze.Inspector)* Disable inspector reload without a watcher ([27429b9](https://github.com/gazler/breeze/commit/27429b90d53f4d1e8ec11c60a583ae27fba99fca))
- *(Breeze.InputRouter)* Restore terminal state on terminate ([fb4d791](https://github.com/gazler/breeze/commit/fb4d791ab8854a0214baa31217ace7524ee904b1))

### Refactor

- *(Breeze.Theme)* Move all of the theme probe functions out ([8088d14](https://github.com/gazler/breeze/commit/8088d141f004badd587ad161688700b26382f276))
- *(Breeze.Implicit)* [**breaking**] Require tagged init results ([274844f](https://github.com/gazler/breeze/commit/274844fe7dda2e28fc2f79300febbe2b665f6c91))
- *(Breeze.Telemetry)* Wrap :telemetry to allow disabling ([4ccf506](https://github.com/gazler/breeze/commit/4ccf506b365d10a27e90a222f8348c74ecc005fb))
- *(Breeze.View)* Separate components from views ([152e92f](https://github.com/gazler/breeze/commit/152e92f3f4052d10c7c226109000656498d3898a))

### Documentation

- *(Breeze.Implicit)* Improve typespecs for implicit dogs ([a203847](https://github.com/gazler/breeze/commit/a203847dd30c89b4dad3e75083fb8c9a99687610))
- Add SSH and Fly.io deployment guides ([5afe9fe](https://github.com/gazler/breeze/commit/5afe9fed2f15d9824fe369b3ea7787f7147c0093))
- *(guides)* Remove some unnecessary guide content ([8f8e7c5](https://github.com/gazler/breeze/commit/8f8e7c571d5f771a0fd803f2850314bd891a730d))

### Performance

- *(Breeze.ChildServer)* Only perform implicit bootstrap once ([6d51846](https://github.com/gazler/breeze/commit/6d51846bde08997f62514bccdd8b410034ba1440))
- *(Breeze.RemoteInspector)* Collapse snapshots on interval ([e26c951](https://github.com/gazler/breeze/commit/e26c9513d9fe4b49b26f119e52e0206885c60586))
- *(Breeze.Renderer)* Skip unused live viewport prepass ([bdff1ba](https://github.com/gazler/breeze/commit/bdff1ba71102bb434e6414589c212660afbb7e8b))
- *(Breeze.Template)* Precompile elixir expressions ([f94f001](https://github.com/gazler/breeze/commit/f94f001ed1442311d01bead233fee14d17d4d99f))
- *(Breeze.Server.Frame)* Compare frame rows in linear time ([8eb36b0](https://github.com/gazler/breeze/commit/8eb36b0e23c4ca91b00f15ee24b3f628430de371))
- *(Breeze.Renderer)* Prepend focusables ([0f15fa5](https://github.com/gazler/breeze/commit/0f15fa5010dbb8b481d103c3c6e8b9326e72415d))
- *(Breeze.Logger.Collector)* Store entries in a bounded queue ([2c7a7e8](https://github.com/gazler/breeze/commit/2c7a7e8b08466095bff0478204cf9d2154739dfa))
- *(Breeze.RemoteInspector)* Store logs in bounded queues ([0d41790](https://github.com/gazler/breeze/commit/0d417907281f60eabdba2e3b54d3b3f22beadaff))
- *(Breeze.Implicit.Textarea)* Optimize multiline wrapping ([faac95b](https://github.com/gazler/breeze/commit/faac95b119afa2c1a396865361e3ec8d3680d91f))
- *(Breeze.Server)* Benchmark input CPU across all examples ([015d007](https://github.com/gazler/breeze/commit/015d007c053e898432fc3e1d875d0caccaba436d))
- *(Breeze.ChildServer)* Detect deferred input routing changes ([fe7232c](https://github.com/gazler/breeze/commit/fe7232c4c0df6574e5afcd7a0d5158d6c9b31d89))
- *(Breeze.Server)* Pace input renders at 60 fps ([68b1bb0](https://github.com/gazler/breeze/commit/68b1bb0048a8218e2d1518a759c193c9845b800e))

### Testing

- *(Breeze.InputRouterThemeSyncTest)* Fix aliases ([6ef0714](https://github.com/gazler/breeze/commit/6ef0714deb7d12c6c792876b44865a1840f86a69))
- Improve test suite robustness on slower machines ([69856d2](https://github.com/gazler/breeze/commit/69856d223d500b1ddd67feaf104322cacfcbb3ac))
- *(Breeze.LiveView.CrashTest)* Increase assert timeout ([1679d33](https://github.com/gazler/breeze/commit/1679d33bc699cc7771152477d2a52c5e1051a348))
- Fix flaky tests on process shutdown ([66d58d7](https://github.com/gazler/breeze/commit/66d58d73fe996778f70a9baa51917686f1df1747))
- *(ExampleSnapshotTest)* Add animated progress snapshot tests ([0a1418b](https://github.com/gazler/breeze/commit/0a1418b6cb83fd032fe5e081402379cf141434f7))
- *(Breeze.ChildServer)* Supervise processes and speed up test runs ([ccae31f](https://github.com/gazler/breeze/commit/ccae31f9afd291e473987a19f66ad978e4856d6d))
## [0.4.0] - 2026-07-10

### Features

- *(Breeze.Server)* Support alt_screen option ([dd01684](https://github.com/gazler/breeze/commit/dd0168472fb500b610dda777b93ef9f753b7aabc))
- *(Breeze.ErrorView)* Add crash detail clipboard export ([b450cd4](https://github.com/gazler/breeze/commit/b450cd468ea88730d4ab6698726118abd1dbaa9e))
- *(Breeze.Blocks)* Add textarea input and enhanced keyboard support ([1289183](https://github.com/gazler/breeze/commit/1289183d38e32d8d253d7efdf0c1b91299667f70))
- *(Breeze.View)* Add switch_theme and cycle_theme functions ([21ca652](https://github.com/gazler/breeze/commit/21ca652715b4adc8218bb188bbfc6d9abcea89b9))
- *(Breeze.Storybook)* Add theme switching shortcuts ([f9b7ac5](https://github.com/gazler/breeze/commit/f9b7ac571bebf302f63af19e31e975a9a7a9b32c))
- *(Breeze.Server)* Support running apps from IEx ([e4ac814](https://github.com/gazler/breeze/commit/e4ac814b300fa53101e22a23890955ed2f287d63))
- *(Breeze.Blocks)* Add table component ([bf34487](https://github.com/gazler/breeze/commit/bf34487217af56b582c99db4d9f22c6d4040c313))
- *(input)* Support focused implicit key capture ([520024d](https://github.com/gazler/breeze/commit/520024d66f604664e26dd573e35032b73481c9b2))
- *(Breeze.Server)* Support deferred renders from event replies ([1aea00b](https://github.com/gazler/breeze/commit/1aea00bc162047bb7926e19b6eb70ece6349df4c))
- *(Breeze.Blocks)* Add navigable tree component ([885a303](https://github.com/gazler/breeze/commit/885a30318b8abe73283ad7b4dfe21f7671b4b4a8))
- *(Breeze.Blocks)* Add virtual tree rendering support ([f651545](https://github.com/gazler/breeze/commit/f651545fb99832b19e6ee6a18c0f0edfc261e850))
- *(Breeze.Inspector)* Adds render tree inspection ([9842fb6](https://github.com/gazler/breeze/commit/9842fb609f13cd61431b778f374d290a5a2de426))
- *(Breeze.Inspector)* Try to start distributed erlang on launch ([f2dba56](https://github.com/gazler/breeze/commit/f2dba56ae0dffcf194b6da4be6639d68fa340aa7))
- *(Breeze.Server)* Allow passing `render_errors` module ([790f66b](https://github.com/gazler/breeze/commit/790f66b35dabc6a029de86543e33f1f2f1735a59))
- *(Breeze.Style)* Add a square border variant ([57beec9](https://github.com/gazler/breeze/commit/57beec945ebaeee1be3162b633f0318cd18133c3))
- *(Breeze.Flash)* Add stackable flash messages ([b0dbc54](https://github.com/gazler/breeze/commit/b0dbc5458859ebd88de81343a08346ee1add0a74))
- *(Breeze.Markdown)* Support custom reset sequences ([526bff4](https://github.com/gazler/breeze/commit/526bff4885621d1add97d16137a179e9188fa511))
- *(Breeze.Server)* Keep focus on focusable live roots ([6fedca4](https://github.com/gazler/breeze/commit/6fedca4ddaf4df6afed6a161579e142d99b6e195))
- *(Breeze.View)* Add put_implicit function for setting state ([dd0c9f2](https://github.com/gazler/breeze/commit/dd0c9f22e3185c9bf64f66c662457c278bb1c606))
- *(Breeze.Server)* Add live child snapshot and input APIs ([8357b3a](https://github.com/gazler/breeze/commit/8357b3a85de07a4914024da2627fe684a70e2709))
- *(Breeze.Blocks)* Virtualize list and table rendering ([63cd22e](https://github.com/gazler/breeze/commit/63cd22e4b77b79130eac0a6d34878472f489b608))
- *(Breeze.Implicit)* [**breaking**] Require init/3 callback ([dc9bdc0](https://github.com/gazler/breeze/commit/dc9bdc01a45863ce8c84b4415c9a36a21ab75afe))
- *(Breeze.Server)* Supervise live views per Breeze session ([6715665](https://github.com/gazler/breeze/commit/6715665264441b5d0c1fa23a45421588918618d6))
- *(Breeze.Logger)* Add supervised capture and inspector logs ([ee40315](https://github.com/gazler/breeze/commit/ee403153493326809b7ba4e90f16971432bcbf74))
- *(Breeze.IO)* Naive alias of IO to allow IO.inspect, etc. ([10323c7](https://github.com/gazler/breeze/commit/10323c7e9f7253a2c86b4fb85bae6427017af8f2))

### Bug Fixes

- *(Breeze.Theme)* Ensure theme probe runs if system theme is used ([1ca5265](https://github.com/gazler/breeze/commit/1ca52654879274311a934515cde7a870ffef6b9d))
- *(Breeze.Server)* Pass root metadata to reload option refresh ([1b4db32](https://github.com/gazler/breeze/commit/1b4db3291b82dab874c6ae20bc3dedc564336a61))
- *(Breezer.Server)* Animation flicker in frame composer ([73bbce2](https://github.com/gazler/breeze/commit/73bbce29ff0c43ff4a85ac1a5b382c1d52768866))
- *(Breeze.Server)* Preserve inspector row repair for overlays ([62f5880](https://github.com/gazler/breeze/commit/62f58809c6d4b94df157b3267a39f6bdb2874a1a))
- *(Breeze.Server)* Render decorations in viewport ([a526e27](https://github.com/gazler/breeze/commit/a526e277612616a867ae7e4b2c5c4eec8ad9b30a))
- Handle ctrl-c and shift-tab input sequences ([7021d9f](https://github.com/gazler/breeze/commit/7021d9f7f7f9ff3a13cd42f62a079b6f7d20a698))
- *(Breeze.ErrorView)* Ensure "q" quits inside of crash handler ([454aa7c](https://github.com/gazler/breeze/commit/454aa7ccd46a9cef2ceb1af7e9a8e5b9c678a42a))
- *(Breeze.Server)* Preserve private-use glyphs in server output ([d4c0520](https://github.com/gazler/breeze/commit/d4c05200a87d12f1db681dc06d3400546c3ed56e))
- *(input)* Honor F10 global stop keybindings ([4827108](https://github.com/gazler/breeze/commit/4827108b76777b1e2523487cb36d17c77371c1ed))
- *(Breeze.Template)* Apply declared component defaults and local helpers ([ed08f66](https://github.com/gazler/breeze/commit/ed08f66b54f63512537a01ac8890ebc5fabfdc78))
- *(Breeze.Input)* Handle multi-grapheme printable paste input ([b58d205](https://github.com/gazler/breeze/commit/b58d20517b54a3dc2627179dd3d02c04074931f2))
- *(Breeze.Template)* Preserve root caller assigns for nested components ([e418988](https://github.com/gazler/breeze/commit/e4189886fa3c6ffdb084799a0178b0df0762c56e))
- *(Breeze.ChildServer)* Route preview mouse events through live children ([7ce68c9](https://github.com/gazler/breeze/commit/7ce68c9e057c6320a30dfd97d0296b4236427575))
- *(Breeze.Renderer)* Preserve live child patch origins ([993cf99](https://github.com/gazler/breeze/commit/993cf99d8ce3ae91ae788eb9d7576b1dc06c6f77))
- *(Breeze.LoggerHandler)* Normalize Unicode logger chardata ([a05a69d](https://github.com/gazler/breeze/commit/a05a69de2ad61165ef80a7442e15b1ca8ebd517f))
- *(Breeze.KeyDecoder)* Support Escape keybind ([0878883](https://github.com/gazler/breeze/commit/0878883787311d62379a3f350aa6135ee4f814bc))
- *(Breeze.Renderer)* Keep screen dim default fills compact ([742610e](https://github.com/gazler/breeze/commit/742610e00c54327b57054c8cf84a006fc941a1a1))
- *(Breeze.Renderer)* Ensure compatibility with back_breeze 0.4.1 ([953f55a](https://github.com/gazler/breeze/commit/953f55aaac8fcb3867f48b2cfc4b69262bef86c3))
- *(Breeze.Renderer)* Preserve live child and overlay dimensions ([8ed3d68](https://github.com/gazler/breeze/commit/8ed3d68ddd007a38e2bd28426e28d559e56caddd))
- *(Breeze.Input)* Centralize printable key handling ([af68dcd](https://github.com/gazler/breeze/commit/af68dcd438af211b3aaac61ec972ce49fccfb1ed))
- *(Breeze.Renderer)* Stabilize overlays and animation scheduling ([e2e5b04](https://github.com/gazler/breeze/commit/e2e5b041b8750b7df42285650994dcc8e9b3505a))
- *(Breeze.Style)* Normalize invalid border values ([9c25c4c](https://github.com/gazler/breeze/commit/9c25c4c8b3c337dbe4255385746e373064e4d62f))
- *(Breeze.Server.RenderTracking)* Bind ETS state to server lifetime ([f587dc1](https://github.com/gazler/breeze/commit/f587dc1bfdc9bcca93c27b11407c1b7fa5ccd518))
- *(Breeze.RemoteInspector)* Fix tab width and palette viewport ([975d5f2](https://github.com/gazler/breeze/commit/975d5f2c49cba8b01d192eed001fe6d1758bf448))
- *(Breeze)* Replace first argument of handle_event with :input ([e40fc0d](https://github.com/gazler/breeze/commit/e40fc0d91438b4b0afcc302532668b0b67ec8a8d))

### Refactor

- *(Breeze.Server)* Split runtime state helpers ([317c7b9](https://github.com/gazler/breeze/commit/317c7b9b8899e1429f9c954d213f7f29bb5f6734))
- *(Breeze.Storybook)* Remove missing story inventory ([6f3d85d](https://github.com/gazler/breeze/commit/6f3d85d0c5cb4b7a00e45646c09424fec662be89))
- *(Breeze.Router)* [**breaking**] Remove routing helpers ([40646c0](https://github.com/gazler/breeze/commit/40646c0e2abc7659605a2afd43611b4488a8b158))
- *(Breeze.Theme)* [**breaking**] Internalize built-in theme constructors ([a654832](https://github.com/gazler/breeze/commit/a65483243e9bf6220059be4b778e2aec3877a100))
- *(Breeze.Storybook)* [**breaking**] Promote the browser to the public entrypoint ([2d3ad9c](https://github.com/gazler/breeze/commit/2d3ad9cdb27dff7e3875ab65e6db124673cfde35))

### Documentation

- *(README.md)* Update for v0.3.0 ([87b1206](https://github.com/gazler/breeze/commit/87b120685a327911164bb0a3d5ffbaeb5f65b690))
- *(README.md)* Fix example ([9ea136e](https://github.com/gazler/breeze/commit/9ea136ef4ed192954795d0613eb501c5a505243a))
- *(Breeze.Docs.Assets)* Use Cascadia mono for consistent docs ([d82af06](https://github.com/gazler/breeze/commit/d82af06a457995ff495cc74bab10a93eab8790c8))
- Restructure documentation to be more user friendly ([780fcf7](https://github.com/gazler/breeze/commit/780fcf7afdc4ef0a8557a69c6b703d132d796e97))
- *(guides)* Add some guides for building a breeze todo list ([84e54d7](https://github.com/gazler/breeze/commit/84e54d744ab3526f2009a8f12b1ba7c824acf54d))

### Performance

- *(Breeze.Template)* Streamline slot evaluation ([d4a284d](https://github.com/gazler/breeze/commit/d4a284d11b34928a5abc79fcca50ddb926b56236))

### Testing

- Fix intermittent test failures in CI ([9a59ebd](https://github.com/gazler/breeze/commit/9a59ebd2a32d8607277ea77c18b8a014211d2043))
- *(Breeze.Storybook)* Fix race condition in tests ([b6bd4e1](https://github.com/gazler/breeze/commit/b6bd4e1ac39361688941aba5699869240b8bd8e0))
- *(Breeze.Storybook)* Explicitly start each story under test ([939c420](https://github.com/gazler/breeze/commit/939c4200b019705b7f5553632bdb27a1e33493a0))
- *(RemoteInspector)* Fix remove inspector and debug test races ([b82383f](https://github.com/gazler/breeze/commit/b82383f3e9cd5d4c63f60a01d968613c2a91595b))
- *(posting)* Update test for CI ([6e62577](https://github.com/gazler/breeze/commit/6e6257779b4b3179ffaed3a631bf43cc268d5b91))
- *(examples/docs)* Hide __functions__ ([2277473](https://github.com/gazler/breeze/commit/227747307deb4e9cad2d4daa6ddef6b7964700a9))
## [0.3.0] - 2026-04-17

### Features

- *(Breeze.Template)* Add internal ~H template runtime ([ff0feec](https://github.com/gazler/breeze/commit/ff0feecd0bdb0808a1a4a941f018ce4956775f40))
- *(Breeze.HTMLFormatter)* Add mix format plugin for ~H ([d839908](https://github.com/gazler/breeze/commit/d8399087f9ef2dfb509bb8dc1bd13cd7094555d7))
- *(viewport)* Add structured scroll modifiers and viewport metrics ([a2aebd0](https://github.com/gazler/breeze/commit/a2aebd09b83b6170e95b006e25f053e09194ec4a))
- *(listview)* Add built-in implicit for keyboard list navigation ([5fd1071](https://github.com/gazler/breeze/commit/5fd1071d89e26fde811fd9d2db97a13fec4b3a2e))
- *(Breeze.Implicit)* Move List and Scroll into implicit namespace ([373c798](https://github.com/gazler/breeze/commit/373c798c9179139fc40fa0985da6ec8f1f8e096c))
- *(Breeze.Blocks)* Implement predefined components using implicits ([6f1fb97](https://github.com/gazler/breeze/commit/6f1fb97255a31afd32d1ffb49eb5a560825c38db))
- *(Breeze.Renderer)* Support grid with apply_style ([fbc3d7f](https://github.com/gazler/breeze/commit/fbc3d7f53e9afff27d1bc81f3c2bfdc647a6c4a7))
- *(Breeze.Renderer)* Support rounded borders ([19b9b74](https://github.com/gazler/breeze/commit/19b9b74a1503d54406a9e8f1b7c2c7c8301f0051))
- *(Breeze.Markdown)* Support rendering markdown text ([0a34d45](https://github.com/gazler/breeze/commit/0a34d456e9d6c61cc788cfcd49ffbdae3b21db19))
- *(Breeze.ChildServer)* Support nested views ([5a595d8](https://github.com/gazler/breeze/commit/5a595d8a7cd75a827dbc6ea7f7ddf411b13bfe0d))
- *(Breeze.Server)* Allow child servers to update async ([e271c28](https://github.com/gazler/breeze/commit/e271c28a131e440f22a5c09f0952ae59eb30b662))
- *(Breeze.Router)* Add a helper module to support routing ([b9f276a](https://github.com/gazler/breeze/commit/b9f276a2fdfb1b7db6e627a67f5b48024220692a))
- *(Breeze.Logger)* Add a Breeze.View for logging ([0055d05](https://github.com/gazler/breeze/commit/0055d05e5c9ad4a2659b93a4c5d0ab259b26e21e))
- *(Breeze.Implicit.Tab)* Add a tabs implicit ([de8b2d9](https://github.com/gazler/breeze/commit/de8b2d92d622926d239e7261f05fdb28bd85396c))
- *(Breeze.Server)* Support global keybindings ([c370667](https://github.com/gazler/breeze/commit/c37066707badbc1c60f405bb91c35ccfe1b23e48))
- *(Breeze.Implicit.Modal)* Add a modal component ([005fe4e](https://github.com/gazler/breeze/commit/005fe4e001021fc0171caf9f504a645e61380d0e))
- *(Breeze.Server)* Split rendering from lifecycle ([117a36d](https://github.com/gazler/breeze/commit/117a36d34b525ac9c193ce82f82eaa1488517a0b))
- *(Breeze.Test)* Module for snapshot testing ([82f0d64](https://github.com/gazler/breeze/commit/82f0d6430b782e70e56104f4ab37e936502459c1))
- *(Breeze.Implicit.Dropdown)* Add dropdown menu implicit ([c276563](https://github.com/gazler/breeze/commit/c276563018ee1ddd32eb883c3c0f6906eaa288b9))
- *(Breeze.Implicit.Input)* Add input implicit and overlays ([18267d6](https://github.com/gazler/breeze/commit/18267d6459a39b0aa1d37c4640a6e86a67f980a6))
- *(Breeze.Mouse)* Add mouse support for views ([1073239](https://github.com/gazler/breeze/commit/10732394e4edace195280e8cccd30636b8f38d88))
- *(Breeze.Server)* Route terminal input through InputRouter ([bbc026e](https://github.com/gazler/breeze/commit/bbc026e2bea98300838e6a20de574c52b6efd32d))
- *(Breeze.Renderer)* Support fixed positioning ([e12aff5](https://github.com/gazler/breeze/commit/e12aff5181f6bb289280f3e9b304981420938806))
- *(Breeze.Debug)* Emit render profiling through telemetry ([ad2a175](https://github.com/gazler/breeze/commit/ad2a1757236778e865e3c7e249ba84e602832109))
- *(Breeze.Blocks)* Update modal to use fixed positioning ([631140b](https://github.com/gazler/breeze/commit/631140bcc019f0f0276934b8301757f3d94f2dfd))
- *(Breeze.Server)* Render a crash screen on view failures ([7c2ee09](https://github.com/gazler/breeze/commit/7c2ee096a1645746822b1d396fdb03d716437d78))
- *(Breeze.InputRouter)* Support hup signal for SSH support ([a6314d6](https://github.com/gazler/breeze/commit/a6314d6b71b498f72cf7837348d75f8d9dcc914f))
- *(Breeze.Server)* Add live reload support ([85c3fdd](https://github.com/gazler/breeze/commit/85c3fdd131d2c949fb1dc41d1b286893caf265a0))
- *(Breeze.Style)* Support both inline text styles and map overrides ([51594d7](https://github.com/gazler/breeze/commit/51594d76f47efe7900624c4490dc417a6e9553ab))
- *(Breeze.Theme)* Add semantic theme support ([10b5092](https://github.com/gazler/breeze/commit/10b5092301bb6c30155bdb4c734db7ed7b7b4d29))
- *(Breeze.Theme)* Add runtime system palette probing ([43e7f51](https://github.com/gazler/breeze/commit/43e7f517f34a51880a66cda60968c20f7b522924))
- *(Breeze.Style)* Add semantic input styling and placeholders ([ac31c09](https://github.com/gazler/breeze/commit/ac31c09830c00e571e15412839db0e42f114d691))
- *(Breeze.Blocks)* Add public input block ([c1d5903](https://github.com/gazler/breeze/commit/c1d5903dcb26f1126aa248b37dda445bb4935152))
- *(Breeze.Blocks)* Make  dropdown use semantic styling ([de0d4f3](https://github.com/gazler/breeze/commit/de0d4f37e5951339b0e36751b21d451a206aa760))
- *(examples)* Update all examples to use border-box sizing ([a78864a](https://github.com/gazler/breeze/commit/a78864a034ad887364f294a2a5bb58317ec4e934))
- *(Breeze.Inspector)* Add inspector overlay and coverage ([1b727ba](https://github.com/gazler/breeze/commit/1b727ba2fdc9c71ead845236765e8c9a064859f8))
- *(Breeze.RemoteInspector)* Add remote inspector app and task ([6fe6d80](https://github.com/gazler/breeze/commit/6fe6d800e84ed3b26aee397ad742354e8601d865))
- *(Breeze.Blocks)* Add underline tab variant ([82eba0c](https://github.com/gazler/breeze/commit/82eba0caafdfd6cbe407db46694b2fe6f72a934d))
- *(Breeze.Renderer)* Add screen-dim backdrops for modals ([d9f9ffa](https://github.com/gazler/breeze/commit/d9f9ffa5f1708432020727a8e678a3aba5c0c0b6))
- *(Breeze.Style)* Support gaps on grid ([d956707](https://github.com/gazler/breeze/commit/d956707752a79b54d7fca54610b3399fa27d181c))
- *(Breeze.Storybook)* Add a storybook style widget viewer ([5f3ae7e](https://github.com/gazler/breeze/commit/5f3ae7e8c5129ea944ae379c4db1734d0ce613d5))
- *(Breeze.Block)* Add a button component ([56ceb8a](https://github.com/gazler/breeze/commit/56ceb8a680603b66b73718adf891b02c3ab53829))
- *(Breeze.Renderer)* Support focus-within for panels ([9727244](https://github.com/gazler/breeze/commit/97272440ba53a274f0c08f51e8f192f9334f80b5))
- *(Breeze.Blocks.List)* Switch to faded out variant with indicator ([3cfb1b5](https://github.com/gazler/breeze/commit/3cfb1b54755dc96c3f1245e3ae03edd25ee48231))
- *(Breeze.Storybook)* Support variants on stories ([f25d20e](https://github.com/gazler/breeze/commit/f25d20eb7372f5d9248b2919b38be00729130676))
- *(Breeze.KeyDecoder)* Decode structured ctrl key events ([044039b](https://github.com/gazler/breeze/commit/044039b318a2292cf0852089806743b803a85d5d))
- *(Breeze.Storybook)* Add modal variants ([6c38828](https://github.com/gazler/breeze/commit/6c38828a031b0d1caa84b65bb1e671aa36b90122))
- *(Breeze.Keybindings)* Add footer keybinding support ([0e0b257](https://github.com/gazler/breeze/commit/0e0b25788b43ddbd7991d38c09d8fa39d3902062))
- *(Breeze.Renderer)* Support rich and virtual text content surfaces ([4216c58](https://github.com/gazler/breeze/commit/4216c5825d7d1e7b766657986732f92f70674e2b))
- *(Breeze.View)* Support component attr and slot docs ([e36adad](https://github.com/gazler/breeze/commit/e36adad9e5ca27cd32a08265c523ff3eea3c1ee2))

### Bug Fixes

- Tighten formatter whitespace handling and slot API docs ([14514b8](https://github.com/gazler/breeze/commit/14514b8d5269db9ade6230b802d59c067812e384))
- *(examples)* Fix focus example ([65f0203](https://github.com/gazler/breeze/commit/65f020336c2a3207687cab3613440cd42c344dc6))
- *(Breeze.Server)* Prevent screen flickering on re-renders ([71560b0](https://github.com/gazler/breeze/commit/71560b073e1441e0325b3d76c2b3526495ce5f7a))
- *(Breeze.Server)* Don't schedule input flush with no input ([10e92db](https://github.com/gazler/breeze/commit/10e92db5e17b569b37c62220436c713a93801ed9))
- *(Breeze.Implicit.Input)* Fix ctrl + w inserting gibberish ([e269eb3](https://github.com/gazler/breeze/commit/e269eb34120a78141011a9f65803fe56879690db))
- *(Breeze.Debug)* Stop debug stats from repainting themselves ([8a8dd91](https://github.com/gazler/breeze/commit/8a8dd9149219e5dd2d100d4e97ae4cccd8f908b6))
- *(Breeze.Server)* Write patched rows before clearing the remainder ([b6de765](https://github.com/gazler/breeze/commit/b6de7652ad9810ae6194627a0a52155a7475e22c))
- *(Breeze.Server)* Clear patched row remainder after content ([e7260a3](https://github.com/gazler/breeze/commit/e7260a39a597835cf8636934366c27f19b05cc8b))
- *(Breeze.Blocks)* Use background color for modal surfaces ([282c637](https://github.com/gazler/breeze/commit/282c6373f51571dd6a7a48614383f4d49e291042))
- *(Breeze.Theme)* Retry system probes and preserve probed surfaces ([fdedf62](https://github.com/gazler/breeze/commit/fdedf624b043be85565ee8f038c5157cf11e265c))
- *(Breeze.Implicit.Input)* Ensure implicit keys handled first ([1634f35](https://github.com/gazler/breeze/commit/1634f351c26786c4ce7f66cfd047dd77031e17cf))
- *(Breeze.Server)* Batch printable input bursts safely ([0a06c58](https://github.com/gazler/breeze/commit/0a06c585e9e27d2b553180790992227b79392582))
- *(Breeze.Server)* Patch live children from their root viewport ([ee5e7bd](https://github.com/gazler/breeze/commit/ee5e7bd4430c3515c1ce92bd70aa63bfa2ff503a))
- *(Breeze.Keybindings)* Match ctrl bindings against decoded key events ([b8774eb](https://github.com/gazler/breeze/commit/b8774ebddcab3b3f95cdc01632fad92a345c28ff))
- *(Breeze.Storybook)* Stabilize preview and support file loading ([89b0a8d](https://github.com/gazler/breeze/commit/89b0a8d1ac5e37f3422de582b4b79949dc83cf91))

### Other

- *(Breeze.Implicit.Input)* Render wide characters by cell width ([f3b33cf](https://github.com/gazler/breeze/commit/f3b33cfebc6b6584ebcdf2aaf6037bc2ec1fb9ec))

### Refactor

- *(Breeze.Renderer)* Remove NimbleParsec and render tree directly ([9bf5f67](https://github.com/gazler/breeze/commit/9bf5f671dfc3b0395c139413748d9298ed32d991))
- *(Breeze.ChildServer)* Extract common functionality with Server ([db55c7a](https://github.com/gazler/breeze/commit/db55c7aef6066898f29fa905a890434faaddab8d))
- *(Breeze.Input)* Make input styling class-driven ([e4f3064](https://github.com/gazler/breeze/commit/e4f306442c76d2ba4ec1f3a52a35d5e66b27fc9c))

### Documentation

- Add Phoenix LiveView prior-art links ([39777b6](https://github.com/gazler/breeze/commit/39777b6bc0823109b9efdac10f20f3ee03960e64))
- Generate built-in component previews ([e8ceed5](https://github.com/gazler/breeze/commit/e8ceed552eaed35789b0edce647c21fe2141797e))

### Performance

- *(Breeze.Renderer)* Remove implicit reconcile callbacks ([eb5ed89](https://github.com/gazler/breeze/commit/eb5ed890e793de5c117277702683b8fbe9ad8ba6))
- *(Breeze.Server)* Reduce redraw flicker ([4687806](https://github.com/gazler/breeze/commit/46878068d017a61e4f9f8dbdbf534df55475ef6b))
- *(Breeze.Server)* Patch fixed live child invalidations ([c905b40](https://github.com/gazler/breeze/commit/c905b40bf8e3447eacad46acc1af11f72e7cc83e))
- *(Breeze.Server)* Patch frame rows and resync on sigwinch ([e9f83cc](https://github.com/gazler/breeze/commit/e9f83cc24f8c374a46addedb68d7dd57a1b188af))
- *(Breeze.ChildServer)* Retain hidden implicit state across remounts ([5497de4](https://github.com/gazler/breeze/commit/5497de44e3e528d78c1c15e7e7b9e587822eb1fa))

### Testing

- *(Breeze.Template)* Expand template and formatter coverage ([81e0a41](https://github.com/gazler/breeze/commit/81e0a41a500a4fae42fbabd019a61d625420bc0d))
- *(docs)* Update snapshots for the docs test ([ba21f6d](https://github.com/gazler/breeze/commit/ba21f6d02b1241cd36e53d03c5c5909470e4c945))
- *(Breeze.Server)* Fix snake example ([7a9eda0](https://github.com/gazler/breeze/commit/7a9eda001b51ddfe18d86d833554c7e6aa0afee6))
- *(posting)* Add a snapshot test for the open modal ([95e16b9](https://github.com/gazler/breeze/commit/95e16b95720b7d47401f60e97a97dbffe6c0d220))
## [0.2.0] - 2024-08-09

### Features

- *(Breeze.Server)* Add focusable elements ([47b475c](https://github.com/gazler/breeze/commit/47b475c03239c587dd92c375024a0c85e431e87b))
- *(Breeze.Server)* Allow passing change events from implicit ([a9b7ad0](https://github.com/gazler/breeze/commit/a9b7ad00c544ec4c4d9ec586f6dee20785095bd8))
- *(Breeze.Server)* Add handle_modfiers for implicits ([cc00bba](https://github.com/gazler/breeze/commit/cc00bbad61ca096a00544e8b054735a1d89ec3a2))
## [0.1.0] - 2024-06-13
