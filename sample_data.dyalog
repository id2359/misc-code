⍝ Sample data for testing timephasedfin.dyalog functions
⍝ Based on Figure 1 and examples in "APL Approaches to Time Phased Financial Modelling Logic"

:Namespace samples
    ⍝ Load the logic from the other file (assuming it's in the same directory or workspace)
    ⍝ In a Dyalog session, you would usually do: ]load timephasedfin.dyalog
    
    ⍝ --- Data from Example 1 (Cost of Sales) ---
    Sales ← 1000 1500 2000 1500 1000
    Expected_CGS ← 850 1275 1700 1530 1377

    ⍝ --- Data from Example 2 (Cash Balance / CUMMAX) ---
    CashFlow ← ¯500 700 ¯900 200 ¯500
    Cash_OB_Min ← 200 1000  ⍝ Opening Balance 200, Minimum Level 1000
    Expected_Cash_Tab ← 3 5 ⍴ 1000 1700 1000 1200 1000 ¯300 400 ¯500 ¯300 ¯800 1300 1300 1500 1500 1800

    ⍝ --- Data from Example 3 (Accounts Receivable / ACREC) ---
    AR_Flow ← 400 200 150 100 400
    Coll_Pct ← 20 25 25 25 30
    AR_OB ← 1500
    AR_Input ← ↑ AR_Flow Coll_Pct
    Expected_AR_Tab ← 2 5 ⍴ 1600 1400 1200 1000 1100 300 400 350 300 300

    ⍝ --- Data from Example 4 (Interest) ---
    Debt_Chg ← 1000 750 220 ¯300 ¯500
    Int_Par ← 500 0.1  ⍝ Constant 500, Rate 10%
    Expected_Interest ← 500 550 520 470 423

    ∇ RunTests
      ⍝ This function demonstrates how to call the functions
      ⎕←'--- Testing COSTOF ---'
      ⎕←#.timephased.COSTOF Sales
      
      ⎕←'--- Testing CUMMAX ---'
      ⎕←Cash_OB_Min #.timephased.CUMMAX CashFlow
      
      ⎕←'--- Testing ACREC ---'
      ⎕←AR_OB #.timephased.ACREC AR_Input
      
      ⎕←'--- Testing INTEREST ---'
      ⎕←Int_Par #.timephased.INTEREST Debt_Chg
    ∇
:endnamespace
