#lang racket/base

;;; ============================================================================
;;; FFT Dashboard in Racket
;;; ----------------------------------------------------------------------------
;;; Generates a composite sine-wave signal (15 Hz + 40 Hz), computes its forward
;;; FFT with `math/array`, and renders a 3-panel dashboard (time series,
;;; magnitude spectrum, phase spectrum) using the `plot` collection.
;;;
;;; Run:  racket fft-dashboard.rkt
;;; Output file: fft-dashboard.png  (in the current working directory)
;;; ============================================================================

(require math/array        ; arrays + array-fft (the forward DFT)
         plot/pict         ; headless plotting (no GUI / Gtk required)
         pict              ; pict combinators to assemble the dashboard
         pict/convert      ; pict->bitmap
         racket/draw       ; save the bitmap to a PNG file
         racket/class      ; send (method call) for bitmap% save-file
         racket/math       ; pi
         racket/flonum)    ; flonum helpers

;; ----------------------------------------------------------------------------
;; 1. Sampling parameters
;; ----------------------------------------------------------------------------
;; ANTI-ALIASING (Nyquist-Shannon sampling theorem):
;;   A signal must be sampled at a rate Fs > 2 * f_max, where f_max is the
;;   highest frequency present in the signal.  If Fs <= 2*f_max, frequencies
;;   above Fs/2 (the Nyquist frequency) "fold back" into the band [0, Fs/2] and
;;   masquerade as lower frequencies -- this corruption is called *aliasing* and
;;   cannot be undone after sampling.  In practice you also need an analog
;;   anti-alias (low-pass) filter before the ADC to remove any energy above
;;   Fs/2, because real signals are rarely perfectly band-limited.
;;
;;   Here f_max = 40 Hz, so we need Fs > 80 Hz.  We choose Fs = 256 Hz, which
;;   gives a comfortable safety margin (Nyquist = 128 Hz) and, conveniently, an
;;   integer number of samples per cycle for both 15 Hz and 40 Hz.
;;
;; NUMBER OF SAMPLES (must be a power of two for `array-fft`):
;;   N = 256.  With Fs = N = 256 the recording lasts T = N/Fs = 1.0 s and the
;;   frequency resolution is dF = Fs/N = 1.0 Hz.  Because dF divides both 15
;;   and 40, the two components land *exactly* on bins 15 and 40 -- no spectral
;;   leakage -- which makes the magnitude/phase plots easy to read.
(define Fs 256.0)     ; sampling rate [Hz]   (> 2 * 40 = 80, so no aliasing)
(define N  256)       ; number of samples (power of two, required by array-fft)
(define f1 15.0)     ; frequency of first  component [Hz]
(define f2 40.0)     ; frequency of second component [Hz]
(define a1 1.0)      ; amplitude of 15 Hz component
(define a2 0.5)      ; amplitude of 40 Hz component
(define nyquist (/ Fs 2.0))   ; = 128 Hz, highest frequency faithfully represented

;; ----------------------------------------------------------------------------
;; 2. Build the composite signal as a 1-D math/array array
;; ----------------------------------------------------------------------------
;; Sampling instants: t[k] = k / Fs  for k = 0 .. N-1.
;; Signal: x(t) = a1*sin(2*pi*f1*t) + a2*sin(2*pi*f2*t)
;;
;; We store x in a `math/array` array because that is what `array-fft`
;; consumes.  `build-array` takes a shape (here a 1-D shape of length N) and a
;; procedure of an *index vector* -> element.
(define signal
  (build-array
   (vector N)
   (lambda (idx)
     (define k (vector-ref idx 0))
     (define t (/ k Fs))                       ; time of sample k
     (+ (* a1 (sin (* 2.0 pi f1 t)))
        (* a2 (sin (* 2.0 pi f2 t)))))))

;; ----------------------------------------------------------------------------
;; 3. Forward FFT
;; ----------------------------------------------------------------------------
;; `array-fft` computes the discrete Fourier transform of every axis of its
;; input.  For a real 1-D array it returns an (Array Float-Complex) of the same
;; length N.  The scaling convention is controlled by the `dft-convention`
;; parameter, which *defaults to the signal-processing convention*: the forward
;; transform is an UNSCALED sum (no 1/N factor), and the 1/N lives in the
;; inverse transform.  We compensate for that explicitly below when we convert
;; to a single-sided amplitude spectrum.
(define spectrum (array-fft signal))   ; X[k], k = 0 .. N-1, complex

;; ----------------------------------------------------------------------------
;; 4. Map FFT bins to actual frequencies
;; ----------------------------------------------------------------------------
;; The k-th output bin corresponds to frequency
;;
;;     f[k] = k * Fs / N        (for the positive-frequency half, k = 0 .. N/2)
;;
;; because the DFT assumes samples are spaced 1/Fs seconds apart, so one full
;; "cycle" of the N-point transform spans N samples = N/Fs seconds, giving a
;; bin spacing of dF = Fs/N = 1 Hz here.  Bins k = 0 .. N/2 cover the positive
;; frequencies 0 .. Fs/2 (the Nyquist frequency); bins k = N/2+1 .. N-1 are the
;; negative frequencies (a mirror image, since the input is real).  For a
;; real-valued signal the magnitude spectrum is therefore symmetric, and we only
;; need to plot the first N/2+1 bins (0 .. Nyquist).
(define num-pos-bins (+ (/ N 2) 1))    ; bins 0 .. N/2 inclusive

;; Helper: read the complex value of bin k from the spectrum array.
(define (bin k) (array-ref spectrum (vector k)))

;; Frequency (in Hz) of the k-th positive bin.
(define (freq-of k) (* k (/ Fs N)))

;; Single-sided amplitude spectrum.
;;   For 0 < k < N/2:  A[k] = (2/N) * |X[k]|     (factor 2 folds the mirror
;;                                                 negative-frequency half back in)
;;   For k = 0 and k = N/2 (DC and Nyquist): A[k] = (1/N) * |X[k]|
;; With the unscaled forward transform this recovers the sinusoid amplitudes
;; (peaks ~ a1 = 1.0 at 15 Hz and ~ a2 = 0.5 at 40 Hz).
(define (amp-of k)
  (define mag (magnitude (bin k)))
  (if (or (= k 0) (= k (/ N 2)))
      (/ mag N)
      (/ (* 2.0 mag) N)))

;; Phase spectrum (radians) from the complex argument of each bin.
;; NB: phase is only meaningful at bins where the magnitude is appreciable;
;; at (near-)zero-magnitude bins it is dominated by numerical noise.
(define (phase-of k) (angle (bin k)))

;; Build (x, y) point vectors for the `lines` renderer.
(define (time-points)
  (for/vector ([k (in-range N)])
    (define t (/ k Fs))
    (vector t (array-ref signal (vector k)))))

(define (magnitude-points)
  (for/vector ([k (in-range num-pos-bins)])
    (vector (freq-of k) (amp-of k))))

(define (phase-points)
  (for/vector ([k (in-range num-pos-bins)])
    (vector (freq-of k) (phase-of k))))

;; ----------------------------------------------------------------------------
;; 5. Render the three subplots with the `plot` collection
;; ----------------------------------------------------------------------------
;; The `plot` collection has no built-in multi-subplot procedure, so we render
;; each panel to a `pict` with `plot-pict` and then stack them into one
;; dashboard image with pict's `vc-append`.
(define w 820)
(define h 280)

(define time-pict
  (plot-pict
   (lines (time-points) #:color "steelblue" #:width 1 #:label "x(t)")
   #:width w #:height h
   #:x-label "time (s)" #:y-label "amplitude"
   #:title "Time series: a1*sin(2*pi*15*t) + a2*sin(2*pi*40*t)"))

(define magnitude-pict
  (plot-pict
   (lines (magnitude-points) #:color "firebrick" #:width 1
          #:label "single-sided |X(f)|")
   #:width w #:height h
   #:x-min 0 #:x-max nyquist
   #:x-label "frequency (Hz)" #:y-label "amplitude"
   #:title "Magnitude spectrum (peaks at 15 Hz and 40 Hz)"))

(define phase-pict
  (plot-pict
   (lines (phase-points) #:color "darkgreen" #:width 1 #:label "arg X(f)")
   #:width w #:height h
   #:x-min 0 #:x-max nyquist
   #:x-label "frequency (Hz)" #:y-label "phase (rad)"
   #:title "Phase spectrum (meaningful only near the peaks)"))

;; ----------------------------------------------------------------------------
;; 6. Assemble the dashboard and save it as a PNG
;; ----------------------------------------------------------------------------
(define title-pict
  ;; `text` takes (string family size style weight underline?) positionally.
  (text "FFT Dashboard: Composite Sine Wave (15 Hz + 40 Hz)" 'modern 20))

(define dashboard
  (vc-append 12 title-pict time-pict magnitude-pict phase-pict))

(define out-file "fft-dashboard.png")
(send (pict->bitmap dashboard) save-file out-file 'png)
(printf "Wrote ~a (~a panels, Fs=~a Hz, N=~a, Nyquist=~a Hz)~n"
        out-file 3 Fs N nyquist)
