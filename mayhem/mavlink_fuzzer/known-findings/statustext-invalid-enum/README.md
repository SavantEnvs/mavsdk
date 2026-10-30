# statustext-invalid-enum

`reproducer.bin` (4 bytes) makes `mavlink_fuzzer` halt with UBSan:

    cpp/src/mavsdk/core/mavlink_statustext_handler.cpp:37:39: runtime error: load of value 36,
    which is not a valid value for type 'MAV_SEVERITY'

Cause: `MavlinkStatustextHandler::process()` does `static_cast<MAV_SEVERITY>(statustext.severity)` on the raw
wire byte of a STATUSTEXT message and then copies the enum; MAVLink's `MAV_SEVERITY` only has values 0..7, so any
other severity byte from a peer is an out-of-range enum load (UB). Impact is low in practice, but it is
reachable from a remote MAVLink peer and, with halting UBSan, ends every fuzz run within seconds, so it is kept
out of `../testsuite/` and recorded here.

Replay: `/mayhem/mavlink_fuzzer-standalone mayhem/mavlink_fuzzer/known-findings/statustext-invalid-enum/reproducer.bin`

Upstream fix: keep the severity as `uint8_t` (or clamp it into 0..7) before converting to `MAV_SEVERITY`.
