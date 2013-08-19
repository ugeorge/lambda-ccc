{-# LANGUAGE TypeOperators, GADTs, PatternGuards, ScopedTypeVariables #-}
{-# LANGUAGE ConstraintKinds #-}
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

module LambdaCCC.ToCCC (toCCC) where

import Data.Functor ((<$>))
import Control.Monad (mplus)
import Data.Maybe (fromMaybe)

import Data.IsTy
import Data.Proof.EQ

import LambdaCCC.Misc
import LambdaCCC.CCC
import LambdaCCC.Ty
import LambdaCCC.Lambda
import LambdaCCC.Prim

{--------------------------------------------------------------------
    Conversion
--------------------------------------------------------------------}

-- -- | Rewrite a lambda expression via CCC combinators
-- toCCC' :: E a -> (Unit :-> a)
-- toCCC' a | HasTy <- expHasTy a
--          = convert UnitPat a

toCCC :: E (a :=> b) -> (a :-> b)
toCCC e | (HasTy,HasTy) <- tyHasTy2 a b = to' e
 where
   (a,b) = splitFunTy (expTy e)

to' :: HasTy2 a b => E (a :=> b) -> (a :-> b)
to' (Lam p e) = convert p e
to' e = to' (Lam vp (e :^ ve))
 where
   (vp,ve) = vars "ETA"

-- | Convert @\ p -> e@ to CCC combinators
convert :: HasTy2 a b => Pat a -> E b -> (a :-> b)
convert _ (Const o _) = ConstC o
convert k (Var v) = fromMaybe (error $ "convert: unbound variable: " ++ show v) $
                    convertVar v k
-- convert k (u :# v)   = convert k u &&& convert k v
-- convert k (Const PairP (tu :=> tv :=> _) :^ u :^ v)
--   | (HasTy,HasTy) <- tyHasTy2 tu tv
--   = convert k u &&& convert k v
convert k (u :^ v)   | HasTy <- tyHasTy (domTy (expTy u))
  = applyE @. (convert k u &&& convert k v)
convert k (Lam p e)  | (HasTy,HasTy) <- tyHasTy2 (patTy p) (expTy e)
                     = curryE (convert (k :# p) e)

-- Convert a variable in context
convertVar :: forall b a. HasTy2 a b => V b -> Pat a -> Maybe (a :-> b)
convertVar u = conv
 where
   conv :: forall c. HasTy2 c b => Pat c -> Maybe (c :-> b)
   conv (VarPat v) | Just Refl <- v `tyEq` u = Just Id
                   | otherwise               = Nothing
   conv UnitPat  = Nothing
   conv (p :# q) | (HasTy,HasTy) <- tyHasTy2 (patTy p) (patTy q)
                 = ((@. Exr) <$> conv q) `mplus` ((@. Exl) <$> conv p)
   conv (p :@ q) = conv q `mplus` conv p

-- Alternatively,
-- 
--    conv (p :# q) = descend Exr q `mplus` descend Exl p
--     where
--       descend :: (c :-> d) -> Pat d -> Maybe (c :-> b)
--       descend sel r = (@. sel) <$> conv r

-- Note that we try q before p. This choice cooperates with uncurrying and
-- shadowing.