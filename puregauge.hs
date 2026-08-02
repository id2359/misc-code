{- This program simulates SU(GROUP) lattice gauge fields with the
   simple Wilson action.
   Converted to Haskell from Creutz's C++ puregauge.cc
-}

{-# LANGUAGE ForeignFunctionInterface #-}

module Main where

import Foreign.C.Types (CDouble(..), CLong(..))
import Data.Array.IO
import Data.IORef
import Control.Monad (forM_, when)
import Text.Printf (printf)
import System.Environment (getArgs)
import System.CPUTime (getCPUTime)
import System.Exit (exitWith, ExitCode(..))

foreign import ccall "drand48" c_drand48 :: IO CDouble
foreign import ccall "srand48" c_srand48 :: CLong -> IO ()

drand48 :: IO Double
drand48 = realToFrac <$> c_drand48

srand48 :: Int -> IO ()
srand48 seed = c_srand48 (fromIntegral seed)

groupConst :: Int
groupConst = 2

dimConst :: Int
dimConst = 4

sizeConst :: Int
sizeConst = 8

hitsConst :: Int
hitsConst = 10

shapeConst :: [Int]
shapeConst = [sizeConst, sizeConst, sizeConst, sizeConst]

nsites :: Int
nsites = sizeConst * sizeConst * sizeConst * sizeConst -- 4096

nlinks :: Int
nlinks = dimConst * nsites -- 16384

vectorlength :: Int
vectorlength = nsites `div` 2 -- 2048

data Matrix = Matrix
  { r00 :: !Double, r01 :: !Double, r10 :: !Double, r11 :: !Double
  , i00 :: !Double, i01 :: !Double, i10 :: !Double, i11 :: !Double
  } deriving (Show, Eq)

idMatrix :: Double -> Matrix
idMatrix x = Matrix x 0.0 0.0 x 0.0 0.0 0.0 0.0

matMul :: Matrix -> Matrix -> Matrix
matMul (Matrix a00 a01 a10 a11 ai00 ai01 ai10 ai11)
       (Matrix b00 b01 b10 b11 bi00 bi01 bi10 bi11) =
  Matrix (a00*b00 - ai00*bi00 + a01*b10 - ai01*bi10)
         (a00*b01 - ai00*bi01 + a01*b11 - ai01*bi11)
         (a10*b00 - ai10*bi00 + a11*b10 - ai11*bi10)
         (a10*b01 - ai10*bi01 + a11*b11 - ai11*bi11)
         (a00*bi00 + ai00*b00 + a01*bi10 + ai01*b10)
         (a00*bi01 + ai00*b01 + a01*bi11 + ai01*b11)
         (a10*bi00 + ai10*b00 + a11*bi10 + ai11*b10)
         (a10*bi01 + ai10*b01 + a11*bi11 + ai11*b11)

matAdd :: Matrix -> Matrix -> Matrix
matAdd (Matrix a00 a01 a10 a11 ai00 ai01 ai10 ai11)
       (Matrix b00 b01 b10 b11 bi00 bi01 bi10 bi11) =
  Matrix (a00+b00) (a01+b01) (a10+b10) (a11+b11)
         (ai00+bi00) (ai01+bi01) (ai10+bi10) (ai11+bi11)

conjugate :: Matrix -> Matrix
conjugate (Matrix r00 r01 r10 r11 i00 i01 i10 i11) =
  Matrix r00 r10 r01 r11 (-i00) (-i10) (-i01) (-i11)

project :: Matrix -> Matrix
project (Matrix r00 r01 r10 r11 i00 i01 i10 i11) =
  let norm = sqrt (r00*r00 + i00*i00 + r01*r01 + i01*i01)
      invNorm = 1.0 / norm
      r00' = r00 * invNorm
      i00' = i00 * invNorm
      r01' = r01 * invNorm
      i01' = i01 * invNorm
      r10' = -r01'
      r11' =  r00'
      i10' =  i01'
      i11' = -i00'
  in Matrix r00' r01' r10' r11' i00' i01' i10' i11'

vtprodElem :: Matrix -> Matrix -> Double
vtprodElem (Matrix a00 a01 a10 a11 ai00 ai01 ai10 ai11)
           (Matrix b00 b01 b10 b11 bi00 bi01 bi10 bi11) =
  (a00*b00 - ai00*bi00) + (a01*b10 - ai01*bi10) +
  (a10*b01 - ai10*bi01) + (a11*b11 - ai11*bi11)

vtraceElem :: Matrix -> Double
vtraceElem (Matrix r00 _ _ r11 _ _ _ _) = r00 + r11

shiftArray :: [Int]
shiftArray = [1, 8, 64, 512]

splitCoords :: Int -> (Int, Int, Int, Int)
splitCoords s =
  let x3 = s `div` 512
      rem3 = s `mod` 512
      x2 = rem3 `div` 64
      rem2 = rem3 `mod` 64
      x1 = rem2 `div` 8
      x0 = rem2 `mod` 8
  in (x0, x1, x2, x3)

siteIndex :: (Int, Int, Int, Int) -> Int
siteIndex (x0, x1, x2, x3) = x0 + 8 * x1 + 64 * x2 + 512 * x3

vshift :: Int -> (Int, Int, Int, Int) -> Int
vshift n (dx0, dx1, dx2, dx3) =
  let (y0, y1, y2, y3) = splitCoords n
      y0' = (y0 + dx0) `mod` 8
      y1' = (y1 + dx1) `mod` 8
      y2' = (y2 + dx2) `mod` 8
      y3' = (y3 + dx3) `mod` 8
  in siteIndex (y0', y1', y2', y3')

ishift :: Int -> Int -> Int -> Int
ishift n dir dist =
  let dx = case dir of
             0 -> (dist, 0, 0, 0)
             1 -> (0, dist, 0, 0)
             2 -> (0, 0, dist, 0)
             _ -> (0, 0, 0, dist)
  in vshift n dx

makeindex :: Int -> IOArray Int Int -> IOArray Int Int -> IO ()
makeindex n parity ind = do
  let dx = splitCoords n
  let loop site iv
        | iv >= vectorlength = return ()
        | otherwise = do
            p <- readArray parity site
            if p /= 0
              then loop (site + 1) iv
              else do
                let s' = vshift site dx
                writeArray ind iv s'
                loop (site + 1) (iv + 1)
  loop 0 0

vgroup :: IOArray Int Matrix -> IO ()
vgroup arr =
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    m <- readArray arr iv
    writeArray arr iv (project m)

vcopy :: IOArray Int Matrix -> IOArray Int Matrix -> IO ()
vcopy src dst =
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    m <- readArray src iv
    writeArray dst iv m

vprod :: IOArray Int Matrix -> IOArray Int Matrix -> IOArray Int Matrix -> IO ()
vprod g1 g2 g3 =
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    m1 <- readArray g1 iv
    m2 <- readArray g2 iv
    writeArray g3 iv (matMul m1 m2)

vsum :: IOArray Int Matrix -> IOArray Int Matrix -> IOArray Int Matrix -> IO ()
vsum g1 g2 g3 =
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    m1 <- readArray g1 iv
    m2 <- readArray g2 iv
    writeArray g3 iv (matAdd m1 m2)

vtprod :: IOArray Int Matrix -> IOArray Int Matrix -> IOArray Int Double -> IO ()
vtprod g1 g2 s =
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    m1 <- readArray g1 iv
    m2 <- readArray g2 iv
    writeArray s iv (vtprodElem m1 m2)

vtrace :: IOArray Int Matrix -> IOArray Int Double -> IO ()
vtrace g s =
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    m <- readArray g iv
    writeArray s iv (vtraceElem m)

getlinks :: IOArray Int Matrix -> IOArray Int Matrix -> Int -> Int -> IOArray Int Int -> IOArray Int Int -> IO ()
getlinks g lattice site link parity myindex = do
  makeindex site parity myindex
  let sft = nsites * link
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    idx <- readArray myindex iv
    m <- readArray lattice (idx + sft)
    writeArray g iv m

getconjugate :: IOArray Int Matrix -> IOArray Int Matrix -> Int -> Int -> IOArray Int Int -> IOArray Int Int -> IO ()
getconjugate g lattice site link parity myindex = do
  makeindex site parity myindex
  let sft = nsites * link
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    idx <- readArray myindex iv
    m <- readArray lattice (idx + sft)
    writeArray g iv (conjugate m)

savelinks :: IOArray Int Matrix -> IOArray Int Matrix -> Int -> Int -> IOArray Int Int -> IOArray Int Int -> IO ()
savelinks g lattice site link parity myindex = do
  makeindex site parity myindex
  let sft = nsites * link
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    idx <- readArray myindex iv
    m <- readArray g iv
    writeArray lattice (idx + sft) m

metro :: IOArray Int Matrix -> IOArray Int Matrix -> Double -> IOArray Int Double -> IOArray Int Double -> IOArray Int Int -> IO Double
metro old trial bias sold snew accepted = do
  expdeltasRef <- newIORef (0.0 :: Double)
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    so <- readArray sold iv
    sn <- readArray snew iv
    let temp = exp (bias * (sn - so))
    modifyIORef' expdeltasRef (+ temp)
    r <- drand48
    writeArray accepted iv (if r < temp then 1 else 0)
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    acc <- readArray accepted iv
    when (acc /= 0) $ do
      sn <- readArray snew iv
      writeArray sold iv sn
      tr <- readArray trial iv
      writeArray old iv tr
  tot <- readIORef expdeltasRef
  return (tot / fromIntegral vectorlength)

ranmat :: IOArray Int Matrix -> IOArray Int Matrix -> IO ()
ranmat g table1 = do
  r <- drand48
  let indexStart = floor (fromIntegral vectorlength * r)
  indexRef <- newIORef indexStart
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    idx <- readIORef indexRef
    let idx' = if idx >= vectorlength then idx - vectorlength else idx
    r2 <- drand48
    t <- readArray table1 idx'
    if r2 < 0.5
      then writeArray g iv t
      else writeArray g iv (conjugate t)
    writeIORef indexRef (idx' + 1)

vtable :: IOArray Int Matrix -> IOArray Int Matrix -> [IOArray Int Matrix] -> IOArray Int Double -> IOArray Int Double -> IOArray Int Int -> Double -> IO ()
vtable table1 table2 mtemp sold snew accepted betaVal = do
  ranmat (mtemp !! 0) table1
  vprod table2 (mtemp !! 0) table1
  vtrace table2 sold
  vtrace table1 snew
  _ <- metro table2 table1 (6.0 * betaVal / fromIntegral groupConst) sold snew accepted
  vcopy table2 table1
  vcopy (mtemp !! 0) table2
  vgroup table1

maketable :: IOArray Int Matrix -> IOArray Int Matrix -> [IOArray Int Matrix] -> IOArray Int Double -> IOArray Int Double -> IOArray Int Int -> Double -> IO ()
maketable table1 table2 mtemp sold snew accepted betaVal = do
  forM_ [0 .. vectorlength - 1] $ \iv -> do
    r1 <- drand48; r2 <- drand48; r3 <- drand48; r4 <- drand48; r5 <- drand48; r6 <- drand48; r7 <- drand48; r8 <- drand48
    let b = betaVal / fromIntegral groupConst
    let t1 = Matrix (b + r1 - 0.5) (r2 - 0.5) (r3 - 0.5) (b + r4 - 0.5) (r5 - 0.5) (r6 - 0.5) (r7 - 0.5) (r8 - 0.5)
    r1' <- drand48; r2' <- drand48; r3' <- drand48; r4' <- drand48; r5' <- drand48; r6' <- drand48; r7' <- drand48; r8' <- drand48
    let t2 = Matrix (b + r1' - 0.5) (r2' - 0.5) (r3' - 0.5) (b + r4' - 0.5) (r5' - 0.5) (r6' - 0.5) (r7' - 0.5) (r8' - 0.5)
    writeArray table1 iv t1
    writeArray table2 iv t2
  vgroup table1
  vgroup table2
  forM_ [0 .. 49] $ \_ -> vtable table1 table2 mtemp sold snew accepted betaVal

staple :: IOArray Int Matrix -> IOArray Int Matrix -> Int -> Int -> [IOArray Int Matrix] -> IOArray Int Int -> IOArray Int Int -> IO ()
staple st lat site link mtemp parity myindex = do
  forM_ [0 .. vectorlength - 1] $ \iv -> writeArray st iv (idMatrix 0.0)
  let site1 = ishift site link 1
  forM_ [0 .. dimConst - 1] $ \link1 -> do
    when (link1 /= link) $ do
      let site2 = ishift site link1 1
      let site4 = ishift site1 link1 (-1)
      let site5 = ishift site link1 (-1)

      getlinks (mtemp !! 0) lat site1 link1 parity myindex
      getconjugate (mtemp !! 1) lat site2 link parity myindex
      vprod (mtemp !! 0) (mtemp !! 1) (mtemp !! 2)
      getconjugate (mtemp !! 0) lat site link1 parity myindex
      vprod (mtemp !! 2) (mtemp !! 0) (mtemp !! 1)
      vsum st (mtemp !! 1) st

      getconjugate (mtemp !! 0) lat site4 link1 parity myindex
      getconjugate (mtemp !! 1) lat site5 link parity myindex
      vprod (mtemp !! 0) (mtemp !! 1) (mtemp !! 2)
      getlinks (mtemp !! 0) lat site5 link1 parity myindex
      vprod (mtemp !! 2) (mtemp !! 0) (mtemp !! 1)
      vsum st (mtemp !! 1) st

monte :: IOArray Int Matrix -> IOArray Int Matrix -> IOArray Int Matrix -> [IOArray Int Matrix] -> IOArray Int Double -> IOArray Int Double -> IOArray Int Int -> IOArray Int Int -> IOArray Int Int -> Double -> IO Double
monte ulinks table1 table2 mtemp sold snew accepted parity myindex betaVal = do
  vtable table1 table2 mtemp sold snew accepted betaVal
  stotRef <- newIORef 0.0
  edsRef <- newIORef 0.0
  iaccRef <- newIORef 0
  forM_ [0 .. 1] $ \color -> do
    forM_ [0 .. dimConst - 1] $ \link -> do
      staple (mtemp !! 4) ulinks color link mtemp parity myindex
      getlinks (mtemp !! 0) ulinks color link parity myindex
      vtprod (mtemp !! 0) (mtemp !! 4) sold
      forM_ [0 .. hitsConst - 1] $ \_ -> do
        ranmat (mtemp !! 1) table1
        vprod (mtemp !! 0) (mtemp !! 1) (mtemp !! 2)
        vtprod (mtemp !! 2) (mtemp !! 4) snew
        e <- metro (mtemp !! 0) (mtemp !! 2) (betaVal / fromIntegral groupConst) sold snew accepted
        modifyIORef' edsRef (+ e)
        forM_ [0 .. vectorlength - 1] $ \iv -> do
          acc <- readArray accepted iv
          modifyIORef' iaccRef (+ acc)
          so <- readArray sold iv
          modifyIORef' stotRef (+ so)
      savelinks (mtemp !! 0) ulinks color link parity myindex

  stotVal <- readIORef stotRef
  edsVal <- readIORef edsRef
  iaccVal <- readIORef iaccRef

  let stot = stotVal / (2.0 * fromIntegral (dimConst - 1) * fromIntegral nlinks * fromIntegral groupConst * fromIntegral hitsConst)
  let acc = (fromIntegral iaccVal / (fromIntegral nlinks * fromIntegral hitsConst)) :: Double
  let eds = edsVal / (2.0 * fromIntegral dimConst * fromIntegral hitsConst)
  printf "stot=%.6f, acc=%.6f, eds=%.6f\n" stot acc eds
  return stot

overrelax :: IOArray Int Matrix -> IOArray Int Matrix -> IOArray Int Matrix -> [IOArray Int Matrix] -> IOArray Int Double -> IOArray Int Double -> IOArray Int Int -> IOArray Int Int -> IOArray Int Int -> Double -> IO Double
overrelax ulinks table1 table2 mtemp sold snew accepted parity myindex betaVal = do
  stotRef <- newIORef 0.0
  edsRef <- newIORef 0.0
  iaccRef <- newIORef 0
  forM_ [0 .. 1] $ \color -> do
    forM_ [0 .. dimConst - 1] $ \link -> do
      staple (mtemp !! 4) ulinks color link mtemp parity myindex
      getlinks (mtemp !! 0) ulinks color link parity myindex
      vcopy (mtemp !! 4) (mtemp !! 1)
      vgroup (mtemp !! 1)
      vprod (mtemp !! 0) (mtemp !! 1) (mtemp !! 2)
      vprod (mtemp !! 1) (mtemp !! 2) (mtemp !! 3)
      forM_ [0 .. vectorlength - 1] $ \iv -> do
        m3 <- readArray (mtemp !! 3) iv
        writeArray (mtemp !! 2) iv (conjugate m3)
      vtprod (mtemp !! 0) (mtemp !! 4) sold
      vtprod (mtemp !! 2) (mtemp !! 4) snew
      e <- metro (mtemp !! 0) (mtemp !! 2) (betaVal / fromIntegral groupConst) sold snew accepted
      modifyIORef' edsRef (+ e)
      forM_ [0 .. vectorlength - 1] $ \iv -> do
        acc <- readArray accepted iv
        modifyIORef' iaccRef (+ acc)
        so <- readArray sold iv
        modifyIORef' stotRef (+ so)
      savelinks (mtemp !! 0) ulinks color link parity myindex

  stotVal <- readIORef stotRef
  edsVal <- readIORef edsRef
  iaccVal <- readIORef iaccRef

  let stot = stotVal / (2.0 * fromIntegral (dimConst - 1) * fromIntegral nlinks * fromIntegral groupConst)
  let acc = (fromIntegral iaccVal / fromIntegral nlinks) :: Double
  let eds = edsVal / (2.0 * fromIntegral dimConst)
  printf "stot=%.6f, acc=%.6f, eds=%.6f\n" stot acc eds
  return stot

renorm :: IOArray Int Matrix -> IO ()
renorm ulinks = do
  forM_ [0 .. 2 * dimConst - 1] $ \octant -> do
    let link = octant * vectorlength
    forM_ [0 .. vectorlength - 1] $ \iv -> do
      m <- readArray ulinks (link + iv)
      writeArray ulinks (link + iv) (project m)

loop :: IOArray Int Matrix -> Int -> Int -> [IOArray Int Matrix] -> IOArray Int Double -> IOArray Int Int -> IOArray Int Int -> IO Double
loop ulinks x y mtemp sold parity myindex = do
  countRef <- newIORef 0
  resultRef <- newIORef 0.0
  forM_ [0 .. 1] $ \color -> do
    forM_ [0 .. dimConst - 1] $ \link1 -> do
      let startLink2 = if x == y then link1 + 1 else 0
      forM_ [startLink2 .. dimConst - 1] $ \link2 -> do
        when (link1 /= link2) $ do
          modifyIORef' countRef (+ 1)
          let corner0 = ishift color link1 x
          let corner = ishift corner0 link2 y
          forM_ [0 .. vectorlength - 1] $ \iv -> do
            writeArray (mtemp !! 0) iv (idMatrix 1.0)
            writeArray (mtemp !! 1) iv (idMatrix 1.0)
            writeArray (mtemp !! 2) iv (idMatrix 1.0)
            writeArray (mtemp !! 3) iv (idMatrix 1.0)
          forM_ [0 .. x - 1] $ \i -> do
            getlinks (mtemp !! 4) ulinks (ishift color link1 i) link1 parity myindex
            vprod (mtemp !! 0) (mtemp !! 4) (mtemp !! 0)
            getconjugate (mtemp !! 4) ulinks (ishift corner link1 (-i - 1)) link1 parity myindex
            vprod (mtemp !! 2) (mtemp !! 4) (mtemp !! 2)
          forM_ [0 .. y - 1] $ \i -> do
            getlinks (mtemp !! 4) ulinks (ishift corner link2 (i - y)) link2 parity myindex
            vprod (mtemp !! 1) (mtemp !! 4) (mtemp !! 1)
            getconjugate (mtemp !! 4) ulinks (ishift color link2 (y - i - 1)) link2 parity myindex
            vprod (mtemp !! 3) (mtemp !! 4) (mtemp !! 3)
          vprod (mtemp !! 0) (mtemp !! 1) (mtemp !! 0)
          vprod (mtemp !! 0) (mtemp !! 2) (mtemp !! 0)
          vtprod (mtemp !! 0) (mtemp !! 3) sold
          forM_ [0 .. vectorlength - 1] $ \iv -> do
            so <- readArray sold iv
            modifyIORef' resultRef (+ so)

  countVal <- readIORef countRef
  resVal <- readIORef resultRef
  let res = resVal / (fromIntegral groupConst * fromIntegral vectorlength * fromIntegral countVal)
  printf " %d by %d loop = %g\n" x y res
  return res

main :: IO ()
main = do
  args <- getArgs
  let betaVal = if not (null args) then read (head args) else 2.3
  srand48 1234

  ulinks <- newArray (0, nlinks - 1) (idMatrix 1.0) :: IO (IOArray Int Matrix)
  parity <- newArray (0, nsites - 1) 0 :: IO (IOArray Int Int)
  table1 <- newArray (0, vectorlength - 1) (idMatrix 1.0) :: IO (IOArray Int Matrix)
  table2 <- newArray (0, vectorlength - 1) (idMatrix 1.0) :: IO (IOArray Int Matrix)

  m0 <- newArray (0, vectorlength - 1) (idMatrix 1.0)
  m1 <- newArray (0, vectorlength - 1) (idMatrix 1.0)
  m2 <- newArray (0, vectorlength - 1) (idMatrix 1.0)
  m3 <- newArray (0, vectorlength - 1) (idMatrix 1.0)
  m4 <- newArray (0, vectorlength - 1) (idMatrix 1.0)
  let mtemp = [m0, m1, m2, m3, m4]

  sold <- newArray (0, vectorlength - 1) 0.0 :: IO (IOArray Int Double)
  snew <- newArray (0, vectorlength - 1) 0.0 :: IO (IOArray Int Double)
  accepted <- newArray (0, vectorlength - 1) 0 :: IO (IOArray Int Int)
  myindex <- newArray (0, vectorlength - 1) 0 :: IO (IOArray Int Int)

  forM_ [0 .. nsites - 1] $ \iv -> do
    let (x0, x1, x2, x3) = splitCoords iv
    let p = (x0 + x1 + x2 + x3) `mod` 2
    writeArray parity iv p

  maketable table1 table2 mtemp sold snew accepted betaVal
  putStrLn "initialization done"
  printf "lattice size %d by %d by %d by %d\n" sizeConst sizeConst sizeConst sizeConst
  printf " vectorlength = %d\n" vectorlength
  printf "group=SU(%d)   beta = %6.4f\n" groupConst betaVal
  putStrLn "-----------------"

  putStrLn "test monte"
  forM_ [0 .. 4] $ \_ -> do
    t0 <- getCPUTime
    forM_ [0 .. 4] $ \_ -> do
      _ <- monte ulinks table1 table2 mtemp sold snew accepted parity myindex betaVal
      return ()
    renorm ulinks
    t1 <- getCPUTime
    let elapsedSec = fromIntegral (t1 - t0) / (1e12 :: Double)
    let microsec = (1000000.0 / (5.0 * fromIntegral nlinks)) * elapsedSec
    printf "running at %g microseconds per link\n" microsec
    _ <- loop ulinks 2 2 mtemp sold parity myindex
    return ()

  putStrLn "test overrelax"
  forM_ [0 .. 4] $ \_ -> do
    t0 <- getCPUTime
    forM_ [0 .. 4] $ \_ -> do
      _ <- overrelax ulinks table1 table2 mtemp sold snew accepted parity myindex betaVal
      return ()
    renorm ulinks
    t1 <- getCPUTime
    let elapsedSec = fromIntegral (t1 - t0) / (1e12 :: Double)
    let microsec = (1000000.0 / (5.0 * fromIntegral nlinks)) * elapsedSec
    printf "running at %g microseconds per link\n" microsec

  putStrLn "all done"
