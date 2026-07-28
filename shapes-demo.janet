(use shapes)

(with-drawing
  (canvas 720 420)

  (layer "background"
    (rect 30 30 660 360 :fill "ivory" :stroke "black")
    (line 70 300 650 300 :stroke "slategray" :stroke-width 6))

  (layer "planets"
    (translate 160 150
      (circle 0 0 70 :fill "tomato" :stroke "maroon"))
    (translate 330 150
      (scale 1.2
        (circle 0 0 45 :fill "gold" :stroke "darkorange"))))

  (layer "structure"
    (rotate-around -6 530 150
      (rect 440 80 180 140 :fill "steelblue" :stroke "navy" :stroke-width 3)))

  (layer "labels"
    (text 60 340 "Shapes DSL demo" :size 28 :fill "black")
    (text 60 374 "layers + transforms" :size 18 :fill "dimgray"))

  (save-svg "/Users/frug/clawd/scripts/janet-mini-langs/examples/shapes-demo.svg"))
