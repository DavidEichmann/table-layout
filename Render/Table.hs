{-# LANGUAGE RecordWildCards #-}
module Render.Table
    ( -- * Layout types and combinators
      LayoutSpec(..)
    , LenSpec(..)
    , PosSpec(..)
    , AlignSpec(..)
    , OccSpec(..)
    , defaultL
    , numL
    , limitL
    , limitLeftL
      -- * Column modification functions
    , pad
    , trimOrPad
    , align
      -- * Column modifaction primitives
    , ColModInfo(..)
    , widthCMI
    , unalignedCMI
    , ensureWidthCMI
    , columnModifier
    , AlignInfo(..)
    , widthAI
    , genColModInfos
    , genAlignInfo
      -- * Basic grid and table layout
    , layoutCells
    , layoutLines
    , layoutString
      -- * Grid modification functions
    , altLines
    , checkeredCells
      -- * Advanced table layout
    , RowGroup(..)
    , layoutTable
    ) where


-- TODO integrate with PrettyPrint/Doc: e.g. color patterns for readability ? could also be done with just the lines
-- TODO

import Data.Bifunctor
import Data.List
import Data.Maybe

{- = Layout types and combinators
   Specify the layout of columns. Layout combinators have a 'L' as postfix.
-}

-- | Determines the layout of a column.
data LayoutSpec = LayoutSpec LenSpec PosSpec AlignSpec

-- | Determines how long a column will be.
data LenSpec = Expand | LimitTo Int

-- | Determines how a column will be positioned.
data PosSpec = LeftPos | RightPos | CenterPos

-- | Determines whether a column will align at a specific letter.
data AlignSpec = AlignAtChar OccSpec | NoAlign

-- | Specifies an occurence of a letter.
data OccSpec = OccSpec Char Int deriving Show

-- | The default layout will allow maximum expand and is positioned on the left.
defaultL :: LayoutSpec
defaultL = LayoutSpec Expand LeftPos NoAlign

-- | Numbers are positioned on the right and aligned on the floating point dot.
numL :: LayoutSpec
numL = LayoutSpec Expand RightPos (AlignAtChar $ OccSpec '.' 0)

-- | Limits the column length and positions according to the given 'PosSpec'.
limitL :: Int -> PosSpec -> LayoutSpec
limitL l pS = LayoutSpec (LimitTo l) pS NoAlign

-- | Limits the column length and positions on the left.
limitLeftL :: Int -> LayoutSpec
limitLeftL i = limitL i LeftPos

--  = Single-cell layout functions.

spaces :: Int -> String
spaces = flip replicate ' '

-- | Assume the given length is greater or equal than the length of the 'String'
-- passed. Pads the given 'String' accordingly, using the position specification.
pad :: Int -> PosSpec -> String -> String
pad l p s = case p of
    LeftPos   -> take l (s ++ repeat ' ')
    RightPos  -> spaces (l - length s) ++ s
    CenterPos -> let fillL  = l - length s
                     (q, r) = fillL `divMod` 2
                 -- Puts more on the right if odd.
                 in spaces q ++ s ++ spaces (q + r)

-- | If the given text is too long, the 'String' will be shortened according to
-- the position specification, also adds some dots to indicate that the column
-- has been trimmed in length, otherwise behaves like 'pad'.
trimOrPad :: Int -> PosSpec -> String -> String
trimOrPad l p s =
    if length s > l
    -- Too long, shorten it.
    then case p of
        -- Show dots left.
        RightPos  -> take l $ ".." ++ s
        -- Show dots right.
        _         -> take l $ take (l - 2) s ++ ".."
    else pad l p s

-- | Align a column by first finding the position to pad with and then padding
-- the missing lengths to the maximum value. If no such position is found, it
-- will align it such that it gets aligned before that position.
align :: OccSpec -> AlignInfo -> String -> String
align oS (AlignInfo l r) s = case splitAtOcc oS s of
    (ls, rs) -> spaces (l - length ls) ++ ls ++ case rs of
        -- No alignment character found.
        [] -> (if r == 0 then "" else spaces r)
        _  -> rs ++ spaces (r - length rs)

splitAtOcc :: OccSpec -> String -> (String, String)
splitAtOcc (OccSpec c occ) = first reverse . go 0 []
  where
    go n ls xs = case xs of
        []      -> (ls, [])
        x : xs' -> if c == x
                   then if n == occ
                        then (ls, xs)
                        else go (succ n) (x : ls) xs'
                   else go n (x : ls) xs'

-- | Specifies how a column should be modified.
data ColModInfo = FillAligned OccSpec AlignInfo
                | FillTo Int
                | ShortenTo Int (Maybe (OccSpec, AlignInfo))
                deriving Show

-- | Get the exact width after the modification.
widthCMI :: ColModInfo -> Int
widthCMI cmi = case cmi of
    FillAligned _ ai -> widthAI ai
    FillTo maxLen    -> maxLen
    ShortenTo lim _  -> lim

-- | Remove alignment from a 'ColModInfo
unalignedCMI :: ColModInfo -> ColModInfo
unalignedCMI cmi = case cmi of
    FillAligned _ ai -> FillTo $ widthAI ai
    ShortenTo i _    -> ShortenTo i Nothing
    _                -> cmi

-- | Ensures that the modification provides a minimum width, but only if it is
-- not limited.
ensureWidthCMI :: Int -> PosSpec -> ColModInfo -> ColModInfo
ensureWidthCMI w posSpec cmi = case cmi of
    FillAligned oS ai@(AlignInfo lw rw) ->
        let neededW = widthAI ai - w
        in if neededW >= 0
           then cmi
           else FillAligned oS $ case posSpec of
               LeftPos   -> AlignInfo lw (rw + neededW)
               RightPos  -> AlignInfo (lw + neededW) rw
               CenterPos -> let (q, r) = neededW `divMod` 2 
                            in AlignInfo (q + lw) (q + rw + r)
    FillTo maxLen                     -> FillTo (max maxLen w)
    _                                 -> cmi

-- | Generates a function which modifies a given 'String' according to
-- 'PosSpec' and 'ColModInfo'.
columnModifier :: PosSpec -> ColModInfo -> (String -> String)
columnModifier posSpec lenInfo = case lenInfo of
    FillAligned oS ai -> align oS ai
    FillTo maxLen     -> pad maxLen posSpec
    ShortenTo lim mT  -> trimOrPad lim posSpec . maybe id (uncurry align) mT

-- | Specifies the length before and after a letter.
data AlignInfo = AlignInfo Int Int deriving Show

-- | The column width when using the 'AlignInfo'.
widthAI :: AlignInfo -> Int
widthAI (AlignInfo l r) = l + r

-- | Since determining a maximum in two directions is not possible, a 'Monoid'
-- instance is provided.
instance Monoid AlignInfo where
    mempty = AlignInfo 0 0
    mappend (AlignInfo ll lr) (AlignInfo rl rr) = AlignInfo (max ll rl) (max lr rr)

-- | Derive the 'ColModInfo' by using layout specifications and looking at the
-- table.
genColModInfos :: [(LenSpec, AlignSpec)] -> [[String]] -> [ColModInfo]
genColModInfos specs cells = zipWith ($) (fmap fSel specs) $ transpose cells
  where
    fSel specs = case specs of
        (Expand   , NoAlign       ) -> FillTo . maximum . fmap length
        (Expand   , AlignAtChar oS) -> FillAligned oS . foldMap (genAlignInfo oS)
        (LimitTo i, NoAlign       ) -> const $ ShortenTo i Nothing
        (LimitTo i, AlignAtChar oS) -> ShortenTo i . Just . (,) oS . foldMap (genAlignInfo oS)
-- | Generate the 'AlignInfo' of a cell using the 'OccSpec'.
genAlignInfo :: OccSpec -> String -> AlignInfo
genAlignInfo occSpec s = AlignInfo <$> length . fst <*> length . snd $ splitAtOcc occSpec s

-----------------------
-- Basic layout
-----------------------

-- | Modifies cells according to the given 'LayoutSpec'.
layoutCells :: [LayoutSpec] -> [[String]] -> [[String]]
layoutCells specs tab = zipWith apply tab
                        . repeat
                        . zipWith columnModifier (map (\(LayoutSpec _ posSpec _) -> posSpec) specs)
                        $ genColModInfos (map (\(LayoutSpec lenSpec _ alignSpec) -> (lenSpec, alignSpec)) specs) tab
  where
    apply = zipWith $ flip ($)

-- | Behaves like 'layoutCells' but produces lines.
layoutLines :: [LayoutSpec] -> [[String]] -> [String]
layoutLines specs tab = map unwords $ layoutCells specs tab

-- | Behaves like 'layoutCells' but produces a 'String'.
layoutString :: [LayoutSpec] -> [[String]] -> String
layoutString ls t = intercalate "\n" $ layoutLines ls t

--  = Grid modifier functions

-- | Applies functions alternating to given lines. This makes it easy to color
-- lines to improve readability in a row.
altLines :: [a -> b] -> [a] -> [b]
altLines = zipWith ($) . cycle

-- | Applies functions alternating to cells for every line, every other line
-- gets shifted by one. This is useful for distinguishability of single cells in
-- a grid arrangement.
checkeredCells  :: (a -> b) -> (a -> b) -> [[a]] -> [[b]]
checkeredCells f g = zipWith altLines $ cycle [[f, g], [g, f]]

------------------
-- Advanced layout
------------------

-- | Groups rows together, which are not seperated from each other. Optionally
-- a label with vertical text on the left can be added.
data RowGroup = RowGroup
              { cells     :: [[String]] 
              , optVLabel :: Maybe String
              }

data TableStyle = TableStyle
                { headerSepH   :: Char
                , headerSepLC  :: Char
                , headerSepRC  :: Char
                , headerSepC   :: Char
                , headerTopL   :: Char
                , headerTopR   :: Char
                , headerTopC   :: Char
                , headerTopH   :: Char
                , headerV      :: Char
                , groupV       :: Char
                , groupSepH    :: Char
                , groupSepC    :: Char
                , groupSepLC   :: Char
                , groupSepRC   :: Char
                , groupTopC    :: Char
                , groupTopL    :: Char
                , groupTopR    :: Char
                , groupTopH    :: Char
                , groupBottomC :: Char
                , groupBottomL :: Char
                , groupBottomR :: Char
                , groupBottomH :: Char
                }

layoutTable :: [RowGroup] -> Maybe ([String], [PosSpec]) -> TableStyle -> [LayoutSpec] -> [String]
layoutTable rGs optHeaderInfo (TableStyle { .. }) specs =
    topLine : addHeaderLines (rowGroupLines ++ [bottomLine])
  where
    -- Line helpers
    vLine hs d                  = vLineDetail hs d d d
    vLineDetail hS dL d dR cols = intercalate [hS] $ [dL] : intersperse [d] cols ++ [[dR]]

    -- Spacers consisting of columns of seperator elements.
    genHSpacers c    = map (flip replicate c) colWidths
    hHeaderSpacers   = genHSpacers headerSepH
    hGroupSpacers = genHSpacers groupSepH


    -- Vertical seperator lines
    topLine       = vLineDetail realTopH realTopL realTopC realTopR $ genHSpacers realTopH
    bottomLine    = vLineDetail groupSepH groupBottomL groupBottomC groupBottomR $ genHSpacers groupBottomH
    groupSepLine  = groupSepLC : groupSepH : intercalate [groupSepH, groupSepC, groupSepH] hGroupSpacers ++ [groupSepH, groupSepRC]
    headerSepLine = vLineDetail headerSepH headerSepLC headerSepC headerSepRC hHeaderSpacers

    -- Vertical content lines
    rowGroupLines = intercalate [groupSepLine] $ map (map (vLine ' ' groupV) . applyRowMods . cells) rGs

    -- Optional functions for the header
    (addHeaderLines, fitHeaderIntoCMIs, realTopH, realTopL, realTopC, realTopR) = case optHeaderInfo of
        Just (h, headerPosSpecs) ->
            let headerLine    = vLine ' ' headerV (apply h headerRowMods)
                headerRowMods = zipWith columnModifier headerPosSpecs $ map unalignedCMI cMIs
            in
            ( (headerLine :) . (headerSepLine :)
            , zipWith ($) (zipWith ($) (map (ensureWidthCMI . length) h) posSpecs)
            , headerTopH
            , headerTopL
            , headerTopC
            , headerTopR
            )
        Nothing ->
            ( id
            , id
            , groupTopH
            , groupTopL
            , groupTopC
            , groupTopR
            )

    posSpecs         = map (\(LayoutSpec _ posSpec _) -> posSpec) specs
    applyRowMods xss = zipWith apply xss $ repeat rowMods
    rowMods          = zipWith columnModifier posSpecs cMIs
    cMIs             = fitHeaderIntoCMIs $ genColModInfos (map (\(LayoutSpec lenSpec _ alignSpec) -> (lenSpec, alignSpec)) specs)
                                         $ concatMap cells rGs
    colWidths        = map widthCMI cMIs
    apply            = zipWith $ flip ($)

asciiRoundS :: TableStyle
asciiRoundS = TableStyle 
            { headerSepH   = '='
            , headerSepLC  = ':'
            , headerSepRC  = ':'
            , headerSepC   = '|'
            , headerTopL   = '.'
            , headerTopR   = '.'
            , headerTopC   = '.'
            , headerTopH   = '-'
            , headerV      = '|'
            , groupV       = '|'
            , groupSepH    = '-'
            , groupSepC    = '+'
            , groupSepLC   = ':'
            , groupSepRC   = ':'
            , groupTopC    = '.'
            , groupTopL    = '.'
            , groupTopR    = '.'
            , groupTopH    = '-'
            , groupBottomC = '\''
            , groupBottomL = '\''
            , groupBottomR = '\''
            , groupBottomH = '-'
            }

-- | Uses special unicode characters to draw clean boxes. 
unicodeS :: TableStyle
unicodeS = TableStyle
         { headerSepH   = '═'
         , headerSepLC  = '╞'
         , headerSepRC  = '╡'
         , headerSepC   = '╪'
         , headerTopL   = '┌'
         , headerTopR   = '┐'
         , headerTopC   = '┬'
         , headerTopH   = '─'
         , headerV      = '│'
         , groupV       = '│'
         , groupSepH    = '─'
         , groupSepC    = '┼'
         , groupSepLC   = '├'
         , groupSepRC   = '┤'
         , groupTopC    = '┬'
         , groupTopL    = '┌'
         , groupTopR    = '┐'
         , groupTopH    = '─'
         , groupBottomC = '┴'
         , groupBottomL = '└'
         , groupBottomR = '┘'
         , groupBottomH = '─'
         }

unicodeBoldHeaderS :: TableStyle
unicodeBoldHeaderS = unicodeS
                   { headerSepH  = '━'
                   , headerSepLC = '┡'
                   , headerSepRC = '┩'
                   , headerSepC  = '╇'
                   , headerTopL  = '┏'
                   , headerTopR  = '┓'
                   , headerTopC  = '┳'
                   , headerTopH  = '━'
                   , headerV     = '┃'
                   }

unicodeRoundS :: TableStyle
unicodeRoundS = unicodeS
              { groupTopL = roundedTL
              , groupTopR = roundedTR
              , groupBottomL = roundedBL
              , groupBottomR = roundedBR
              , headerTopL = roundedTL
              , headerTopR = roundedTR
              }
  where
    roundedTL = '╭'
    roundedTR = '╮'
    roundedBL = '╰'
    roundedBR = '╯'

unicodeBoldS :: TableStyle
unicodeBoldS = TableStyle
             { headerSepH   = '━'
             , headerSepLC  = '┣'
             , headerSepRC  = '┫'
             , headerSepC   = '╋'
             , headerTopL   = '┏'
             , headerTopR   = '┓'
             , headerTopC   = '┳'
             , headerTopH   = '━'
             , headerV      = '┃'
             , groupV       = '┃'
             , groupSepH    = '━'
             , groupSepC    = '╋'
             , groupSepLC   = '┣'
             , groupSepRC   = '┫'
             , groupTopC    = '┳'
             , groupTopL    = '┏'
             , groupTopR    = '┓'
             , groupTopH    = '━'
             , groupBottomC = '┻'
             , groupBottomL = '┗'
             , groupBottomR = '┛'
             , groupBottomH = '━'
             }

unicodeBoldStripedS :: TableStyle
unicodeBoldStripedS = unicodeBoldS { groupSepH = '-', groupSepC = '┃', groupSepLC = '┃', groupSepRC = '┃' }
