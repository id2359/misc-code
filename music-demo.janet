(use midimusic)

(with-score
  (tempo 128)
  (instrument 0 0)
  (scale c4 major)

  (bar
    (degree 1 1)
    (degree 3 1)
    (degree 5 1)
    (degree 8 1))

  (bar
    (chord [c4 e4 g4] 2)
    (rest 1)
    (degree 5 1))

  (pattern 2
    (bar
      (degree 4 1)
      (degree 6 1)
      (degree 5 1)
      (degree 3 1)))

  (save-midi "/Users/frug/clawd/scripts/janet-mini-langs/examples/music-demo.mid"))
