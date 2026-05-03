NB. fwn.ijs -- minimal Fuzzy Wavelet Network demo in J
NB.
NB. Run in J:
NB.     load 'fwn.ijs'
NB.
NB. Educational simplifications:
NB.   * 1-D input, 1-D output
NB.   * Gaussian fuzzy memberships
NB.   * Mexican-hat wavelets
NB.   * least-squares output weights

cocurrent 'base'

mexhat =: 3 : '(1 - *: y) * ^ _0.5 * *: y'
target =: 3 : '((1 o. 2 * y) + 0.3 * 2 o. 7 * y)'

NB. Parameters
ruleCentres =: _2 0 2
ruleWidth   =: 1.4
waveCentres =: _3 + (6 % 12) * i.13
scales      =: 1.2 0.8 1.2

NB. Helpers
gauss =: 3 : '^ _0.5 * *: y'

NB. Normalized membership matrix:
NB. rows are x values, columns are fuzzy rules.
memberships =: 3 : 0
  x =. y
  raw =. gauss (x -/ ruleCentres) % ruleWidth
  raw % +/"1 raw
)

NB. Design matrix:
NB. one column for each (rule,wavelet), plus final bias column.
design =: 3 : 0
  x =. y
  mu =. memberships x
  phi =. 0 $~ (#x),0
  for_i. i.#ruleCentres do.
    z =. (x -/ waveCentres) % i { scales
    psi =. mexhat z
    phi =. phi ,. (i {"1 mu) * psi
  end.
  phi ,. 1
)

NB. Training data
xTrain =: _3 + (6 % 79) * i.80
yTrain =: target xTrain

NB. Least-squares fit.
NB. dyad %. solves A %. b for least-squares-style systems in J.
Phi =: design xTrain
weights =: yTrain %. Phi

predict =: 3 : '(design y) +/ . * weights'

xTest =: _3 + (6 % 199) * i.200
yTest =: target xTest
yHat  =: predict xTest
rmse  =: %: (+/ *: yHat - yTest) % # yTest

echo 'Minimal FWN demo'
echo '----------------'
echo 'rules: ', ": # ruleCentres
echo 'wavelets per rule: ', ": # waveCentres
echo 'parameters: ', ": # weights
echo 'test RMSE: ', ": rmse
echo ''
echo 'first 10 rows: x , target , fwn'
echo 10 {. xTest ,. yTest ,. yHat
