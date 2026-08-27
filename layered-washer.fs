\ layered-washer.fs
\ Layered washing-machine control example for Gforth.
\
\ This is a SIMULATION.  It does not control real hardware.
\
\ Layers:
\
\   IO-LAYER       simulated digital/analogue I/O
\   WASHER-HW      named appliance sensors and actuators
\   WASHER-CONTROL control operations such as fill, heat, drain, spin
\   WASHER-PROGRAM complete wash cycles built from those operations
\
\ Run:
\
\   gforth layered-washer.fs
\   quick-wash
\
\ or:
\
\   gforth layered-washer.fs -e 'quick-wash bye'


\ ============================================================
\ Layer 1: generic simulated I/O
\ ============================================================

vocabulary io-layer

also io-layer definitions

variable sim-water-level
variable sim-temperature
variable sim-door-closed

0 sim-water-level !
20 sim-temperature !
-1 sim-door-closed !

: io-message ( c-addr u -- )
    type cr ;

: digital-on ( c-addr u -- )
    ." ON:  " type cr ;

: digital-off ( c-addr u -- )
    ." OFF: " type cr ;

: read-water-level ( -- n )
    sim-water-level @ ;

: write-water-level ( n -- )
    sim-water-level ! ;

: read-temperature ( -- n )
    sim-temperature @ ;

: write-temperature ( n -- )
    sim-temperature ! ;

: read-door-switch ( -- flag )
    sim-door-closed @ ;

previous definitions


\ ============================================================
\ Layer 2: washing-machine hardware vocabulary
\ Depends on IO-LAYER.
\ ============================================================

vocabulary washer-hw

also io-layer
also washer-hw definitions

: inlet-on ( -- )
    s" water inlet valve" digital-on ;

: inlet-off ( -- )
    s" water inlet valve" digital-off ;

: heater-on ( -- )
    s" heater" digital-on ;

: heater-off ( -- )
    s" heater" digital-off ;

: pump-on ( -- )
    s" drain pump" digital-on ;

: pump-off ( -- )
    s" drain pump" digital-off ;

: motor-stop ( -- )
    s" drum motor" digital-off ;

: motor-wash-cw ( -- )
    s" drum motor: slow clockwise" io-message ;

: motor-wash-ccw ( -- )
    s" drum motor: slow anticlockwise" io-message ;

: motor-spin ( -- )
    s" drum motor: high-speed spin" io-message ;

: door-closed? ( -- flag )
    read-door-switch ;

: water-level ( -- n )
    read-water-level ;

: water-level! ( n -- )
    write-water-level ;

: temperature ( -- n )
    read-temperature ;

: temperature! ( n -- )
    write-temperature ;

previous
previous
definitions


\ ============================================================
\ Layer 3: control operations
\ Depends on WASHER-HW and IO-LAYER.
\ ============================================================

vocabulary washer-control

also io-layer
also washer-hw
also washer-control definitions

: require-door-closed ( -- )
    door-closed? 0= if
        abort" Door is open"
    then ;

: fill-to ( target -- )
    require-door-closed
    inlet-on

    begin
        dup water-level >
    while
        water-level 10 + dup 100 min water-level!
        ." water level = " water-level . ." %" cr
        100 ms
    repeat

    drop
    inlet-off ;

: heat-to ( target-temp -- )
    require-door-closed
    heater-on

    begin
        dup temperature >
    while
        temperature 5 + temperature!
        ." temperature = " temperature . ." C" cr
        100 ms
    repeat

    drop
    heater-off ;

: tumble-once ( -- )
    require-door-closed

    motor-wash-cw
    200 ms
    motor-stop
    100 ms

    motor-wash-ccw
    200 ms
    motor-stop
    100 ms ;

: tumble ( cycles -- )
    0 ?do
        tumble-once
    loop ;

: drain ( -- )
    pump-on

    begin
        water-level 0>
    while
        water-level 10 - 0 max water-level!
        ." water level = " water-level . ." %" cr
        100 ms
    repeat

    pump-off ;

: spin-for ( cycles -- )
    require-door-closed
    water-level 0<> if
        abort" Cannot spin while water remains in drum"
    then

    motor-spin
    0 ?do
        ." spinning..." cr
        150 ms
    loop
    motor-stop ;

: rinse-cycle ( -- )
    ." -- rinse --" cr
    60 fill-to
    4 tumble
    drain ;

previous
previous
previous
definitions


\ ============================================================
\ Layer 4: complete washing programs
\ Depends on all lower layers.
\ ============================================================

vocabulary washer-program

also io-layer
also washer-hw
also washer-control
also washer-program definitions

: prepare-machine ( -- )
    require-door-closed
    motor-stop
    pump-off
    inlet-off
    heater-off ;

: cotton-wash ( -- )
    ." === COTTON WASH ===" cr
    prepare-machine

    ." -- main wash --" cr
    70 fill-to
    60 heat-to
    8 tumble
    drain

    rinse-cycle
    rinse-cycle

    ." -- final spin --" cr
    10 spin-for

    ." === COTTON WASH COMPLETE ===" cr ;

: quick-wash-cycle ( -- )
    ." === QUICK WASH ===" cr
    prepare-machine

    ." -- wash --" cr
    50 fill-to
    40 heat-to
    4 tumble
    drain

    rinse-cycle

    ." -- spin --" cr
    5 spin-for

    ." === QUICK WASH COMPLETE ===" cr ;

previous
previous
previous
previous
definitions


\ ============================================================
\ Public interface
\ ============================================================

also washer-program

: quick-wash ( -- )
    quick-wash-cycle ;

: full-wash ( -- )
    cotton-wash ;

previous


\ ============================================================
\ Simulation helpers exposed in FORTH
\ ============================================================

also io-layer

: reset-washer ( -- )
    0 sim-water-level !
    20 sim-temperature !
    -1 sim-door-closed !
    ." washer simulation reset" cr ;

: open-door ( -- )
    0 sim-door-closed !
    ." door opened" cr ;

: close-door ( -- )
    -1 sim-door-closed !
    ." door closed" cr ;

: washer-status ( -- )
    ." water:       " sim-water-level @ . ." %" cr
    ." temperature: " sim-temperature @ . ." C" cr
    ." door:        "
    sim-door-closed @ if
        ." closed"
    else
        ." open"
    then
    cr ;

previous


\ ============================================================
\ Try these at the Gforth prompt
\ ============================================================
\
\   washer-status
\
\   quick-wash
\
\   reset-washer
\   full-wash
\
\ Safety/interlock demonstration:
\
\   reset-washer
\   open-door
\   quick-wash
\
\ This aborts with:
\
\   Door is open
\
\
\ Explore the vocabulary layers:
\
\   order
\
\   also washer-hw
\   words
\   previous
\
\   also washer-control
\   words
\   previous
\
\   also washer-program
\   words
\   previous
