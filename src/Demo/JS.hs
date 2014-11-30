{-# LANGUAGE CPP, OverloadedStrings #-}
module Demo.JS ( readInputState
               , writeInputState
               , mkRandomInput
               , sDrawButton
               , sRandomButton 
               , drawList
               , displayOutput
               , scaleMax
               , mkCanvas ) where

import Control.Monad
import Control.Applicative
import JavaScript.JQuery
import JavaScript.Canvas hiding (Left, Right)
import GHCJS.Types
import GHCJS.Foreign
import Data.Text (pack, unpack, Text)
import qualified Data.Map as M (empty, insert)
import Data.Maybe (fromJust)
import Demo.Types
import Demo.Links

-- Easily Configurable!
canvasXPadding = 20 :: Double
canvasYPadding = 20 :: Double
scaleMax = 120 :: Double

sRandomButton = select "#randomButton"
sSizeDiv = select "#size"
sStartDiv = select "#start"
sCellsDiv = select "#boxbox"
sDrawButton = select "#drawButton"
sHeadInput = select "#head"
sCanvasBox = select "#drawingbox"
sCanvas = select "#theCanvas" -- dont forget to make it!
sCellNum i = select (pack (template (cellMkName i)))
  where template n = "<div class=\"outer\"><div class=\"inner\">" 
                     ++ (show i) 
                     ++ "</div><input id=\"" 
                     ++ n 
                     ++ "\" type=\"text\" name=\"a\" /></div>"

{- There are two of these because when you are creating elements,
   you must omit the "#" that you use to later select them.
   
   I was using the "#" in the name to both create AND select them
   before, and was getting a "TypeError" in the firefox console
   as a result. Almost drove me crazy :/   -}
cellName :: Int -> String
cellName i = "#hey" ++ (show i)
cellMkName :: Int -> String
cellMkName i = "hey" ++ (show i)

printList :: Either String [LElem] -> IO ()
printList = print . show

showVal sel = fmap (print . unpack) (sel >>= getVal)
pullVal :: IO JQuery -> IO Int
pullVal sel = do s <- fmap unpack (sel >>= getVal)
                 print $ "this pullval: " ++ s
                 return (read s)

readInputState :: IO InputState
readInputState = do start <- pullVal sStartDiv
                    size <- pullVal sSizeDiv
                    print "readinputstate"
                    h <- getHead
                    m <- getMemSt start size 
                    return (InSt start size h m)

mkRandomInput :: IO InputState
mkRandomInput = do showVal sStartDiv
                   showVal sSizeDiv
                   print "mkrandom"
                   start <- pullVal sStartDiv
                   size <- pullVal sSizeDiv
                   ri <- randomInput start size
                   writeInputState ri
                   return ri

getHead :: IO String
getHead = fmap unpack (getVal =<< sHeadInput)

getMemSt :: Int -> Int -> IO MemSt
getMemSt start size = fmap mkMemSt (r start)
  where r i = if i < (start + size)
                 then do c <- readCell i
                         fmap (c:) (r (i+1))  --liftM (:) (readCell i) (r (i+1))
                 else return []

writeInputState :: InputState -> IO ()
writeInputState (InSt i s h m) = mkBoxes i s m >> setHead h

setHead :: String -> IO ()
setHead h = sHeadInput >>= setVal (pack h) >> return ()

readMemSt :: [Cell] -> MemSt
readMemSt = foldr (\(i,s) -> M.insert i (i,s)) M.empty

readCell :: Int -> IO Cell
readCell i = let name = pack (cellName i)
               in fmap (((,) i) . unpack) (print (cellName i) >> (print "ah" >> select name >>= getVal))

writeCell :: Int -> String -> IO ()
writeCell i s = select (pack (cellName i)) >>= setVal (pack s) >> return ()

mkBoxes :: Int -> Int -> MemSt -> IO ()
mkBoxes start size m = clear >> note start size >> r (start + size) size
  where note :: Int -> Int -> IO ()
        note i s = let f x = (setVal ((pack . show) x))
                   in sSizeDiv >>= f s >> sStartDiv >>= f i >> return ()          
        r :: Int -> Int -> IO ()
        r n i = if i > 0
                   then do -- print $ "making box number " ++ (show i) 
                           box <- sCellNum (n - i)
                           parent <- sCellsDiv
                           appendJQuery box parent
                           writeCell i (stringAtIndex i m)
                           r n (i - 1)
                   else return ()
        clear :: IO ()
        clear = sCellsDiv >>= children >>= remove >> return ()

getCanvasDimensions :: IO (Int,Int)
getCanvasDimensions = do
  sh <- getHeight =<< select "#s"
  ah <- getHeight =<< select "#a"
  bh <- getHeight =<< select "#b"
  ch <- getHeight =<< select "#c"
  dw <- getWidth =<< select "#drawingbox"
  let h = floor $ sh - ah - bh - ch - 170
      w = floor $ dw - 13 -- not sure why i need this...
  return (w,h)
  
mkCanvas :: IO ()
mkCanvas = do
  (w,h) <- getCanvasDimensions
  p <- sCanvasBox
  children p >>= remove
  c <- select $ pack $ "<canvas id=\"theCanvas\" width=\""
                       ++ show w
                       ++ "\" height=\""
                       ++ show h
                       ++ "\"></canvas>"
  appendJQuery c p
  return ()

displayOutput :: Either String Layout -> IO ()
displayOutput l = cullError >> case l of
                                 Left er -> printError er
                                 Right ls -> drawList ls

withPadding :: (Double, Double) -> (Double, Double)
withPadding (x,y) = (x - (2 * canvasXPadding), y - (2 * canvasYPadding))

addOffsets :: Double -> (Double, Double) -> Layout -> LayoutD
addOffsets scale (cx,cy) ls = foldr f [] ls
  where f (e, (x, y), os) = let sx = scale * (fromIntegral (fst (getRect ls)))
                                sy = scale * (fromIntegral (snd (getRect ls)))
                                fx = ((cx - sx) / 2) + canvasXPadding
                                fy = ((cy - sy) / 2) + canvasYPadding
                                dx = scale * (fromIntegral x)
                                dy = scale * (fromIntegral y)
                            in (:) (e, (dx + fx, dy + fy), nmap ((* scale) . fromIntegral) os)

type Coord = (Double, Double)

drawList :: Layout -> IO ()
drawList ls = do cints <- getCanvasDimensions
                 let csize = nmap fromIntegral cints
                     cdims = withPadding csize
                     scale = min scaleMax (findScale cdims (getRect ls))
                     (h,w) = csize
                 c <- sCanvas >>= indexArray 0 . castRef >>= getContext
                 save c
                 clearRect 0 0 h w c 
                 restore c
                 let dls = addOffsets scale csize ls
                     r (l:ls) = (drawElem c scale) l >> r ls
                     r _ = return ()
                 r dls

drawElem :: Context -> Double -> (DElem, (Double, Double), (Double, Double)) -> IO ()
drawElem c scale elem = 
  let ((t,i,v), (x, y), (xo, yo)) = elem
  in case t of
       Box -> do save c 
                 strokeRect x (y + (yo / 3)) xo (yo * 2 / 3) c 
                 drawTextFloor ( (x + (xo / 2)) 
                               , (y + (yo / 3) - (yo / 9)))
                               (xo / 2) 
                               (yo / 12) 
                               i c 
                 drawTextCenter ( (x + (xo / 2)
                                , (y + (yo * 2 / 3))))
                                (xo * 4 / 5) 
                                (yo * 5 / 9) 
                                v c 
                 restore c
       Arrow -> return ()
       LoopBack _ -> return ()

cullError = return ()
printError a = return ()

drawTextCenter :: Coord   -- location at which to center the text
               -> Double  -- maximum width of the text
               -> Double  -- maximum height of the text
               -> String  -- the text to be drawn
               -> Context -- the canvas context
               -> IO ()
drawTextCenter (x,y) maxW maxH s c =
  do (a,b) <- setFont maxH maxW s c
     fillText (pack s) (x - (a / 2)) (y + (b / 2)) c

-- same as drawTextCenter, but floors the text at the coordinates
drawTextFloor :: Coord -> Double -> Double -> String -> Context -> IO ()
drawTextFloor (x,y) maxW maxH s c =
  do (a,_) <- setFont maxH maxW s c
     fillText (pack s) (x - (a / 2)) y c

setFont :: Double -> Double -> String -> Context -> IO (Double, Double)
setFont maxHeight maxWidth s c = try maxWidth maxHeight s c

try d f s c = do font (pack ((show ((floor f)::Int)) ++ "pt Calibri")) c
                 x <- measureText (pack s) c
                 if x > d
                    then try d (f - 20) s c
                    else print (show (floor f)) >> return (x,f)