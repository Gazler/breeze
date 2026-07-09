## [unreleased]

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

### Refactor

- *(Breeze.Server)* Split runtime state helpers ([317c7b9](https://github.com/gazler/breeze/commit/317c7b9b8899e1429f9c954d213f7f29bb5f6734))

### Documentation

- *(README.md)* Update for v0.3.0 ([87b1206](https://github.com/gazler/breeze/commit/87b120685a327911164bb0a3d5ffbaeb5f65b690))
- *(README.md)* Fix example ([9ea136e](https://github.com/gazler/breeze/commit/9ea136ef4ed192954795d0613eb501c5a505243a))

### Testing

- Fix intermittent test failures in CI ([9a59ebd](https://github.com/gazler/breeze/commit/9a59ebd2a32d8607277ea77c18b8a014211d2043))
- *(Breeze.Storybook)* Fix race condition in tests ([b6bd4e1](https://github.com/gazler/breeze/commit/b6bd4e1ac39361688941aba5699869240b8bd8e0))
- *(Breeze.Storybook)* Explicitly start each story under test ([939c420](https://github.com/gazler/breeze/commit/939c4200b019705b7f5553632bdb27a1e33493a0))
- *(RemoteInspector)* Fix remove inspector and debug test races ([b82383f](https://github.com/gazler/breeze/commit/b82383f3e9cd5d4c63f60a01d968613c2a91595b))

### Miscellaneous Tasks

- Update ssh demos ([e0af8b0](https://github.com/gazler/breeze/commit/e0af8b0739636da3f59e395d39cc2561aaa13fa2))
- *(ci)* Ignore formatting ([bec4843](https://github.com/gazler/breeze/commit/bec484315d11b5750eee63277a4a68f59012cba6))
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
- 0.3.0 ([461172a](https://github.com/gazler/breeze/commit/461172a648ae3f65571ef88f5742a5377a5f721e))

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

### Miscellaneous Tasks

- Remove phoenix_live_view dependency ([a89bf78](https://github.com/gazler/breeze/commit/a89bf787b5117bf66df662780ddb1a73ec005338))
- *(Breeze.Template)* Use eval_quoted for bindings ([1b81a43](https://github.com/gazler/breeze/commit/1b81a435981b8129f6c573c9fc048c4bf1512592))
- Add locals_without_parens to formatter ([c4ea1f3](https://github.com/gazler/breeze/commit/c4ea1f3f7a53459f335c50c5983ff6c50f8b0c18))
- *(.github)* Ci workflow ([1bea866](https://github.com/gazler/breeze/commit/1bea866e4f838fdfc51eb850c3ccd49de3bd18f6))
- *(.ci)* Remove branches from triggers ([029c137](https://github.com/gazler/breeze/commit/029c137e5d723abb8b5fb87deaa1785e1475b442))
- Add a posting example to show off a complicated UI ([ad4e115](https://github.com/gazler/breeze/commit/ad4e115c08fe7665af3220281305d3a3a5c3bd54))
- Update back_breeze ([67902c1](https://github.com/gazler/breeze/commit/67902c1caa458385d8f73a42900b314d22bbe950))
- Upgrade back_breeze to support render cache ([1cd0994](https://github.com/gazler/breeze/commit/1cd099444a20b7098d85b4f5d669246529dc107b))
## [0.2.1] - 2025-05-23

### Other

- 0.2.1 ([619d728](https://github.com/gazler/breeze/commit/619d728c367dfc210e384e9db8256aec34342fc3))

### Miscellaneous Tasks

- Upgrade termite and live_view ([b08fd29](https://github.com/gazler/breeze/commit/b08fd29c08d7c7a66636e0cdd52ed295c5b93acd))
## [0.2.0] - 2024-08-09

### Features

- *(Breeze.Server)* Add focusable elements ([47b475c](https://github.com/gazler/breeze/commit/47b475c03239c587dd92c375024a0c85e431e87b))
- *(Breeze.Server)* Allow passing change events from implicit ([a9b7ad0](https://github.com/gazler/breeze/commit/a9b7ad00c544ec4c4d9ec586f6dee20785095bd8))
- *(Breeze.Server)* Add handle_modfiers for implicits ([cc00bba](https://github.com/gazler/breeze/commit/cc00bbad61ca096a00544e8b054735a1d89ec3a2))

### Other

- 0.2.0 ([c45ba99](https://github.com/gazler/breeze/commit/c45ba99a6652663af68c389a0fbe23899e67f31d))
## [0.1.0] - 2024-06-13

### Miscellaneous Tasks

- Initial setup ([069c03b](https://github.com/gazler/breeze/commit/069c03b0278118c98eb004833bcd3383f6d5c778))
