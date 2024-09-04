0.2.0 2024-09-04
--------------

- fix: update computation for payload length offset
  ([#63](https://github.com/anmonteiro/httpun-ws/pull/63))
- don't select digestif implementation
  ([#67](https://github.com/anmonteiro/httpun-ws/pull/67))
- fix: garbled data after committing frame header
  ([#68](https://github.com/anmonteiro/httpun-ws/pull/68))
- fix: mask all client frames
  ([#69](https://github.com/anmonteiro/httpun-ws/pull/69))
- feat: yield the reader if reads not scheduled
  ([#70](https://github.com/anmonteiro/httpun-ws/pull/70))
- unify input handler EOF and websocket error handler
  ([#70](https://github.com/anmonteiro/httpun-ws/pull/70),
  [#72](https://github.com/anmonteiro/httpun-ws/pull/72))
- client: fix infinite loop when client handshake disconnects
  ([#73](https://github.com/anmonteiro/httpun-ws/pull/73))

0.1.0 2024-06-17
--------------

- Initial public release

