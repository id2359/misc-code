(var current-cash 0.0)
(var holdings @{})
(var prices @{})
(var histories @{})

(defn ->amount [x]
  (+ 0.0 x))

(defn reset-state []
  (set current-cash 0.0)
  (set holdings @{})
  (set prices @{})
  (set histories @{}))

(defn with-session* [thunk]
  (reset-state)
  (thunk)
  nil)

(defmacro with-session [& body]
  (tuple 'with-session* (tuple 'fn (tuple) ;body)))

(defn price* [asset amount]
  (def px (->amount amount))
  (put prices asset px)
  (def xs (or (get histories asset) @[]))
  (array/push xs px)
  (put histories asset xs)
  px)

(defn series* [asset values]
  (when (= 0 (length values))
    (error "series cannot be empty"))
  (def xs @[])
  (each v values
    (array/push xs (->amount v)))
  (put histories asset xs)
  (put prices asset (get xs (- (length xs) 1)))
  xs)

(defn lookup-price [asset]
  (or (get prices asset)
      (error (string "no price registered for asset " asset))))

(defn lookup-history [asset]
  (or (get histories asset)
      (error (string "no history registered for asset " asset))))

(defn lookup-holding [asset]
  (or (get holdings asset) 0.0))

(defn capital [amount]
  (set current-cash (->amount amount)))

(defn units* [asset]
  (lookup-holding asset))

(defn cash []
  current-cash)

(defn last-n [xs n]
  (tuple/slice xs (- (length xs) n)))

(defn sum-seq [xs]
  (var total 0.0)
  (each x xs
    (set total (+ total x)))
  total)

(defn sma* [asset period]
  (def xs (lookup-history asset))
  (when (< (length xs) period)
    (error (string "not enough history for " asset " period " period)))
  (/ (sum-seq (last-n xs period)) period))

(defn equity []
  (var total current-cash)
  (each [asset qty] (pairs holdings)
    (set total (+ total (* qty (lookup-price asset)))))
  total)

(defn buy* [asset qty]
  (def units (->amount qty))
  (def px (lookup-price asset))
  (def cost (* units px))
  (when (> cost current-cash)
    (error (string "insufficient cash for " asset ": need " cost ", have " current-cash)))
  (set current-cash (- current-cash cost))
  (put holdings asset (+ (lookup-holding asset) units))
  nil)

(defn sell* [asset qty]
  (def units (->amount qty))
  (def owned (lookup-holding asset))
  (when (> units owned)
    (error (string "cannot sell " units " units of " asset "; only have " owned)))
  (def px (lookup-price asset))
  (set current-cash (+ current-cash (* units px)))
  (put holdings asset (- owned units))
  nil)

(defn fmt2 [x]
  (string/format "%.2f" x))

(defn fmt4 [x]
  (string/format "%.4f" x))

(defn show-indicator [label value]
  (print "  " label ": " (fmt4 (->amount value))))

(defn holding-value* [asset]
  (def qty (lookup-holding asset))
  (def px (lookup-price asset))
  (print asset " => units " (fmt4 qty) " @ " (fmt2 px) " => value " (fmt2 (* qty px))))

(defn report []
  (print "Finance report")
  (print "  cash: " (fmt2 current-cash))
  (def items @[])
  (each [asset qty] (pairs holdings)
    (when (> qty 0.0)
      (array/push items @[asset qty])))
  (sort items (fn [a b] (< (string (a 0)) (string (b 0)))))
  (each item items
    (holding-value* (item 0)))
  (print "  total equity: " (fmt2 (equity))))

(defn rule* [name thunk]
  (print "Rule " name)
  (thunk)
  nil)

(defn if-crosses-above* [asset fast slow thunk]
  (def xs (lookup-history asset))
  (when (< (length xs) (+ slow 1))
    (error (string "need at least slow+1 samples for " asset)))
  (def prev-xs (tuple/slice xs 0 -1))
  (def prev-fast (/ (sum-seq (last-n prev-xs fast)) fast))
  (def prev-slow (/ (sum-seq (last-n prev-xs slow)) slow))
  (def now-fast (sma* asset fast))
  (def now-slow (sma* asset slow))
  (when (and (<= prev-fast prev-slow)
             (> now-fast now-slow))
    (thunk))
  nil)

(defn if-crosses-below* [asset fast slow thunk]
  (def xs (lookup-history asset))
  (when (< (length xs) (+ slow 1))
    (error (string "need at least slow+1 samples for " asset)))
  (def prev-xs (tuple/slice xs 0 -1))
  (def prev-fast (/ (sum-seq (last-n prev-xs fast)) fast))
  (def prev-slow (/ (sum-seq (last-n prev-xs slow)) slow))
  (def now-fast (sma* asset fast))
  (def now-slow (sma* asset slow))
  (when (and (>= prev-fast prev-slow)
             (< now-fast now-slow))
    (thunk))
  nil)

(defmacro price [asset amount]
  ~(price* ,(keyword (string asset)) ,amount))

(defmacro series [asset values]
  ~(series* ,(keyword (string asset)) ,values))

(defmacro units [asset]
  ~(units* ,(keyword (string asset))))

(defmacro sma [asset period]
  ~(sma* ,(keyword (string asset)) ,period))

(defmacro buy [asset qty]
  ~(buy* ,(keyword (string asset)) ,qty))

(defmacro sell [asset qty]
  ~(sell* ,(keyword (string asset)) ,qty))

(defmacro holding-value [asset]
  ~(holding-value* ,(keyword (string asset))))

(defmacro rule [name & body]
  (tuple 'rule* (string name) (tuple 'fn (tuple) ;body)))

(defmacro if-crosses-above [asset fast slow & body]
  (def assetk (keyword (string asset)))
  (tuple 'if-crosses-above* assetk fast slow (tuple 'fn (tuple) ;body)))

(defmacro if-crosses-below [asset fast slow & body]
  (def assetk (keyword (string asset)))
  (tuple 'if-crosses-below* assetk fast slow (tuple 'fn (tuple) ;body)))
