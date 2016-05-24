module Text.Layout.Table.Internal where

import Data.Default.Class
import Data.Default.Instances.Base

import Text.Layout.Table.Position
import Text.Layout.Table.Primitives.Basic

-- | Groups rows together, which are not seperated from each other.
newtype RowGroup = RowGroup
                 { rows     :: [[String]] 
                 }

{-# DEPRECATED rowGroup "Use rowG or rowsG instead." #-} 
-- | Construct a row group from a list of rows.
rowGroup :: [Row String] -> RowGroup
rowGroup = RowGroup

-- | Group the given rows together.
rowsG :: [Row String] -> RowGroup
rowsG = RowGroup

-- | Make a group of a single row.
rowG :: Row String -> RowGroup
rowG = RowGroup . (: [])

-- | Specifies how a header is layout, by omitting the cut mark it will use the
-- one specified in the 'Text.Layout.Primitives.Column.ColSpec' like the other
-- cells in that column.
data HeaderColSpec = HeaderColSpec (Position H) (Maybe CutMark)

headerColumn :: Position H -> Maybe CutMark -> HeaderColSpec
headerColumn = HeaderColSpec

-- | Header columns are usually centered.
instance Default HeaderColSpec where
    def = headerColumn center def

-- | An alias for lists, conceptually for values with a horizontal arrangement.
type Row a = [a]

-- | An alias for lists, conceptually for values with a vertical arrangement.
type Col a = [a]
