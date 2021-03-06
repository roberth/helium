{-# OPTIONS_GHC -fno-warn-orphans #-}
{-| Module      :  ImportEnvironment
    License     :  GPL

    Maintainer  :  helium@cs.uu.nl
    Stability   :  experimental
    Portability :  portable
-}

module Helium.ModuleSystem.ImportEnvironment where

import qualified Data.Map as M
import Helium.Utils.Utils (internalError)
import Helium.Syntax.UHA_Syntax -- (Name)
import Helium.Syntax.UHA_Utils
import Top.Types
import Helium.Parser.OperatorTable
import Helium.StaticAnalysis.Messages.Messages () -- instance Show Name
import Helium.StaticAnalysis.Heuristics.RepairHeuristics (Siblings)
import Helium.StaticAnalysis.Directives.TS_CoreSyntax
import Data.List 
import Data.Maybe (catMaybes)
import Data.Function (on)

type TypeEnvironment             = M.Map Name TpScheme
type ValueConstructorEnvironment = M.Map Name TpScheme
type TypeConstructorEnvironment  = M.Map Name Int
type TypeSynonymEnvironment      = M.Map Name (Int, Tps -> Tp)
type ClassMemberEnvironment      = M.Map Name [(Name, Bool)]

type ImportEnvironments = [ImportEnvironment]
data ImportEnvironment  = 
     ImportEnvironment { -- types
                         typeConstructors  :: TypeConstructorEnvironment
                       , typeSynonyms      :: TypeSynonymEnvironment
                       , typeEnvironment   :: TypeEnvironment       
                         -- values
                       , valueConstructors :: ValueConstructorEnvironment
                       , operatorTable     :: OperatorTable
                         -- type classes
                       , classEnvironment  :: ClassEnvironment
                       , classMemberEnvironment :: ClassMemberEnvironment                       
                         -- other
                       , typingStrategies  :: Core_TypingStrategies 
                       }

emptyEnvironment :: ImportEnvironment
emptyEnvironment = ImportEnvironment 
   { typeConstructors  = M.empty
   , typeSynonyms      = M.empty
   , typeEnvironment   = M.empty
   , valueConstructors = M.empty
   , operatorTable     = M.empty
   , classEnvironment  = emptyClassEnvironment
   , classMemberEnvironment = M.empty
   , typingStrategies  = [] 
   }
                                              
addTypeConstructor :: Name -> Int -> ImportEnvironment -> ImportEnvironment                      
addTypeConstructor name int importenv = 
   importenv {typeConstructors = M.insert name int (typeConstructors importenv)} 

-- add a type synonym also to the type constructor environment   
addTypeSynonym :: Name -> (Int,Tps -> Tp) -> ImportEnvironment -> ImportEnvironment                      
addTypeSynonym name (arity, function) importenv = 
   importenv { typeSynonyms     = M.insert name (arity, function) (typeSynonyms importenv)
             , typeConstructors = M.insert name arity (typeConstructors importenv)
             } 

addType :: Name -> TpScheme -> ImportEnvironment -> ImportEnvironment                      
addType name tpscheme importenv = 
   importenv {typeEnvironment = M.insert name tpscheme (typeEnvironment importenv)}

addToTypeEnvironment :: TypeEnvironment -> ImportEnvironment -> ImportEnvironment
addToTypeEnvironment new importenv =
   importenv {typeEnvironment = typeEnvironment importenv `M.union` new} 
   
addValueConstructor :: Name -> TpScheme -> ImportEnvironment -> ImportEnvironment                      
addValueConstructor name tpscheme importenv = 
   importenv {valueConstructors = M.insert name tpscheme (valueConstructors importenv)}

addOperator :: Name -> (Int,Assoc) -> ImportEnvironment -> ImportEnvironment  
addOperator name pair importenv = 
   importenv {operatorTable = M.insert name pair (operatorTable importenv) } 
   
setValueConstructors :: M.Map Name TpScheme -> ImportEnvironment -> ImportEnvironment  
setValueConstructors new importenv = importenv {valueConstructors = new} 

setTypeConstructors :: M.Map Name Int -> ImportEnvironment -> ImportEnvironment     
setTypeConstructors new importenv = importenv {typeConstructors = new}

setTypeSynonyms :: M.Map Name (Int,Tps -> Tp) -> ImportEnvironment -> ImportEnvironment  
setTypeSynonyms new importenv = importenv {typeSynonyms = new}

setTypeEnvironment :: M.Map Name TpScheme -> ImportEnvironment -> ImportEnvironment 
setTypeEnvironment new importenv = importenv {typeEnvironment = new}

setOperatorTable :: OperatorTable -> ImportEnvironment -> ImportEnvironment 
setOperatorTable new importenv = importenv {operatorTable = new}

getOrderedTypeSynonyms :: ImportEnvironment -> OrderedTypeSynonyms
getOrderedTypeSynonyms importEnvironment = 
   let synonyms = let insertIt name = M.insert (show name)
                  in M.foldWithKey insertIt M.empty (typeSynonyms importEnvironment)
       ordering = fst (getTypeSynonymOrdering synonyms)
   in (ordering, synonyms)

setClassMemberEnvironment :: ClassMemberEnvironment -> ImportEnvironment -> ImportEnvironment
setClassMemberEnvironment new importenv = importenv { classMemberEnvironment = new }

setClassEnvironment :: ClassEnvironment -> ImportEnvironment -> ImportEnvironment
setClassEnvironment new importenv = importenv { classEnvironment = new }

addTypingStrategies :: Core_TypingStrategies -> ImportEnvironment -> ImportEnvironment  
addTypingStrategies new importenv = importenv {typingStrategies = new ++ typingStrategies importenv}

removeTypingStrategies :: ImportEnvironment -> ImportEnvironment  
removeTypingStrategies importenv = importenv {typingStrategies = []}

getSiblingGroups :: ImportEnvironment -> [[String]]
getSiblingGroups importenv = 
   [ xs | Siblings xs <- typingStrategies importenv ]

getSiblings :: ImportEnvironment -> Siblings
getSiblings importenv =
   let f s = [ (s, ts) | ts <- findTpScheme (nameFromString s) ]
       findTpScheme n = 
          catMaybes [ M.lookup n (valueConstructors importenv)
                    , M.lookup n (typeEnvironment   importenv)
                    ]
   in map (concatMap f) (getSiblingGroups importenv) 
         
combineImportEnvironments :: ImportEnvironment -> ImportEnvironment -> ImportEnvironment
combineImportEnvironments (ImportEnvironment tcs1 tss1 te1 vcs1 ot1 ce1 cm1 xs1) (ImportEnvironment tcs2 tss2 te2 vcs2 ot2 ce2 cm2 xs2) = 
   ImportEnvironment 
      (tcs1 `exclusiveUnion` tcs2) 
      (tss1 `exclusiveUnion` tss2)
      (te1  `exclusiveUnion` te2 )
      (vcs1 `exclusiveUnion` vcs2)
      (ot1  `exclusiveUnion` ot2)
      (M.unionWith combineClassDecls ce1 ce2)
      (cm1 `exclusiveUnion` cm2)
      (xs1 ++ xs2)

combineImportEnvironmentList :: ImportEnvironments -> ImportEnvironment
combineImportEnvironmentList = foldr combineImportEnvironments emptyEnvironment
      
exclusiveUnion :: Ord key => M.Map key a -> M.Map key a -> M.Map key a
exclusiveUnion m1 m2 =
   let keys = M.keys (M.intersection m1 m2)
       f m  = foldr (M.update (const Nothing)) m keys
   in f m1 `M.union` f m2

containsClass :: ClassEnvironment -> Name -> Bool
containsClass cEnv n = M.member (getNameName n) cEnv
{-
-- Bastiaan:
-- For the moment, this function combines class-environments.
-- The only instances that are added to the standard instances 
-- are the derived Show instances (Show has no superclasses).
-- If other instances are added too, then the class environment
-- should be split into a class declaration environment, and an
-- instance environment.-}
combineClassDecls :: ([[Char]],[(Predicate,[Predicate])]) -> 
                     ([[Char]],[(Predicate,[Predicate])]) ->
                     ([[Char]],[(Predicate,[Predicate])])
combineClassDecls (super1, inst1) (super2, inst2)
   | super1 == super2 = (super1, inst1 ++ inst2)
   | otherwise        = internalError "ImportEnvironment.hs" "combineClassDecls" "cannot combine class environments"

-- Bastiaan:
-- Create a class environment from the dictionaries in the import environment
createClassEnvironment :: ImportEnvironment -> ClassEnvironment
createClassEnvironment importenv = 
    let  dicts = map (drop (length dictPrefix) . show) 
               . M.keys 
               . M.filterWithKey isDict 
               $ typeEnvironment importenv
         isDict n _ = dictPrefix `isPrefixOf` show n
         dictPrefix = "$dict"
         -- classes = ["Eq","Num","Ord","Enum","Show"]
         -- TODO: put $ between class name and type in dictionary name
         --  i.e. $dictEq$Int instead of $dictEqInt
         splitDictName ('E':'q':t) = ("Eq", t)
         splitDictName ('N':'u':'m':t) = ("Num", t)
         splitDictName ('O':'r':'d':t) = ("Ord", t)
         splitDictName ('E':'n':'u':'m':t) = ("Enum", t)
         splitDictName ('S':'h':'o':'w':t) = ("Show", t)
         splitDictName x = internalError "ImportEnvironment" "splitDictName" ("illegal dictionary: " ++ show x)
         arity s | s == "()" = 0
                 | isTupleConstructor s = length s - 1
                 | otherwise = M.findWithDefault
                                  (internalError "ImportEnvironment" "splitDictName" ("unknown type constructor: " ++ show s))                            
                                  (nameFromString s)
                                  (typeConstructors importenv) 
         dictTuples = [ (c, makeInstance c (arity t) t) 
                      | d <- dicts, let (c, t) = splitDictName d 
                      ]
         
         classEnv = foldr 
                    (\(className, inst) e -> insertInstance className inst e) 
                    superClassRelation 
                    dictTuples
    in classEnv

superClassRelation :: ClassEnvironment
superClassRelation = M.fromList
   [ ("Num",  ( ["Eq","Show"],   []))
   , ("Enum", ( [],              []))
   , ("Eq" ,  ( [],              []))
   , ("Ord",  ( ["Eq"],          []))
   , ("Show", ( [],              []))
   ]

makeInstance :: String -> Int -> String -> Instance
makeInstance className nrOfArgs tp =
   let tps = take nrOfArgs [ TVar i | i <- [0..] ] 
   in ( Predicate className (foldl TApp (TCon tp) tps)
      , [ Predicate className x | x <- tps ] 
      )
    
-- added for holmes
holmesShowImpEnv :: Module -> ImportEnvironment -> String
holmesShowImpEnv module_ (ImportEnvironment _ _ te _ _ _ _ _) =
      concat functions
    where
       localName = getModuleName module_
       functions =
          let (xs, ys) = partition (isIdentifierName . fst) (M.assocs te)
              list     = map (\(n,_) -> getHolmesName localName n) (ys++xs)
          in map (++ ";") list

instance Show ImportEnvironment where
   show (ImportEnvironment tcs tss te vcs ot ce cm _) = 
      unlines (concat [ fixities
                      , datatypes
                      , typesynonyms
                      , theValueConstructors
                      , functions
                      , classes
                      , classmembers
                      ])
    where
       fixities =    
          let sorted  = let cmp (name, (priority, associativity)) = (10 - priority, associativity, not (isOperatorName name), name)
                        in sortBy (compare `on` cmp) (M.assocs ot)
              grouped = groupBy ((==) `on` snd) sorted
              list = let f ((name, (priority, associativity)) : rest) =
                            let names  = name : map fst rest 
                                prefix = (case associativity of
                                             AssocRight -> "infixr"
                                             AssocLeft  -> "infixl"
                                             AssocNone  -> "infix "
                                         )++" "++ show priority ++ " "
                            in prefix ++ foldr1 (\x y -> x++", "++y) (map showNameAsOperator names)
                         f [] = error "Pattern match failure in ModuleSystem.ImportEnvironment"   
                     in map f grouped          
          in showWithTitle "Fixity declarations" list
       
       datatypes = 
          let allDatas = filter ((`notElem` M.keys tss). fst) (M.assocs tcs)
              f (n,i)  = unwords ("data" : showNameAsVariable n : take i variableList)
          in showWithTitle "Data types" (showEm f allDatas)
       
       typesynonyms =
          let f (n,(i,g)) = let tcons =  take i (map TCon variableList)
                            in unwords ("type" : showNameAsVariable n : map show tcons ++ ["=", show (g tcons)])               
          in showWithTitle "Type synonyms" (showEm f (M.assocs tss))
                 
       theValueConstructors =
          let f (n,t) = showNameAsVariable n ++ " :: "++show t      
          in showWithTitle "Value constructors" (showEm f (M.assocs vcs))   
                 
       functions = 
          let f (n,t) = showNameAsVariable n ++ " :: "++show t
          in showWithTitle "Functions" (showEm f (M.assocs te))                
       
       classes = 
          let f = undefined 
          in showWithTitle "Classes" (map f (M.assocs ce))
          
       classmembers = 
          let f = undefined
          in showWithTitle "Class members" (showEm f (M.assocs cm))
          
       showWithTitle title xs
          | null xs   = []
          | otherwise = (title++":") : map ("   "++) xs
   
       showEm showf aMap = map showf (part2 ++ part1)
         where
            (part1, part2) = partition (isIdentifierName . fst) aMap
         
instance Ord Assoc where
  x <= y = let f :: Assoc -> Int
               f AssocLeft  = 0
               f AssocRight = 1
               f AssocNone  = 2
           in f x <= f y
