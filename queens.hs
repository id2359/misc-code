{-# LANGUAGE BangPatterns #-}

module Main (main) where

import Data.Bits
import System.Environment (getArgs, getProgName)
import Text.Read (readMaybe)

-- Backtracking with bitmasks.
-- cols: occupied columns
-- d1: occupied diagonals (shifted left each row)
-- d2: occupied anti-diagonals (shifted right each row)
--
-- We represent available positions as bits within an Int.

solveNQueens :: Int -> Bool -> IO Integer
solveNQueens n printSolutions = go 0 0 0 []
  where
    allMask :: Int
    allMask = (1 `shiftL` n) - 1

    go :: Int -> Int -> Int -> [Int] -> IO Integer
    go !cols !d1 !d2 placement
      | length placement == n = do
          if printSolutions
            then putStrLn (unwords (map (show . (+1)) (reverse placement)))
            else pure ()
          pure 1
      | otherwise = loop avail placement 0
      where
        avail = allMask .&. complement (cols .|. d1 .|. d2)

        loop :: Int -> [Int] -> Integer -> IO Integer
        loop 0 _ !acc = pure acc
        loop a p !acc = do
          let bit = a .&. negate a              -- lowest set bit
              a'  = a `xor` bit
              col = countTrailingZeros bit
          cnt <- go (cols .|. bit) ((d1 .|. bit) `shiftL` 1) ((d2 .|. bit) `shiftR` 1) (col : p)
          loop a' p (acc + cnt)

main :: IO ()
main = do
  args <- getArgs
  prog <- getProgName
  case args of
    [s] ->
      case readMaybe s :: Maybe Int of
        Nothing -> usage prog
        Just n
          | n <= 0 -> putStrLn "0"
          | n > 32 -> putStrLn "n too large (max 32 for this build)"
          | otherwise -> do
              let printSolutions = n <= 10
              if printSolutions
                then putStrLn "Printing each solution as 1-based column positions per row..."
                else pure ()
              count <- solveNQueens n printSolutions
              putStrLn ("count: " ++ show count)
    _ -> usage prog

usage :: String -> IO ()
usage prog = do
  putStrLn ("Usage: " ++ prog ++ " <n>")
  putStrLn "Solves N-Queens for the given n. Prints solutions for n<=10, then always prints the total count."
