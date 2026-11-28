# Changelog

## [0.23.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.22.0...v0.23.0) (2026-11-28)


### Features

* **domain:** companion types, codec and fake transport (F19 S2) ([#177](https://github.com/peteyRevs/weight-lifting-app/issues/177)) ([63bb775](https://github.com/peteyRevs/weight-lifting-app/commit/63bb775fc1b94544d6eda5b4dfa381795a14cc0e))
* **domain:** the workout reconciler (F19 S1) ([#175](https://github.com/peteyRevs/weight-lifting-app/issues/175)) ([87b1ddc](https://github.com/peteyRevs/weight-lifting-app/commit/87b1ddc6b8aacdf96c38d0abcdb0e653e02527e1))
* **health:** the HealthStore contract, its values and a scriptable fake (F16 S1) ([#128](https://github.com/peteyRevs/weight-lifting-app/issues/128)) ([411b5ba](https://github.com/peteyRevs/weight-lifting-app/commit/411b5ba2948aff3ab382ee66ea6ecdf688298dad))
* **health:** the live store's session state machine: start, mirroring and heart rate (F16 S2a) ([#130](https://github.com/peteyRevs/weight-lifting-app/issues/130)) ([902e590](https://github.com/peteyRevs/weight-lifting-app/commit/902e5904efb4878297a7d50ba4b2a04580bb5689))
* **health:** the phone asks the watch to start, saves a phone-only workout, reads a record (F16 S3b) ([#133](https://github.com/peteyRevs/weight-lifting-app/issues/133)) ([b01cfcc](https://github.com/peteyRevs/weight-lifting-app/commit/b01cfcc730396983e1edb87e069a73a232a474e6))
* **health:** the phone's mirror receiver, and both apps' health wiring (F16 S3a) ([#132](https://github.com/peteyRevs/weight-lifting-app/issues/132)) ([c859750](https://github.com/peteyRevs/weight-lifting-app/commit/c859750611ceb7f0258b745b3067a67769b26a94))
* **health:** the watch's HealthKit session, the end of a workout, takeover and recovery (F16 S2b) ([#131](https://github.com/peteyRevs/weight-lifting-app/issues/131)) ([66386d3](https://github.com/peteyRevs/weight-lifting-app/commit/66386d3b1a7bb8f17afa1d5925ffd1b1e4595412))
* **persistence:** saveHealth/pendingHealth and the last-performance merge (F19 S3b) ([#182](https://github.com/peteyRevs/weight-lifting-app/issues/182)) ([6a0f9fc](https://github.com/peteyRevs/weight-lifting-app/commit/6a0f9fcac7731ac95242bafb68728fb71afa8b35))
* **persistence:** v003_companionSync tables and CompanionStore (F19 S3a) ([#180](https://github.com/peteyRevs/weight-lifting-app/issues/180)) ([0bdcaea](https://github.com/peteyRevs/weight-lifting-app/commit/0bdcaeaf5825e3f5d5b65f15530f8eea112bcb29))
* **sync:** live sync wired into both apps, and the liveConnection key (F17 S7b) ([#148](https://github.com/peteyRevs/weight-lifting-app/issues/148)) ([12ca728](https://github.com/peteyRevs/weight-lifting-app/commit/12ca728f3c5529c5a59f7ebaac40c0430d805b09))
* **sync:** the double start, the earlier start wins and no logged set is lost (F17 S5b) ([#144](https://github.com/peteyRevs/weight-lifting-app/issues/144)) ([73eda4f](https://github.com/peteyRevs/weight-lifting-app/commit/73eda4fa4799556f0d6f88912759029ac3b7eda4))
* **sync:** the health events broadcast and the watch's 5 s adopt-or-start rule (F17 S5a) ([#142](https://github.com/peteyRevs/weight-lifting-app/issues/142)) ([7522165](https://github.com/peteyRevs/weight-lifting-app/commit/7522165d5826582c46aee1179c41fc66de241c10))
* **sync:** the host on a live transport, handshake and gap replay (F17 S4a) ([#140](https://github.com/peteyRevs/weight-lifting-app/issues/140)) ([c056dac](https://github.com/peteyRevs/weight-lifting-app/commit/c056dacaa6950c8d6b05e00f271ff8d9e8868678))
* **sync:** the host takes the peer's envelopes (F17 S3) ([#139](https://github.com/peteyRevs/weight-lifting-app/issues/139)) ([66b7e6e](https://github.com/peteyRevs/weight-lifting-app/commit/66b7e6e52b120cdc447b6a5bd923507cacfdbf1f))
* **sync:** the live transport contract and a fake network for it (F17 S2) ([#138](https://github.com/peteyRevs/weight-lifting-app/issues/138)) ([c93fd3b](https://github.com/peteyRevs/weight-lifting-app/commit/c93fd3b019aed4b842716bda4db438073532cb1b))
* **sync:** the live wire format, WireFrame and WireCodec (F17 S1) ([#136](https://github.com/peteyRevs/weight-lifting-app/issues/136)) ([66f3e55](https://github.com/peteyRevs/weight-lifting-app/commit/66f3e55877c74f9a822d43524f077502e046a36e))
* **sync:** the mirroring and composite transports, watchdog, batching and connection state (F17 S6) ([#145](https://github.com/peteyRevs/weight-lifting-app/issues/145)) ([8bf02c6](https://github.com/peteyRevs/weight-lifting-app/commit/8bf02c676aeabdcaeb2e88517c6e6ed910b98628))
* **sync:** the WatchConnectivity transport and its one session delegate (F17 S7a) ([#146](https://github.com/peteyRevs/weight-lifting-app/issues/146)) ([38f0d42](https://github.com/peteyRevs/weight-lifting-app/commit/38f0d422bebff0dea245098255323e66a93f0958))
* **sync:** WCCompanionTransport over the activator's WCSession (F19 S4) ([#184](https://github.com/peteyRevs/weight-lifting-app/issues/184)) ([9989797](https://github.com/peteyRevs/weight-lifting-app/commit/99897979e94d0d87332fe578a00dab41acac1705))
* **watch:** Always-On, the UI flows and the device checks (F18 S7) ([#173](https://github.com/peteyRevs/weight-lifting-app/issues/173)) ([06e03cc](https://github.com/peteyRevs/weight-lifting-app/commit/06e03cc129f86995728d34c3ace7d52d271282fe))
* **watch:** presentation derivations for the mode, set and rest screens (F18 S1) ([#158](https://github.com/peteyRevs/weight-lifting-app/issues/158)) ([ea6cb6d](https://github.com/peteyRevs/weight-lifting-app/commit/ea6cb6d956831054026900f1cf5e5d0517604187))
* **watch:** rest zero, the GO window and haptics (F18 S2b) ([#164](https://github.com/peteyRevs/weight-lifting-app/issues/164)) ([71dcf1a](https://github.com/peteyRevs/weight-lifting-app/commit/71dcf1abf8427cb672e5842bbffede97744363b1))
* **watch:** the end confirm (F18 S6b) ([#172](https://github.com/peteyRevs/weight-lifting-app/issues/172)) ([1ee2e62](https://github.com/peteyRevs/weight-lifting-app/commit/1ee2e627ba8244343563c6895a5a3ba86b55d0a2))
* **watch:** the exercise list, the summary and the banners (F18 S6a) ([#169](https://github.com/peteyRevs/weight-lifting-app/issues/169)) ([156b19e](https://github.com/peteyRevs/weight-lifting-app/commit/156b19ebf7b6f49b644dd3713a8dddc97e929141))
* **watch:** the HealthKit session follows the workout (F18 S3) ([#165](https://github.com/peteyRevs/weight-lifting-app/issues/165)) ([745aacd](https://github.com/peteyRevs/weight-lifting-app/commit/745aacd30da648b7c495fca84d8a878f09bc764d))
* **watch:** the idle and summary presentation (F18 S1b) ([#159](https://github.com/peteyRevs/weight-lifting-app/issues/159)) ([b057a0c](https://github.com/peteyRevs/weight-lifting-app/commit/b057a0cb80cf73e46758068a66916967c850ec3a))
* **watch:** the session list and end overlay presentation (F18 S1c) ([#160](https://github.com/peteyRevs/weight-lifting-app/issues/160)) ([fbb194f](https://github.com/peteyRevs/weight-lifting-app/commit/fbb194fab8b215de4264266d5d57b2930562f62c))
* **watch:** the set-ready and rest screens (F18 S5b) ([#168](https://github.com/peteyRevs/weight-lifting-app/issues/168)) ([437962d](https://github.com/peteyRevs/weight-lifting-app/commit/437962d41ab7e2da4e70db50a7c4d419b71814eb))
* **watch:** the watch components (F18 S4) ([#166](https://github.com/peteyRevs/weight-lifting-app/issues/166)) ([a8ed5ed](https://github.com/peteyRevs/weight-lifting-app/commit/a8ed5edb343b17f08097f097c4e48a47019d97ee))
* **watch:** the workout root and the idle screen (F18 S5a) ([#167](https://github.com/peteyRevs/weight-lifting-app/issues/167)) ([b813daf](https://github.com/peteyRevs/weight-lifting-app/commit/b813daf62c198000a4d9f3e5e1cebbff8928b8fe))
* **watch:** the workout store, intents, overlays and crown (F18 S2a) ([#163](https://github.com/peteyRevs/weight-lifting-app/issues/163)) ([d01bf70](https://github.com/peteyRevs/weight-lifting-app/commit/d01bf70c6d0c6ddca5c5edc5cb2bdb1a15f22c45))
* **workout:** the watch-not-connected line and the F17 device checklist (F17 S8) ([#149](https://github.com/peteyRevs/weight-lifting-app/issues/149)) ([d1402a0](https://github.com/peteyRevs/weight-lifting-app/commit/d1402a08350013d3d12fe00a06d66fa467ddfacb))


### Fixes

* **ci:** the pre-validation's reported time comes from a clock the suite controls ([#178](https://github.com/peteyRevs/weight-lifting-app/issues/178)) ([#179](https://github.com/peteyRevs/weight-lifting-app/issues/179)) ([2dc27e4](https://github.com/peteyRevs/weight-lifting-app/commit/2dc27e413579e14a071a66147bfe50a80ded8ef7))
* **test:** the phone's health wiring tests build only for iOS, so check.sh --fast builds on the Mac again ([#137](https://github.com/peteyRevs/weight-lifting-app/issues/137)) ([cc1a0dd](https://github.com/peteyRevs/weight-lifting-app/commit/cc1a0ddaaa7b19a739623a8707de14fe8ad003b7))
* **workout:** the header's name keeps its case for VoiceOver and the audit ([#176](https://github.com/peteyRevs/weight-lifting-app/issues/176)) ([e60b547](https://github.com/peteyRevs/weight-lifting-app/commit/e60b5477e04de7d6451aa2e05e136d0a90826d9d))

## [0.22.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.21.1...v0.22.0) (2026-11-21)


### Features

* **appkit:** UI tests start from seeded history, Smoke starts from Today, and the nightly Flows chain the critical paths (F15 S1) ([#103](https://github.com/peteyRevs/weight-lifting-app/issues/103)) ([a10a2c2](https://github.com/peteyRevs/weight-lifting-app/commit/a10a2c2ad2f373f58f79c5438806988464e27523))


### Fixes

* **appkit:** UI tests draw the appearance they ask for, and the Program tab's audit issues are measured exclusions ([#105](https://github.com/peteyRevs/weight-lifting-app/issues/105)) ([e7cbbcc](https://github.com/peteyRevs/weight-lifting-app/commit/e7cbbccd0e6eb4eac3ed65f59457bff631ac36b3))
* **library:** a name of only spaces shows the placeholder; Today's Resume and View keep every word at every size ([#127](https://github.com/peteyRevs/weight-lifting-app/issues/127)) ([a317431](https://github.com/peteyRevs/weight-lifting-app/commit/a3174311130dc03148084efc4ff2e141ad66cbfe))
* **tests:** the long rest tests move RestCoverClock, and the first ImageRenderer render is a probe no test reads ([#111](https://github.com/peteyRevs/weight-lifting-app/issues/111)) ([e0996dc](https://github.com/peteyRevs/weight-lifting-app/commit/e0996dc3a7999d175761fe01e68bff42a0aeaf68))


### Performance

* **persistence:** historyEntries decodes each workout row from a cursor, not a fetchAll copy ([#118](https://github.com/peteyRevs/weight-lifting-app/issues/118)) ([#119](https://github.com/peteyRevs/weight-lifting-app/issues/119)) ([dd247c0](https://github.com/peteyRevs/weight-lifting-app/commit/dd247c0ba51779d17daa4f7a4fdb81a3cce32703))
* **persistence:** workout, exercise and exercise-history reads decode rows from cursors, as [#119](https://github.com/peteyRevs/weight-lifting-app/issues/119) did ([#126](https://github.com/peteyRevs/weight-lifting-app/issues/126)) ([5958613](https://github.com/peteyRevs/weight-lifting-app/commit/59586134aa1c96655e3b0c419b0af1ca33524292))

## [0.21.1](https://github.com/peteyRevs/weight-lifting-app/compare/v0.21.0...v0.21.1) (2026-11-13)


### Fixes

* **domain:** a rest that ends at no time stays hidden on watchOS 27.2, and the watch renders no NavigationStack off-screen ([#101](https://github.com/peteyRevs/weight-lifting-app/issues/101)) ([c92e963](https://github.com/peteyRevs/weight-lifting-app/commit/c92e963eeaa3425b495fd4d69ad47c814ee07f5d))

## [0.21.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.20.0...v0.21.0) (2026-11-11)


### Features

* **workout:** draw a superset as one block, logged round by round (F10 S9) ([#92](https://github.com/peteyRevs/weight-lifting-app/issues/92)) ([71533ae](https://github.com/peteyRevs/weight-lifting-app/commit/71533ae6a4e06fdadefadf3c556a8344e3adb10c))

## [0.20.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.19.0...v0.20.0) (2026-11-11)


### Features

* **settings:** delete all data, after a warning and the typed word, in one transaction (F14 S3) ([#91](https://github.com/peteyRevs/weight-lifting-app/issues/91)) ([2f452dd](https://github.com/peteyRevs/weight-lifting-app/commit/2f452dd534de9ef872982612f6ab8c56b2b1be44))

## [0.19.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.18.0...v0.19.0) (2026-11-11)


### Features

* **workout:** swap an exercise from its card, from a sheet of alternatives (F10 S8b) ([#89](https://github.com/peteyRevs/weight-lifting-app/issues/89)) ([18f1201](https://github.com/peteyRevs/weight-lifting-app/commit/18f120157ae7643b2bb299867f4d1dda8d84e8cf))

## [0.18.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.17.0...v0.18.0) (2026-11-11)


### Features

* **domain:** a swap re-targets the undone sets and its program change lands with the workout's first save (F10 S8a) ([#86](https://github.com/peteyRevs/weight-lifting-app/issues/86)) ([ca54ad6](https://github.com/peteyRevs/weight-lifting-app/commit/ca54ad628677da3d708efa682439bd2de7bc587a))
* **settings:** units carry your programs, the bar and plates, and CSV export (F14 S2) ([#88](https://github.com/peteyRevs/weight-lifting-app/issues/88)) ([8d462a2](https://github.com/peteyRevs/weight-lifting-app/commit/8d462a26bb7f599963e82617498c750fb6948f61))

## [0.17.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.16.0...v0.17.0) (2026-11-11)


### Features

* **history:** fix a past workout's sets in one sheet, saved as one write, with records and stats following (F13 S3) ([#84](https://github.com/peteyRevs/weight-lifting-app/issues/84)) ([da6470d](https://github.com/peteyRevs/weight-lifting-app/commit/da6470d384e388cadf97023a20bcae278b44f6e9))

## [0.16.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.15.0...v0.16.0) (2026-11-03)


### Features

* **history:** a past workout's detail with its receipt, rows that open their history, and delete (F13 S2) ([#81](https://github.com/peteyRevs/weight-lifting-app/issues/81)) ([fea3b77](https://github.com/peteyRevs/weight-lifting-app/commit/fea3b77ae2e579020f0ffa136ee7142763e6a177))
* **settings:** the Settings screen, with units, rest, week start and switches that save as you tap, and a two-option control in the design system (F14 S1b) ([#80](https://github.com/peteyRevs/weight-lifting-app/issues/80)) ([6bf5eb8](https://github.com/peteyRevs/weight-lifting-app/commit/6bf5eb8e59ab27bc8758b636f7339b429dc35704))

## [0.15.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.14.0...v0.15.0) (2026-10-29)


### Features

* **history:** the History tab lists past workouts by week, and a past workout opens where it was tapped (F13 S1) ([#77](https://github.com/peteyRevs/weight-lifting-app/issues/77)) ([dfb945a](https://github.com/peteyRevs/weight-lifting-app/commit/dfb945a87b730666e02019b6430b597169c89066))

## [0.14.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.13.0...v0.14.0) (2026-10-26)


### Features

* **library:** an exercise's history, with its 8-week chart, its stats and its session log (F12 S2) ([#72](https://github.com/peteyRevs/weight-lifting-app/issues/72)) ([20aac83](https://github.com/peteyRevs/weight-lifting-app/commit/20aac83a0f1de2a5cfa15aee99614eb737aa3947))


### Fixes

* **ci:** Linux jobs on ubuntu-24.04, and format in the macOS job, after two runner-image breakages ([#73](https://github.com/peteyRevs/weight-lifting-app/issues/73)) ([f46ab86](https://github.com/peteyRevs/weight-lifting-app/commit/f46ab86bd74a0712752f603efaa16946ce76bc76))

## [0.13.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.12.0...v0.13.0) (2026-10-22)


### Features

* **library:** the Library tab, with search, filter chips, RECENTLY LOGGED and every exercise's best set (F12 S1) ([#70](https://github.com/peteyRevs/weight-lifting-app/issues/70)) ([d92cc15](https://github.com/peteyRevs/weight-lifting-app/commit/d92cc1541872b84d2e05da6510105669ee714027))

## [0.12.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.11.0...v0.12.0) (2026-10-21)


### Features

* **onboarding:** the three onboarding steps and the root gate that shows them on a fresh install (F08 S2+S3) ([#67](https://github.com/peteyRevs/weight-lifting-app/issues/67)) ([a59315f](https://github.com/peteyRevs/weight-lifting-app/commit/a59315fc5ee05b946ecca6eb1ba43d367095ddfc))
* **program:** the Program tab in the app, with the Day editor's and the library's stores (F11 S14) ([#66](https://github.com/peteyRevs/weight-lifting-app/issues/66)) ([685314c](https://github.com/peteyRevs/weight-lifting-app/commit/685314caa634aefb2002025b2fb8fc55a8571031))
* **workout:** the receipt of a saved workout, with its records and Done (F10 S7b) ([#65](https://github.com/peteyRevs/weight-lifting-app/issues/65)) ([8316b7c](https://github.com/peteyRevs/weight-lifting-app/commit/8316b7c8c9f5f1c2006e0873ec1bce68b9de64cc))

## [0.11.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.10.0...v0.11.0) (2026-10-18)


### Features

* **program:** the builder's store, its save loop and its root (F11 S13) ([#63](https://github.com/peteyRevs/weight-lifting-app/issues/63)) ([b4364a8](https://github.com/peteyRevs/weight-lifting-app/commit/b4364a8e4d665eb094ba4da4518a661ddb1980e2))
* **program:** the views of the Day editor and of its slot panel (F11 S10) ([#55](https://github.com/peteyRevs/weight-lifting-app/issues/55)) ([77b33ec](https://github.com/peteyRevs/weight-lifting-app/commit/77b33ec90d2cb0d67582e28cb5805cc0072acf6d))
* **workout:** finishing a workout from the cover, with its save and a failed save (F10 S7a) ([#59](https://github.com/peteyRevs/weight-lifting-app/issues/59)) ([160989c](https://github.com/peteyRevs/weight-lifting-app/commit/160989ccf26618ae12a53501804f511ecd3e46e2))
* **workout:** the rest panel under the cover, with haptics (F10 S6) ([#54](https://github.com/peteyRevs/weight-lifting-app/issues/54)) ([d3ea51a](https://github.com/peteyRevs/weight-lifting-app/commit/d3ea51a4c937f0b95fa35bf0f4712f09db312435))


### Fixes

* counted texts in Today, icons right to left, and three test chores (M1 batch B) ([#56](https://github.com/peteyRevs/weight-lifting-app/issues/56)) ([d30500d](https://github.com/peteyRevs/weight-lifting-app/commit/d30500dadf63a0ad30faab6a117659e6415f6194))
* **design:** a name being edited keeps the tails of its letters ([#60](https://github.com/peteyRevs/weight-lifting-app/issues/60)) ([a3b8ab6](https://github.com/peteyRevs/weight-lifting-app/commit/a3b8ab655d1a4303b77f5c29995d2c790f95edf4))

## [0.10.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.9.0...v0.10.0) (2026-10-10)


### Features

* **program:** the views of the program builder and of the exercise library sheet (F11 S9) ([#49](https://github.com/peteyRevs/weight-lifting-app/issues/49)) ([abcf852](https://github.com/peteyRevs/weight-lifting-app/commit/abcf85269b8b21300a106973f3fb96da0cf1bccf))
* **today:** Today is on screen in the app, with its store and wiring (F09 S5) ([#50](https://github.com/peteyRevs/weight-lifting-app/issues/50)) ([b4b5821](https://github.com/peteyRevs/weight-lifting-app/commit/b4b582162ba2d175c74e50f54d1e16640258b3c8))
* **workout:** logging the sets of a solo exercise under the cover (F10 S5) ([#52](https://github.com/peteyRevs/weight-lifting-app/issues/52)) ([5e427ca](https://github.com/peteyRevs/weight-lifting-app/commit/5e427ca8610b0e43f45a90da7146d40a64ffb9ce))

## [0.9.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.8.0...v0.9.0) (2026-10-09)


### Features

* **program:** the form controls and the presentation of the exercise library sheet (F11 S8) ([#47](https://github.com/peteyRevs/weight-lifting-app/issues/47)) ([79ef492](https://github.com/peteyRevs/weight-lifting-app/commit/79ef49275e12a5d444e3774c08c8fd2dcae5f6c6))
* **workout:** starting or resuming a workout opens its cover (F10 S4) ([#45](https://github.com/peteyRevs/weight-lifting-app/issues/45)) ([e014b02](https://github.com/peteyRevs/weight-lifting-app/commit/e014b0220f61df48ab8701719d26787b01039867))

## [0.8.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.7.0...v0.8.0) (2026-10-08)


### Features

* **program:** the presentation of the day editor and its slot panel (F11 S6) ([#44](https://github.com/peteyRevs/weight-lifting-app/issues/44)) ([56c06a5](https://github.com/peteyRevs/weight-lifting-app/commit/56c06a5ac7ad64927e532d4705367a46fd1abe3f))
* **today:** the views of the Today screen (F09 S4) ([#43](https://github.com/peteyRevs/weight-lifting-app/issues/43)) ([127eb70](https://github.com/peteyRevs/weight-lifting-app/commit/127eb7071fc548935c8c0f0d9d6419b4c4c8b275))

## [0.7.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.6.0...v0.7.0) (2026-10-08)


### Features

* **program:** the presentation of the program builder (F11 S5) ([#40](https://github.com/peteyRevs/weight-lifting-app/issues/40)) ([1b6df7f](https://github.com/peteyRevs/weight-lifting-app/commit/1b6df7f18c99ec292eac31b24fca9eec2c1259e2))

## [0.6.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.5.0...v0.6.0) (2026-10-06)


### Features

* **domain:** program and day editing rules (F11 S1) ([#34](https://github.com/peteyRevs/weight-lifting-app/issues/34)) ([582bed6](https://github.com/peteyRevs/weight-lifting-app/commit/582bed65fa828f55da0890a05b09c690df10b28e))
* **domain:** the next scheduled day, volume change and load state for Today (F09 S2) ([#37](https://github.com/peteyRevs/weight-lifting-app/issues/37)) ([a627494](https://github.com/peteyRevs/weight-lifting-app/commit/a627494246c3032d5505eca9717d442b38a03c3c))
* **persistence:** a program is changed where it is stored, in one step (F11 S3) ([#36](https://github.com/peteyRevs/weight-lifting-app/issues/36)) ([50f2c6d](https://github.com/peteyRevs/weight-lifting-app/commit/50f2c6d1505bce01b8fd33591a0f14ef05141c60))
* **today:** the presentation that decides what Today shows (F09 S3) ([#38](https://github.com/peteyRevs/weight-lifting-app/issues/38)) ([6ba3c42](https://github.com/peteyRevs/weight-lifting-app/commit/6ba3c42372f97557489d0b5382597c342b780711))

## [0.5.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.4.0...v0.5.0) (2026-10-06)


### Features

* **app:** both apps boot on a real database (F07 S2) ([#24](https://github.com/peteyRevs/weight-lifting-app/issues/24)) ([6209706](https://github.com/peteyRevs/weight-lifting-app/commit/6209706a498ab479e2a3ad6f6ea20b7a374b6081))
* **app:** tab shell, route mapping and the first String Catalog (F09 S1) ([#28](https://github.com/peteyRevs/weight-lifting-app/issues/28)) ([9c6ea8d](https://github.com/peteyRevs/weight-lifting-app/commit/9c6ea8d4db6200c1e3a1dc490ff3952865c732ce))
* **app:** Today placeholders, debug menu with Diagnostics, UI tests (F07 S3) ([#25](https://github.com/peteyRevs/weight-lifting-app/issues/25)) ([567b9c3](https://github.com/peteyRevs/weight-lifting-app/commit/567b9c33ef8a7a7e78ce79ec7ac588941d7b005b))
* **deps:** dependency keys, stubs and the LedgerFakes module (F07 S1) ([#22](https://github.com/peteyRevs/weight-lifting-app/issues/22)) ([7ec7643](https://github.com/peteyRevs/weight-lifting-app/commit/7ec7643eb6b3d9c407e24905d5f4fba31011f8b0))
* **domain:** workout session client seam (F10 S1) ([#27](https://github.com/peteyRevs/weight-lifting-app/issues/27)) ([95b0837](https://github.com/peteyRevs/weight-lifting-app/commit/95b0837a838625353ba9b8c61307843b523cce09))
* **persistence:** a swap's program change lands with the saved workout; the log goes in the same transaction (F10 S3) ([#30](https://github.com/peteyRevs/weight-lifting-app/issues/30)) ([6943203](https://github.com/peteyRevs/weight-lifting-app/commit/6943203e3ac2440f9905f39747af04048726607e))
* **sync:** the workout session host, recovery at launch and the start use case (F10 S2) ([#29](https://github.com/peteyRevs/weight-lifting-app/issues/29)) ([6c5939d](https://github.com/peteyRevs/weight-lifting-app/commit/6c5939d151f1687e9dbf0217c6468a0d296ca1a6))

## [0.4.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.3.0...v0.4.0) (2026-10-03)


### Features

* **persistence:** personal records always follow history (F05 follow-up, decision [#27](https://github.com/peteyRevs/weight-lifting-app/issues/27)) ([#21](https://github.com/peteyRevs/weight-lifting-app/issues/21)) ([a8080ff](https://github.com/peteyRevs/weight-lifting-app/commit/a8080ffe5f79241bfae8f8cf618fe7db8dfc0501))
* **persistence:** workout history and stats queries (F05 S3) ([#19](https://github.com/peteyRevs/weight-lifting-app/issues/19)) ([efe0691](https://github.com/peteyRevs/weight-lifting-app/commit/efe0691e4d7ebdd01fa4026c96b0ab252ab220a5))

## [0.3.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.2.0...v0.3.0) (2026-10-02)


### Features

* **design:** phone components for Today and the active workout (F06 slice 2) ([#11](https://github.com/peteyRevs/weight-lifting-app/issues/11)) ([1d80613](https://github.com/peteyRevs/weight-lifting-app/commit/1d80613b5e93c461667a1eee85648c361a5a122d))
* **design:** remaining components, watch components and DesignGallery (F06 slice 3) ([#15](https://github.com/peteyRevs/weight-lifting-app/issues/15)) ([7740bd9](https://github.com/peteyRevs/weight-lifting-app/commit/7740bd993b4ea8dd02533ac8eddf28dd6793bca3))
* **domain:** exercise catalog seed, 224 exercises (F03) ([#14](https://github.com/peteyRevs/weight-lifting-app/issues/14)) ([7473d65](https://github.com/peteyRevs/weight-lifting-app/commit/7473d65422aebe89f31aa0969407560376525416))
* **persistence:** exercise and program repositories, catalog seeding (F05 S2) ([#17](https://github.com/peteyRevs/weight-lifting-app/issues/17)) ([b58ee2d](https://github.com/peteyRevs/weight-lifting-app/commit/b58ee2d5c494d7049e077d54aeab8f888b9c9ffe))
* **persistence:** GRDB schema, exact columns and event store (F05 S1) ([#13](https://github.com/peteyRevs/weight-lifting-app/issues/13)) ([1db1cf9](https://github.com/peteyRevs/weight-lifting-app/commit/1db1cf9d508b77b21164742625748f45316a568f))

## [0.2.0](https://github.com/peteyRevs/weight-lifting-app/compare/v0.1.0...v0.2.0) (2026-09-30)


### Features

* **design:** tokens, Archivo width axis, snapshots and design lint (F06 slice 1) ([#6](https://github.com/peteyRevs/weight-lifting-app/issues/6)) ([12b03c2](https://github.com/peteyRevs/weight-lifting-app/commit/12b03c2dce04e78bb0e2a13e0af3f59cac5710af))
* **domain:** event-sourced WorkoutEngine shared by phone and watch (F04) ([#8](https://github.com/peteyRevs/weight-lifting-app/issues/8)) ([ad4e20e](https://github.com/peteyRevs/weight-lifting-app/commit/ad4e20ea6e23c980ac2620a92b8f72d7424bb2a4))
