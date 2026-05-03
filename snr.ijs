NB. ========= basic complex linear algebra =========

NB. Hermitian (conjugate transpose)
H =: +@|:

NB. inner product: x^H y
ip =: 4 : '(H x) +/ .* y'

NB. matrix-vector product
mv =: 4 : 'x +/ .* y'

NB. quadratic form: w^H R w
qf =: 4 : 'x ip (y mv x)'

NB. normalize vector (unit norm)
norm =: %: @ (+/ @: (* +. *))   NB sqrt(sum |.|^2)
unit =: % norm

NB. ========= max-SNR beamformer =========

NB. w ∝ Rn^{-1} d
maxsnr =: 4 : '(%. x) mv y'

NB. normalized version (optional)
maxsnr_n =: 4 : 'unit ((%. x) mv y)'

NB. ========= SNR =========

NB. SNR = (w^H Rs w) / (w^H Rn w)
snr =: 4 : '((x qf y) % (x qf z))'  NB w snr (Rs;Rn)

NB. helper: unpack boxed Rs,Rn
snr_eval =: 4 : '(x snr >{.y) >{:y'

NB. ========= steering vector (ULA, plane wave) =========

NB. steering vector: d_n = exp(j * k * r_n)
NB. here use simple linear phase: exp(j * phi * n)
steer =: 3 : 'exp(0j1 * y * i. x)'  NB x=#elements, y=phase increment

NB. ========= example =========

NB. array size
N =: 4

NB. steering vector (signal direction)
d =: N steer 0.3

NB. noise covariance (correlated noise example)
Rn =: 4 4 $ 1 0.3 0.2 0.1 ,
             0.3 1 0.3 0.2 ,
             0.2 0.3 1 0.3 ,
             0.1 0.2 0.3 1

NB. signal covariance (rank-1)
sigma2 =: 1
Rs =: sigma2 * d */ H d

NB. compute weights
w =: Rn maxsnr d
w =: unit w   NB normalize (optional)

NB. test beamformer output on signal
v_sig =: d
v_out =: w ip v_sig

NB. compute SNR
SNR =: w snr_eval (Rs;Rn)

NB. ========= print =========
'weights w:' , ": w
'output (signal):' , ": v_out
'SNR:' , ": SNR
