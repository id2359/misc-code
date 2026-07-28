(var canvas-width 640)
(var canvas-height 480)
(var emitter-stack @[])

(defn reset-state []
  (set canvas-width 640)
  (set canvas-height 480)
  (set emitter-stack @[@[]]))

(reset-state)

(defn with-drawing* [thunk]
  (reset-state)
  (thunk)
  nil)

(defmacro with-drawing [& body]
  (tuple 'with-drawing* (tuple 'fn (tuple) ;body)))

(defn current-emitter []
  (get emitter-stack (- (length emitter-stack) 1)))

(defn push-element [s]
  (array/push (current-emitter) s)
  nil)

(defn canvas [width height]
  (set canvas-width width)
  (set canvas-height height))

(defn option-map [kvs]
  (def out @{})
  (var i 0)
  (while (< i (length kvs))
    (def key (kvs i))
    (def value (kvs (+ i 1)))
    (put out key value)
    (set i (+ i 2)))
  out)

(defn rect [x y width height & kvs]
  (def opts (option-map kvs))
  (def fill (or (get opts :fill) "none"))
  (def stroke (or (get opts :stroke) "black"))
  (def stroke-width (or (get opts :stroke-width) 2))
  (push-element
    (string/format
      "<rect x=\"%v\" y=\"%v\" width=\"%v\" height=\"%v\" fill=\"%v\" stroke=\"%v\" stroke-width=\"%v\" />"
      x y width height fill stroke stroke-width)))

(defn circle [cx cy radius & kvs]
  (def opts (option-map kvs))
  (def fill (or (get opts :fill) "none"))
  (def stroke (or (get opts :stroke) "black"))
  (def stroke-width (or (get opts :stroke-width) 2))
  (push-element
    (string/format
      "<circle cx=\"%v\" cy=\"%v\" r=\"%v\" fill=\"%v\" stroke=\"%v\" stroke-width=\"%v\" />"
      cx cy radius fill stroke stroke-width)))

(defn line [x1 y1 x2 y2 & kvs]
  (def opts (option-map kvs))
  (def stroke (or (get opts :stroke) "black"))
  (def stroke-width (or (get opts :stroke-width) 2))
  (push-element
    (string/format
      "<line x1=\"%v\" y1=\"%v\" x2=\"%v\" y2=\"%v\" stroke=\"%v\" stroke-width=\"%v\" />"
      x1 y1 x2 y2 stroke stroke-width)))

(defn escape-text [s]
  (var t (string s))
  (set t (string/replace "&" "&amp;" t))
  (set t (string/replace "<" "&lt;" t))
  (set t (string/replace ">" "&gt;" t))
  t)

(defn text [x y content & kvs]
  (def opts (option-map kvs))
  (def size (or (get opts :size) 24))
  (def fill (or (get opts :fill) "black"))
  (push-element
    (string/format
      "<text x=\"%v\" y=\"%v\" font-size=\"%v\" fill=\"%v\" font-family=\"Futura, Avenir, sans-serif\">%v</text>"
      x y size fill (escape-text content))))

(defn wrap-group [attrs inner]
  (def body (string/join inner "\n"))
  (string "<g " attrs ">\n" body "\n</g>"))

(defn capture-group [wrapper thunk]
  (def local @[])
  (array/push emitter-stack local)
  (thunk)
  (array/pop emitter-stack)
  (push-element (wrapper local)))

(defn svg-document []
  (def body (string/join (current-emitter) "\n"))
  (string/format
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%v\" height=\"%v\" viewBox=\"0 0 %v %v\">\n%v\n</svg>\n"
    canvas-width canvas-height canvas-width canvas-height body))

(defn save-svg [path]
  (def f (file/open path :wn))
  (file/write f (svg-document))
  (file/close f)
  (print "Wrote SVG to " path))

(defmacro layer [name & body]
  (tuple 'capture-group
         (tuple 'fn
                (tuple 'inner)
                (tuple 'wrap-group
                       (tuple 'string/format "data-layer=\"%v\"" name)
                       'inner))
         (tuple 'fn (tuple) ;body)))

(defmacro translate [dx dy & body]
  (tuple 'capture-group
         (tuple 'fn
                (tuple 'inner)
                (tuple 'wrap-group
                       (tuple 'string/format "transform=\"translate(%v %v)\"" dx dy)
                       'inner))
         (tuple 'fn (tuple) ;body)))

(defmacro rotate [deg & body]
  (tuple 'capture-group
         (tuple 'fn
                (tuple 'inner)
                (tuple 'wrap-group
                       (tuple 'string/format "transform=\"rotate(%v)\"" deg)
                       'inner))
         (tuple 'fn (tuple) ;body)))

(defmacro rotate-around [deg cx cy & body]
  (tuple 'capture-group
         (tuple 'fn
                (tuple 'inner)
                (tuple 'wrap-group
                       (tuple 'string/format "transform=\"rotate(%v %v %v)\"" deg cx cy)
                       'inner))
         (tuple 'fn (tuple) ;body)))

(defmacro scale [a & rest]
  (if (and (> (length rest) 0) (number? (rest 0)))
    (do
      (def sx a)
      (def sy (rest 0))
      (def body (tuple/slice rest 1))
      (tuple 'capture-group
             (tuple 'fn
                    (tuple 'inner)
                    (tuple 'wrap-group
                           (tuple 'string/format "transform=\"scale(%v %v)\"" sx sy)
                           'inner))
             (tuple 'fn (tuple) ;body)))
    (do
      (def factor a)
      (def body rest)
      (tuple 'capture-group
             (tuple 'fn
                    (tuple 'inner)
                    (tuple 'wrap-group
                           (tuple 'string/format "transform=\"scale(%v)\"" factor)
                           'inner))
             (tuple 'fn (tuple) ;body)))))
