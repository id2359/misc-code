:Namespace fwn
⍝ fwn.dyalog -- minimal Fuzzy Wavelet Network demo in Dyalog APL 18.2
⍝
⍝ Load in Dyalog/RIDE:
⍝     ]load /path/to/fwn.dyalog
⍝
⍝ Educational simplifications:
⍝   - 1-D input, 1-D output
⍝   - Gaussian fuzzy memberships
⍝   - Mexican-hat wavelets
⍝   - least-squares output weights

⎕IO←0
⎕PP←8

MexHat←{(1-⍵*2)×*-0.5×⍵*2}
Target←{(1○(2×⍵)) + 0.3×(2○(7×⍵))}  ⍝ sin(2x)+0.3 cos(7x)

RuleCentres←¯2 0 2
RuleWidth←1.4
WaveCentres←¯3 + (6÷12)×⍳13
Scales←1.2 0.8 1.2

Gaussian←{*-0.5×⍵*2}

⍝ Memberships x:
⍝ returns matrix: rows=input samples, columns=fuzzy rules.
Memberships←{
    x←⍵
    raw←Gaussian ((x∘.-RuleCentres)÷RuleWidth)
    raw÷(+/raw)
}

⍝ Design x:
⍝ feature columns are membership_i(x) × wavelet_k_i(x), plus bias.
Design←{
    x←⍵
    mu←Memberships x
    phi←((⍴x),0)⍴0
    :For i :In ⍳⍴RuleCentres
        z←(x∘.-WaveCentres)÷i⊃Scales
        psi←MexHat z
        phi←phi,(mu[;i])×psi
    :EndFor
    phi,1
}

⍝ Training data
XTrain←¯3 + (6÷79)×⍳80
YTrain←Target XTrain

Phi←Design XTrain

⍝ Least-squares weights. In Dyalog, b⌹A solves A w ≈ b.
Weights←YTrain⌹Phi

Predict←{(Design ⍵)+.×Weights}

XTest←¯3 + (6÷199)×⍳200
YTest←Target XTest
YHat←Predict XTest
RMSE←((+/((YHat-YTest)*2))÷⍴YTest)*0.5

⎕←'Minimal FWN demo'
⎕←'----------------'
⎕←'rules: ',⍕⍴RuleCentres
⎕←'wavelets per rule: ',⍕⍴WaveCentres
⎕←'parameters: ',⍕⍴Weights
⎕←'test RMSE: ',⍕RMSE
⎕←''
⎕←'first 10 rows: x , target , fwn'
⎕←10↑XTest,YTest,YHat

:EndNamepace 
