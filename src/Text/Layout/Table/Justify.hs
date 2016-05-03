-- | Produce justified text, which is spread over multiple rows, and join it
-- with other columns. For a simple cut, 'chunksOf' from the `split` package
-- is best suited.
{-# LANGUAGE MultiWayIf #-}
module Text.Layout.Table.Justify
    ( justifyTextsAsGrid
    , justifyWordListsAsGrid
    , justifyText
    , justify

      -- * Vertical alignment of whole columns
    , columnsAsGrid
    , vpadCols

    -- * Helpers
    , dimorphicSummands
    , dimorphicSummandsBy
    ) where

import Control.Arrow
import Data.List

import Text.Layout.Table.Internal
import Text.Layout.Table.Primitives.Basic
import Text.Layout.Table.Position.Internal

-- | Justifies texts and presents the resulting lines in a grid structure (each
-- text in one column).
justifyTextsAsGrid :: [(Int, String)] -> [Row String]
justifyTextsAsGrid = justifyWordListsAsGrid . fmap (second words)

-- | Justifies lists of words and presents the resulting lines in a grid
-- structure (each list of words in one column). This is useful if you don't
-- want to split just at whitespaces.
justifyWordListsAsGrid :: [(Int, [String])] -> [Row String]
justifyWordListsAsGrid = columnsAsGrid top . fmap (uncurry justify)

-- TODO put in fitting module
{- | Merges multiple columns together and merges them to a valid grid without
   holes. The following example clarifies this:

>>> columnsAsGrid top [justifyText 10 "This text will not fit on one line.", ["42", "23"]]
[["This  text","42"],["will   not","23"],["fit on one",""],["line.",""]]

The result is intended to be used with 'Text.Layout.Table.layoutToCells' or with
'Text.Layout.Table.rowGroup'.
-}
columnsAsGrid :: Position V -> [Col [a]] -> [Row [a]]
columnsAsGrid vPos = transpose . vpadCols vPos []

-- | Fill all columns to the same length by aligning at the given position.
vpadCols :: Position V -> a -> [[a]] -> [[a]]
vpadCols vPos x l = fmap fillToMax l
  where
    fillToMax = fillTo $ maximum $ 0 : fmap length l
    fillTo    = let f = case vPos of
                       Start  -> fillEnd
                       Center -> fillBoth
                       End    -> fillStart
                in f x

-- | Uses 'words' to split the text into words and justifies it with 'justify'.
--
-- >>> justifyText 10 "This text will not fit on one line."
-- ["This  text","will   not","fit on one","line."]
--
justifyText :: Int -> String -> [String]
justifyText w = justify w . words

-- | Fits as many words on a line, depending on the given width. Every line, but
-- the last one, gets equally filled with spaces between the words, as far as
-- possible.
justify :: Int -> [String] -> [String]
justify width = mapInit pad (\(_, _, line) -> unwords line) . gather 0 0 []
  where
    pad (len, wCount, line) = unwords $ if len < width
                                        then zipWith (++) line $ dimorphicSpaces (width - len) (pred wCount) ++ [""]
                                        else line

    gather lineLen wCount line ws = case ws of  
        []      | null line -> []
                | otherwise -> [(lineLen, wCount, reverse line)]
        w : ws'             ->
            let wLen   = length w
                newLineLen = lineLen + 1 + wLen
                reinit = gather wLen 1 [w] ws'
            in if | null line           -> reinit
                  | newLineLen <= width -> gather newLineLen (succ wCount) (w : line) ws'
                  | otherwise           -> (lineLen, wCount, reverse line) : reinit

-- | Map inits with the first function and the last one with the last function.
mapInit :: (a -> b) -> (a -> b) -> [a] -> [b]
mapInit _ _ []       = []
mapInit f g (x : xs) = go x xs
  where
    go y []        = [g y]
    go y (y' : ys) = f y : go y' ys

dimorphicSpaces :: Int -> Int -> [String]
dimorphicSpaces = dimorphicSummandsBy spaces

-- | Splits a given number into summands of 2 different values, where the
-- first one is exactly one bigger than the second one. Splitting 40 spaces
-- into 9 almost equal parts would result in:
--
-- >>> dimorphicSummands 40 9
-- [5,5,5,5,4,4,4,4,4]
--
dimorphicSummands :: Int -> Int -> [Int]
dimorphicSummands = dimorphicSummandsBy id

dimorphicSummandsBy :: (Int -> a) -> Int -> Int -> [a]
dimorphicSummandsBy _ _ 0      = []
dimorphicSummandsBy f n splits = replicate r largeS ++ replicate (splits - r) smallS
  where
    (q, r) = n `divMod` splits
    largeS = f $ succ q
    smallS = f q
