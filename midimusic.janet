(def ppq 480)
(var current-bpm 120)
(var current-tick 0)
(var event-counter 0)
(var current-scale-root :c4)
(var current-scale-mode :major)
(var current-bar-beats 4)
(var events @[])

(def note-table
  @{
    "c" 0 "c#" 1 "db" 1
    "d" 2 "d#" 3 "eb" 3
    "e" 4
    "f" 5 "f#" 6 "gb" 6
    "g" 7 "g#" 8 "ab" 8
    "a" 9 "a#" 10 "bb" 10
    "b" 11
  })

(def mode-intervals
  @{
    :major @[0 2 4 5 7 9 11]
    :minor @[0 2 3 5 7 8 10]
    :dorian @[0 2 3 5 7 9 10]
    :mixolydian @[0 2 4 5 7 9 10]
  })

(defn reset-state []
  (set current-bpm 120)
  (set current-tick 0)
  (set event-counter 0)
  (set current-scale-root :c4)
  (set current-scale-mode :major)
  (set current-bar-beats 4)
  (set events @[]))

(defn with-score* [thunk]
  (reset-state)
  (thunk)
  nil)

(defmacro with-score [& body]
  (tuple 'with-score* (tuple 'fn (tuple) ;body)))

(defn beats->ticks [beats]
  (math/round (* ppq beats)))

(defn tempo [bpm]
  (set current-bpm bpm))

(defn record-event [tick data]
  (set event-counter (+ event-counter 1))
  (array/push events @[tick event-counter data]))

(defn instrument [channel program]
  (record-event 0 (buffer (+ 0xC0 channel) program)))

(defn digit-byte? [b]
  (and (>= b 48) (<= b 57)))

(defn parse-pitch-string [pitch]
  (def s (string/ascii-lower pitch))
  (var split nil)
  (for i 0 (length s)
    (def b (in s i))
    (when (or (digit-byte? b) (= b 45))
      (set split i)
      (break)))
  (when (nil? split)
    (error (string "bad pitch spelling " pitch)))
  (def name (string/slice s 0 split))
  (def octave (scan-number (string/slice s split)))
  (def semitone (get note-table name))
  (when (nil? semitone)
    (error (string "unknown pitch " pitch)))
  (+ (* 12 (+ octave 1)) semitone))

(defn pitch->midi [pitch]
  (cond
    (int? pitch) pitch
    (keyword? pitch) (parse-pitch-string (string pitch))
    (symbol? pitch) (parse-pitch-string (string pitch))
    (string? pitch) (parse-pitch-string pitch)
    true (error (string "unsupported pitch " pitch))))

(defn scale* [root mode]
  (set current-scale-root root)
  (set current-scale-mode mode))

(defn degree->midi [n]
  (def root-midi (pitch->midi current-scale-root))
  (def intervals (or (get mode-intervals current-scale-mode)
                     (error (string "unknown scale mode " current-scale-mode))))
  (def idx (- n 1))
  (def size (length intervals))
  (def octave-shift (math/floor (/ idx size)))
  (def step (get intervals (mod idx size)))
  (+ root-midi step (* 12 octave-shift)))

(defn note* [pitch beats]
  (def midi (pitch->midi pitch))
  (def duration (beats->ticks beats))
  (record-event current-tick (buffer 0x90 midi 96))
  (record-event (+ current-tick duration) (buffer 0x80 midi 0))
  (set current-tick (+ current-tick duration)))

(defn chord* [pitches beats]
  (def duration (beats->ticks beats))
  (each pitch pitches
    (record-event current-tick (buffer 0x90 (pitch->midi pitch) 90)))
  (each pitch pitches
    (record-event (+ current-tick duration) (buffer 0x80 (pitch->midi pitch) 0)))
  (set current-tick (+ current-tick duration)))

(defn degree* [n beats]
  (note* (degree->midi n) beats))

(defn rest [beats]
  (set current-tick (+ current-tick (beats->ticks beats))))

(defn bar* [thunk]
  (def start current-tick)
  (thunk)
  (def used (/ (- current-tick start) ppq))
  (unless (= used current-bar-beats)
    (error (string "expected bar to contain " current-bar-beats " beats, got " used)))
  nil)

(defn sort-events []
  (sort events
        (fn [a b]
          (if (= (a 0) (b 0))
            (< (a 1) (b 1))
            (< (a 0) (b 0))))))

(defn push-u16 [buf n]
  (buffer/push-byte buf
                    (band (brushift n 8) 0xFF)
                    (band n 0xFF)))

(defn push-u24 [buf n]
  (buffer/push-byte buf
                    (band (brushift n 16) 0xFF)
                    (band (brushift n 8) 0xFF)
                    (band n 0xFF)))

(defn push-u32 [buf n]
  (buffer/push-byte buf
                    (band (brushift n 24) 0xFF)
                    (band (brushift n 16) 0xFF)
                    (band (brushift n 8) 0xFF)
                    (band n 0xFF)))

(defn push-vlq [buf n]
  (def parts @[(band n 0x7F)])
  (var value n)
  (while (>= value 128)
    (set value (brushift value 7))
    (array/push parts (band value 0x7F)))
  (var i (- (length parts) 1))
  (while (>= i 0)
    (def part (parts i))
    (if (= i 0)
      (buffer/push-byte buf part)
      (buffer/push-byte buf (bor 0x80 part)))
    (set i (- i 1))))

(defn tempo-event [bpm]
  (def mpqn (math/round (/ 60000000 bpm)))
  (def buf (buffer))
  (buffer/push-byte buf 0xFF 0x51 0x03)
  (push-u24 buf mpqn)
  buf)

(defn track-bytes []
  (sort-events)
  (def track (buffer))
  (def all-events @[@[0 0 (tempo-event current-bpm)]])
  (each evt events
    (array/push all-events evt))
  (var last-tick 0)
  (each evt all-events
    (def tick (evt 0))
    (def payload (evt 2))
    (push-vlq track (- tick last-tick))
    (buffer/push track payload)
    (set last-tick tick))
  (buffer/push-byte track 0x00 0xFF 0x2F 0x00)
  track)

(defn save-midi [path]
  (def track (track-bytes))
  (def out (buffer))
  (buffer/push out "MThd")
  (push-u32 out 6)
  (push-u16 out 0)
  (push-u16 out 1)
  (push-u16 out ppq)
  (buffer/push out "MTrk")
  (push-u32 out (length track))
  (buffer/push out track)
  (def f (file/open path :wbn))
  (file/write f out)
  (file/close f)
  (print "Wrote MIDI to " path))

(defmacro note [pitch beats]
  ~(note* ,(if (symbol? pitch) (keyword (string pitch)) pitch) ,beats))

(defmacro scale [root mode]
  ~(scale* ,(if (symbol? root) (keyword (string root)) root)
            ,(if (symbol? mode) (keyword (string mode)) mode)))

(defmacro chord [pitches beats]
  (if (tuple? pitches)
    (do
      (def xs @[])
      (each pitch pitches
        (array/push xs (if (symbol? pitch) (keyword (string pitch)) pitch)))
      ~(chord* ,xs ,beats))
    ~(chord* ,pitches ,beats)))

(defmacro degree [n beats]
  ~(degree* ,n ,beats))

(defmacro pattern [times & body]
  (tuple 'for 'i 0 times ;body))

(defmacro bar [& body]
  (tuple 'bar* (tuple 'fn (tuple) ;body)))
