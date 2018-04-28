{-# LANGUAGE OverloadedStrings #-}
module LogicIR.Backend.Z3.Z3 where

import qualified Data.Map as M
import           Z3.Monad

import LogicIR.Expr
import LogicIR.Fold
import LogicIR.Parser ()

lExprToZ3Ast :: LExpr -> Z3 AST
lExprToZ3Ast =
  foldLExpr (LAlgebra fConst genVar fUnop fBinop fIf fQuant fArray fIsnull fLen)
  where
    fConst c = case c of
      CBool x -> mkBool x
      CInt x -> mkInteger $ toInteger x
      CReal f -> mkRealNum f
      CNil -> error "null constants cannot be used directly with Z3 (see LogicIR.Null)"
    fUnop o a' = do
      a <- a'
      case o of
        NNeg -> mkUnaryMinus a
        LNot -> mkNot a
    fBinop x' o y' = do
      x <- x'
      y <- y'
      case o of
        NAdd     -> mkAdd [x, y]
        NSub     -> mkSub [x, y]
        NMul     -> mkMul [x, y]
        NDiv     -> mkDiv x y
        NRem     -> mkRem x y
        LAnd     -> mkAnd [x, y]
        LOr      -> mkOr [x, y]
        LImpl    -> mkImplies x y
        LEqual   -> mkEq x y
        CEqual   -> mkEq x y
        CLess    -> mkLt x y
        CGreater -> mkGt x y
    fIf c' x' y' = do
      c <- c'
      x <- x'
      y <- y'
      mkIte c x y
    fQuant o x@(Var t _) d' a' = do
      a <- a'
      d <- d'
      case t of
        "int" -> do
          vApp <- genVar x >>= toApp
          case o of
            QAll -> do e <- mkImplies d a
                       mkForallConst [] [vApp] e
            QAny -> do e <- mkAnd [d, a]
                       mkExistsConst [] [vApp] e
        _ -> error $ "unsupported quantifier domain type: " ++ show (o, x)
    fArray x' a' = do
      x <- genVar x'
      a <- a'
      mkSelect x a
    fIsnull (Var (TArray _) x) = genNullVar x
    fIsnull _                  = error "unsupported null check"
    fLen (Var (TArray _) x) = genLenVar x -- TODO: support proper array lengths
    fLen _                  = error "unsupported length"

-- | Get formula's free variables (to be included in model).
type FreeVars = M.Map String AST
freeVars2 :: LExpr -> LExpr -> Z3 FreeVars
freeVars2 l l' = M.unions <$> mapM (foldLExpr freeVarsAlgebra) [l, l']
freeVars :: LExpr -> Z3 FreeVars
freeVars = foldLExpr freeVarsAlgebra
freeVarsAlgebra :: LAlgebra (Z3 FreeVars)
freeVarsAlgebra = LAlgebra fConst fVar fUnop fBinop fIf fQuant fArray fIsnull fLen
  where
    fConst _ = return M.empty
    fVar xVar@(Var _ x) = M.singleton x <$> genVar xVar
    fUnop _ x = x
    fBinop x _ y = M.unions <$> sequence [x, y]
    fIf c x y = M.unions <$> sequence [c, x, y]
    fQuant _ (Var _ x) d a = M.unions . fmap (M.delete x) <$> sequence [a, d]
    fArray x _ = M.unions <$> sequence [fIsnull x, fLen x, fVar x]
    fIsnull x = M.singleton (x ++ "?null") <$> genNullVar x
    fLen (Var (TArray _) x) = M.singleton (x ++ "?length") <$> genLenVar x

-- | Generate a new Z3 variable, depending on the expression's type.
genVar :: Var -> Z3 AST
genVar (Var t x) =
  mkStringSymbol x >>=
    case t of
      "int"    -> mkIntVar
      "bool"   -> mkBoolVar
      "real"   -> mkRealVar
      "[int]"  -> mkArrayVar mkIntSort
      "[real]" -> mkArrayVar mkRealSort
      "[bool]" -> mkArrayVar mkBoolSort
      _        -> error $ "unsupported type: " ++ show t
  where mkArrayVar mkValSort symbol = do
          intSort <- mkIntSort
          valSort <- mkValSort
          arraySort <- mkArraySort intSort valSort
          mkVar symbol arraySort
genNullVar :: String -> Z3 AST
genNullVar s = genVar $ Var "bool" (s ++ "?null")
genLenVar :: String -> Z3 AST
genLenVar s = genVar $ Var "int" (s ++ "?length")
