# The Companion protocol

Everything here lives in the `ClickerCompanion` module except discovery and the connection policy, which are the app's (`DeviceBrowser`, `RemoteController`). pyatv is the reference for every wire format; facts marked as measured were checked against a Living Room Apple TV on tvOS 27.0.

## Discovery

One `NWBrowser` for `_companion-link._tcp` runs for the app's life. It reports additions, removals and TXT changes live and follows network path changes on its own. Results are filtered by the `rpMd` TXT record so only Apple TVs appear (Macs, iPhones and HomePods advertise the same service). `rpFl` says whether PIN pairing is allowed, `rpVr` is the protocol version, and `rpMRtID` is the stable identifier pairings are keyed by; never key by `rpBA`, the Bluetooth address, which rotates.

`AppleTVDevice` keeps the whole TXT record and the interfaces the TV was seen on (`DeviceBrowser.merge` unions them across per-interface results). The browser skips callbacks whose changes are all `.identical`, since the system's path agents make it re-report unchanged results several times a second.

Rescan, in the device picker, calls `DeviceBrowser.restart()`, which re-issues the query but holds back removals for a 2 s grace so a partial first callback cannot drop the selected TV (which would make `devicesDidChange` select another). It cannot flush mDNSResponder's cache: a TV that vanished without a Bonjour goodbye lingers until its records expire either way. Rescan also knocks on the selected TV's last connected address (`PortKnocker`: half-second TCP connections to 3689, 7000, 32498, 49152 and 49153), pyatv's trick for waking a TV behind a Bonjour sleep proxy. The address is remembered per device in `lastAddressByDevice` and dropped on Forget.

## Pairing

Pair-setup follows HomeKit over Companion frames: SRP with the TV's PIN, then an Ed25519 key exchange encrypted with ChaCha20-Poly1305, producing long-term keys (`PairingCredentials`). Every later connection runs pair-verify (X25519 plus Ed25519 signatures) and derives per-direction session keys.

- SRP: the RFC 5054 3072-bit group with SHA-512, `k = H(N | PAD(g))`, `u = H(PAD(A) | PAD(B))`, and the full-width `H(N) xor H(g)` in M1. The math is slow in debug builds; use `--release` when pairing often.
- Pairing nonces are 8-byte labels (`"PS-Msg05"`) left-padded with zeros to 12 bytes.
- The client's identity (`clientDeviceID` in user defaults, through `IdentityStore`) is what the TV knows Clicker by. Two copies running at once share it, and the TV drops the earlier session when the second connects.

When pair-verify fails because the pairing is no longer valid, the controller drops the stale credentials itself (`dropStalePairing`) and brings the pair card back with `pairingNotice` explaining why, since Retry would fail the same way and Forget is buried in Settings:

- `CompanionError.identityChanged`: the TV presented a different accessory identifier, which means a factory reset (`--demo reset`).
- `CompanionError.pairingLost`: the TV answered M4 with an error TLV, which means Clicker was removed from its Remotes and Devices (`--demo removed`). The TLV's own code 2 message talks about PIN codes and would mislead, so it is not shown.

`submitPIN` turns a credential save failure into a failed pair card ("Paired, but the pairing couldn't be saved: …", `--demo savefailed`), since a green check would be a lie after the next launch.

### Legacy pairing keys

Old pairings were keyed by something other than the `rpMRtID` UUID. When a TV appears unpaired, `RemoteController` adopts a pairing for it by name and model, but only one whose key is not a UUID (`legacyPairing`). Any wider rule breaks two same-named TVs of the same model in different homes: on every network switch each would take the other's keys, fail pair-verify with `identityChanged` and drop them. `LegacyPairingTests` pins this.

## The session

After pair-verify, frames are encrypted with ChaCha20-Poly1305 using a 12-byte little-endian counter nonce and the frame header as additional data. The client then registers a `com.apple.tvremoteservices` session; `TVRCSessionStart` may fail on older tvOS and is best-effort.

- Buttons are `_hidC` events with real press and release, so holds work.
- Touch: `_touchStart` opens a 1000×1000 virtual pad and `_hidT` events carry press, hold and release with coordinates and a timestamp (see [input.md](input.md#trackpad-swipes)).
- Power state comes from `TVSystemStatus` / `SystemStatus` events. `FetchAttentionState` is unimplemented on newer tvOS, so it is best-effort too.
- Media control is `_mcc`, and the TV's `_iMC` events carry `_mcF` flags saying what the playing app supports (`MediaControlFlags`, pyatv's values). The flags start empty until the first `_iMC`, as in pyatv.
- The connected TV's tvOS version is `_osV` in the `_systemInfo` reply, shown in the device picker's details.

Measured: `_mcc` commands act on whatever app is playing, and the TV accepts every command without an error whether or not the app supports it. With Netflix playing (flags: play, pause, volume, skip forward, skip backward), play, pause and `SkipBy` ±10 s worked, while next/previous track and fast forward/rewind were accepted and did nothing. Trust the flags, never the reply. `FetchUserAccountsEvent` returned the one profile as `{uuid: name}` and `SwitchUserAccountEvent` to it was accepted (no UI yet). Caption settings (`_mcc` 12 and 13) are only named in pyatv, which never sends them, so their payload is unknown.

### Mute

The HID set has no mute. Mute uses `_mcc` GetVolume and SetVolume: set to 0, restore on unmute. The TV only answers these when it owns an absolute volume level, meaning HomePod, AirPlay or Bluetooth output. Over HDMI the volume buttons still work (the TV forwards them as CEC or IR) but mute cannot.

`MediaControlFlags.volume` (0x100) gates the Mute segment and the M key through `canMute`, with a tooltip saying what output it needs. The flag is not enough on its own: measured over HDMI, tvOS 27 advertises volume, answers GetVolume with a constant 0.5 whatever the real level, echoes SetVolume back and sends no `_iMC` afterwards, so nothing audible happens. pyatv's `set_volume` waits for that `_iMC` and times out at 5 s; `RemoteController.confirmMute` does the same (`muteConfirmationTimeout`), then undoes the mute, drops the volume bit so Mute disables with its tooltip, and shows an inline notice (`--demo hdmi`). A later `_iMC` with the bit set (output switched to a HomePod) re-enables it.

## Text input

- `_tiStart` reports whether a field is focused; `_tiStarted` and `_tiStopped` events track focus while connected.
- `_tiC` events carry `RTITextOperations` keyed archives, built with `NSKeyedArchiver` and `$archiver` rewritten to `RTIKeyedArchiver`. A replace asserts an empty field and inserts the new text in one operation, so backspace and edits show no empty flash.
- Reading `_tiD` walks the archive's UIDs by hand, because class-name lookup can resolve to real private classes once AppKit is loaded.
- tvOS 27 archives `$top.sessionUUID` as 16 raw bytes (`NSData`), not an `NSUUID` with `NS.uuidbytes`; `TextInputArchive.session` accepts both. Rejecting the raw form makes every `_tiStart` reply parse as nil.
- Return sends `"\n"` as `insertionText` (`RemoteController.submitTVText`). pyatv has no submit and the private headers show no done field, but tvOS treats the newline as Done.

Measured in the Search app: insert, replace, clear, `currentText` from a reopened field, `_tiStarted` pushed while connected, and Return (Search ran the query and sent `_tiStopped`). When a parser question comes up, dump the TV's `_tiD` to a file and `plutil -p` it rather than guessing.

## Connection lifecycle

`RemoteController` connects when the panel opens and keeps the session while it is closed.

- `connectIfNeeded` retries once quietly: a connection attempt right after another session dropped often times out once, at the TCP connect itself (no "Connected to" log), not in pair-verify. The first attempt waits 5 s and the retry 10 s (`firstConnectTimeout`, `retryConnectTimeout`); a successful connect lands in about 2 s. If "Connect failed: timeout" starts appearing twice per open, widen the first timeout.
- A command queued while an attempt is in flight waits through the retry too (`readyClient` loops over `connectTask`). Once an attempt has failed, a command does not start another, otherwise each queued press would run its own attempt and the lot would replay when the TV answered. The notice's Retry, the next panel open and `scheduleReconnect` are the ways back.
- While open, the session sends an empty NoOp frame (type 1) every 30 s (`CompanionConnection.keepAliveInterval`). The TV answers nothing and the receive loop ignores non-OPACK frames.
- When the TV drops the session while the panel is open, `scheduleReconnect` makes one attempt a second later (`reconnectDelay`). With the panel hidden, the next open connects.
- Quitting goes through `applicationShouldTerminate`, which waits up to a second for `RemoteController.shutdown(within:)` to send `_sessionStop` and close, so the TV is told instead of finding a dead connection. A task group races the disconnect against a sleep and cancels the loser.
- Every wait in `CompanionConnection` (the TCP connect, `exchange`, `exchangeAuthentication`) ends with `CancellationError` as soon as its task is cancelled, and `close()` ends a connect in flight with the close's error. Without that, a cancelled request would wait out its full timeout (5 s, 30 s while pairing). `CompanionConnectionTests` drives this against a silent loopback listener.

## Codec and crypto gotchas

- OPACK back-references: the decoder's object list, which pointer markers 0xA0–0xC4 index, takes sized ints (0x30–0x33), floats, UUIDs, dates, strings and data, and skips one-byte ints, bools, null, arrays and dictionaries, exactly as pyatv's `_unpack` does. Skipping sized ints makes a pointer after one (a transaction id above 0x27, say) resolve one object early. `OPACKTests.countsObjectsLikePyatv` pins the rule.
- `Data` slices: CryptoKit ciphertext can have a non-zero `startIndex`. Index by the value's own indices or copy it (`Data(slice)`); this once crashed pairing.
- `SymmetricKey` is `Sendable` in the SDK, so keys cross actors unwrapped.
