#lang finance

(capital 25000)
(series BTC (102000 101000 100000 99000 100500 104000))
(series ETH (3200 3190 3180 3170 3190 3250))

(rule momentum-check
  (show-indicator "BTC sma(3)" (sma 'BTC 3))
  (show-indicator "BTC sma(5)" (sma 'BTC 5))
  (show-indicator "ETH sma(3)" (sma 'ETH 3)))

(if-crosses-above BTC 3 5
  (buy BTC 0.08))

(if-crosses-above ETH 3 5
  (buy ETH 2))

(price ETH 3100)
(if-crosses-below ETH 2 3
  (sell ETH 0.5))

(report)
