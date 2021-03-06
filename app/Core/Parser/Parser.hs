{-# LANGUAGE BlockArguments #-}
module Core.Parser.Parser where
  import Text.Parsec
  import Text.Parsec.Expr
  import Text.Parsec.Char
  import Text.Parsec.String
  import qualified Text.Parsec.Token as Token
  import Text.Parsec.Language (emptyDef)
  import Text.Parsec.Token (GenTokenParser)
  import Data.Functor.Identity (Identity)
  import Control.Applicative (Alternative(some))
  import Core.Parser.AST
  import Data.List

  {- LEXER PART -}
  languageDef =
    emptyDef { Token.commentStart    = "/*"
              , Token.commentEnd      = "*/"
              , Token.commentLine     = "//"
              , Token.identStart      = letter
              , Token.identLetter     = alphaNum
              , Token.reservedNames   = ["func", "return", ":=", "struct", "=", "const", "import"]
              , Token.reservedOpNames = ["+", "-", "*", "/", ":", ".", "(", ")", "[", "]"] }

  lexer :: GenTokenParser String u Identity
  lexer = Token.makeTokenParser languageDef

  identifier :: Parser String
  identifier = Token.identifier lexer

  reserved :: String -> Parser ()
  reserved = Token.reserved lexer

  reservedOp :: String -> Parser ()
  reservedOp = Token.reservedOp lexer

  parens :: Parser a -> Parser a
  parens = Token.parens lexer

  integer :: Parser Integer
  integer = Token.integer lexer

  whiteSpace :: Parser ()
  whiteSpace = Token.whiteSpace lexer

  comma :: Parser String
  comma = Token.comma lexer

  semi :: Parser String
  semi = Token.semi lexer

  {- PARSER PART -}

  parser :: Parser Statement
  parser = whiteSpace >> statement

  -- Statement parsing

  statement :: Parser Statement
  statement
    = choice [
      import', try modify, assign, Expression <$> expression,
      returnE, block, function
    ]

  import' :: Parser Statement
  import' = do
    reserved "import"
    name <- sepBy identifier (char '.')
    return . Import $ intercalate "/" name ++ ".love"

  returnE :: Parser Statement
  returnE = do
    reserved "return"
    Return <$> expression

  block :: Parser Statement
  block = Sequence <$> Token.braces lexer (many statement)

  assign :: Parser Statement
  assign = try $ do
    var <- identifier
    reserved ":="
    Assign var <$> expression

  list :: Parser Expression
  list = List <$> Token.brackets lexer (Token.commaSep lexer expression)

  modifyID :: Parser Expression
  modifyID = try (do
    x <- identifier
    reservedOp "."
    Property (Var x) <$> identifier) <|> (Var <$> identifier)

  modify :: Parser Statement
  modify = try $ do
    var <- modifyID
    reserved "="
    Modify var <$> expression

  function :: Parser Statement
  function = do
    reserved "func"
    name <- identifier
    args <- parens (Token.commaSep lexer identifier)
    Function name args <$> statement

  -- Expression parsing

  expression :: Parser Expression
  expression = buildExpressionParser table term

  stringLit :: Parser Expression
  stringLit = do
    char '"'
    str <- many (noneOf "\"")
    char '"'
    return $ String str

  floatLit :: Parser Expression
  floatLit = do
    num <- many1 digit
    char '.'
    dec <- many1 digit
    return $ Float (read (num ++ "." ++ dec) :: Float)

  term :: Parser Expression
  term
    = try floatLit <|> (Number <$> integer) <|> stringLit <|> try list <|> try lambda
   <|> object <|> variable <|> parens expression

  variable :: Parser Expression
  variable = Var <$> identifier

  lambda :: Parser Expression
  lambda = do
    reserved "func"
    args <- parens (Token.commaSep lexer identifier)
    Lambda args <$> statement

  object :: Parser Expression
  object = do
    reserved "struct"
    fields <- Token.braces lexer $ sepBy (try $ do
      name <- identifier
      reservedOp ":"
      value <- expression
      return (name, value)
      ) comma
    return $ Struct fields

  makeUnaryOp s = foldr1 (.) <$> some s

  table :: [[Operator String () Identity Expression]]
  table = [
      [Postfix $ makeUnaryOp do
        reservedOp "."
        id <- identifier
        return (`Property` id)],
      [Postfix $ makeUnaryOp do
        reservedOp "("
        args <- sepBy expression comma
        reservedOp ")"
        return (`Call` args)],
      [Postfix $ foldl1 (.) . reverse <$>some do
        reservedOp "["
        arg <- expression
        reservedOp "]"
        return (`Index` arg)],
      [Infix (reservedOp "*" >> return (Bin Mul)) AssocLeft,
      Infix (reservedOp "/" >> return (Bin Div)) AssocLeft],
      [Infix (reservedOp "+" >> return (Bin Add)) AssocLeft,
      Infix (reservedOp "-" >> return (Bin Neg)) AssocLeft]
    ]

  parseLove = runParser parser () ""