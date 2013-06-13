{-# LANGUAGE TypeOperators, GADTs, PatternGuards, ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wall #-}

-- {-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP
-- {-# OPTIONS_GHC -fno-warn-unused-binds   #-} -- TEMP

----------------------------------------------------------------------
-- |
-- Module      :  LambdaCCC.ToCCC
-- Copyright   :  (c) 2013 Tabula, Inc.
-- License     :  BSD3
-- 
-- Maintainer  :  conal@tabula.com
-- Stability   :  experimental
-- 
-- Convert lambda expressions to CCC combinators
----------------------------------------------------------------------

module LambdaCCC.ToCCCPh (toCCC, toCCC') where

import Data.Functor ((<$>))
import Control.Monad (mplus)
import Data.Maybe (fromMaybe)
import Unsafe.Coerce (unsafeCoerce)

import LambdaCCC.Misc
import LambdaCCC.CCC
import LambdaCCC.LambdaPh

{--------------------------------------------------------------------
    Conversion
--------------------------------------------------------------------}

-- | Rewrite a lambda expression via CCC combinators
toCCC :: E a -> (Unit :-> a)
toCCC = convert UnitP

toCCC' :: E (a :=> b) -> (a :-> b)
toCCC' (Lam p e) = convert p e
toCCC' e = toCCC' (Lam vp (e :^ ve))
 where
   (vp,ve) = vars "ETA"

-- | Convert @\ p -> e@ to CCC combinators
convert :: Pat a -> E b -> (a :-> b)
convert _ (Const o)  = Konst o
convert k (Var v)    = fromMaybe (error $ "unbound variable: " ++ show v) $
                       convertVar v k
convert k (u :# v)   = convert k u &&& convert k v
convert k (u :^ v)   = Apply @. (convert k u &&& convert k v)
                  -- = Apply @. convert k (u :# v)
convert k (Lam p e)  = Curry (convert (PairP k p) e)

-- Convert a variable in context
convertVar :: forall b a. V b -> Pat a -> Maybe (a :-> b)
convertVar (V b) = conv
 where
   conv :: forall c. Pat c -> Maybe (c :-> b)
   conv (VarP (V c)) | c == b    = Just (unsafeCoerce Id)
                     | otherwise = Nothing
   conv UnitP = Nothing
   conv (PairP p q) = ((@. Snd) <$> conv q) `mplus` ((@. Fst) <$> conv p)

-- Alternatively,
-- 
--    conv (PairP p q) = descend Snd q `mplus` descend Fst p
--     where
--       descend :: (c :-> d) -> Pat d -> Maybe (c :-> b)
--       descend sel r = (@. sel) <$> conv r

-- Note that we try q before p. This choice cooperates with uncurrying and
-- shadowing.
