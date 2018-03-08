{-# LANGUAGE ScopedTypeVariables #-}
module API where

import Control.Concurrent
import Data.List          (intercalate)
import Data.List.Split    (splitOn)
import Data.Maybe
import Prelude            hiding (log)
import System.IO

import Javawlp.Engine.HelperFunctions
import Javawlp.Engine.Types
import Language.Java.Pretty
import Language.Java.Syntax

import qualified LogicIR.Backend.QuickCheck.API as Test
import qualified LogicIR.Backend.Z3.API         as Z3
import           LogicIR.Expr
import           LogicIR.Frontend.Java          (javaExpToLExpr)
import           LogicIR.Null                   (lExprPreprocessNull)
import           LogicIR.Pretty
import           Model

import Control.DeepSeq
import Control.Exception.Base

-- | Data types.
data Mode = Debug | Release deriving (Eq, Show)

data ParseMode = Raw | File

type Source = String

type EquivImpl = LExpr -> LExpr -> IO Response

type MethodDef = ([TypeDecl], Stmt, TypeEnv)

-- | Calls proveSpec and testSpec on different threads and returns
--   their response. If the function is called in debug mode, it
--   compares the result of testSpec and proveSpec. Otherwise, it
--   returns the answer of the fastest method of the two.
compareSpec :: Mode               -- ^ The execution mode
            -> ParseMode          -- ^ The parsing mode
            -> (FilePath, String) -- ^ Specification 1
            -> (FilePath, String) -- ^ Specification 2
            -> IO Response        -- ^ Result of spec comparison.
compareSpec m pMode methodA methodB = do
    -- Parsing.
    [mA, mB] <- mapM (parseMethod pMode) [methodA, methodB]
    log "\n********************************************************************"
    log $ "MethodA:\n" ++ ppMethodDef mA ++ "\n"
    log $ "MethodB:\n" ++ ppMethodDef mB ++ "\n"
    res <- methodDefToLExpr mA mB "pre"
    case res of
      Left e -> do
        log $ "*** ERROR: " ++ show e
        return $ mkErrorResponse e
      Right (preL, preL') -> do
        log $ "Pre\n" ++ "~~~\n"
        log $ "LExprA:\n" ++ prettyLExpr preL ++ "\n"
        log $ "LExprB:\n" ++ prettyLExpr preL' ++ "\n"
        res' <- methodDefToLExpr mA mB "post"
        case res' of
          Left e' -> do
            log $ "*** ERROR: " ++ show e'
            return $ mkErrorResponse e'
          Right (postL, postL') -> do
            log $ "Post\n" ++ "~~~~\n"
            log $ "LExprA:\n" ++ prettyLExpr postL ++ "\n"
            log $ "LExprB:\n" ++ prettyLExpr postL' ++ "\n"

            mv1 <- newEmptyMVar
            mv2 <- if m == Debug then newEmptyMVar else return mv1
            mapM_ compareSpecHelper [ (mv1, "Z3", Z3.equivalentTo)
                                    , (mv2, "Test", Test.equivalentTo)
                                    ]
            res1 <- readMVar mv1
            res2 <- readMVar mv2 -- if Release, this won't block
            return $ getRes m res1 res2
            where -- | Runs f on a separate thread and stores the result in mv.
            compareSpecHelper (mv, name, impl) = forkIO $ do
                    res <- checkSpec name impl (preL, preL') (postL, postL') 
                    res `seq` putMVar mv res

-- | Makes sure that both Responses are the same, otherwise, if we
--   run in debug mode, an error will be thrown. If not in debug mode,
--   the first given Response (that of the theorem prover) will be
--   returned because the mistake will generally be in testSpec.
getRes :: Mode     -- ^ True if debug mode, False otherwise
       -> Response -- ^ The response from proveSpec
       -> Response -- ^ The response from testSpec
       -> Response -- ^ The final response.
getRes _        Timeout           testRes           = testRes
getRes _        Undefined         testRes           = testRes
getRes _        Equivalent        Equivalent        = Equivalent
getRes _        (NotEquivalent m) (NotEquivalent _) = NotEquivalent m
getRes Release  resp              _                 = resp
getRes Debug    resp              resp'             =
    error $ "proveSpec says " ++ show resp ++ ", testSpec says " ++ show resp'

checkSpec :: String -> EquivImpl -> (LExpr, LExpr) -> (LExpr, LExpr) -> IO Response
checkSpec name equivTo (preL, preL') (postL, postL') = do
    preRes <- preL `equivTo` preL'
    log $ "PreResponse (" ++ name ++ "):\n" ++ show preRes ++ "\n"
    postRes <- postL `equivTo` postL'
    log $ "PostResponse (" ++ name ++ "):\n" ++ show postRes ++ "\n"
    return $ preRes <> postRes

--------------------------------------------------------------------------------

-- Takes a Java source file and a method name and returns the class declarations,
-- Returns the method body and the method's formal parameters.
parseMethod :: ParseMode -> (Source, String) -> IO MethodDef
parseMethod pMode (src, name) = do
    decls <- case pMode of
                Raw  -> parseDeclsRaw src
                File -> parseDecls src
    -- get the method's body (assuming all methods have different names)
    let mbody = fromJust $ getMethod decls (Ident name)
    -- get the method's formal parameters:
    let env = getMethodTypeEnv decls (Ident name)
    -- return the relevant data
    return (decls, mbody, env)

methodDefToLExpr :: MethodDef -> MethodDef -> String -> IO (Either String (LExpr, LExpr))
methodDefToLExpr m1@(decls1, _, env1) m2@(decls2, _, env2) name = do
    -- get pre/post condition
    let (e1, e2) = (extractCond m1 name, extractCond m2 name)
    res :: Either SomeException (LExpr, LExpr) <-
      try . evaluate . force $ (javaExpToLExpr e1 env1 decls1, javaExpToLExpr e2 env2 decls2)
    return $ case res of
      Left e ->
        Left $ show e
      Right (l, l') ->
        Right (lExprPreprocessNull l, lExprPreprocessNull l')
    where extractCond :: MethodDef -> String -> Exp
          extractCond m n = extractExpr $ getMethodCalls m n

-- Get a list of all calls to a method of a specific name from a method definition.
getMethodCalls :: MethodDef -> String -> [MethodInvocation]
getMethodCalls (_, StmtBlock (Block bs), _) name = mapMaybe extractMethodInv bs
    where
        extractMethodInv :: BlockStmt -> Maybe MethodInvocation
        extractMethodInv (BlockStmt (ExpStmt (MethodInv i@(MethodCall (Name [Ident n]) _)))) = if n == name then Just i else Nothing
        extractMethodInv _ = Nothing

-- [pre(a), pre(b), pre(c)] -> (a AND b AND c)
extractExpr :: [MethodInvocation] -> Exp
extractExpr call = combineExprs $ map (\(MethodCall (Name [Ident _]) [a]) -> a) call
    where combineExprs :: [Exp] -> Exp
          combineExprs []     = true
          combineExprs [e]    = e
          combineExprs (e:es) = e &* combineExprs es

--------------------------------- Debugging ------------------------------------
log :: String -> IO ()
log = hPutStrLn stderr

mkErrorResponse :: String -> Response
mkErrorResponse = ErrorResponse . head . splitOn "\nCallStack"

ppMethodDef :: MethodDef -> String
ppMethodDef (typeDecls, stmt, typeEnv) =
  ppTypeEnv typeEnv ++ "\n" ++ prettyPrint stmt

ppTypeEnv :: TypeEnv -> String
ppTypeEnv = intercalate ", " . map ppNT
  where ppNT (n, t) = prettyPrint t ++ " " ++ prettyPrint n